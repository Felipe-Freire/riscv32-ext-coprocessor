// DMA read channel (Channels 0 and 1: L2 SRAM -> A / B 64-bit AXI4-Stream).
// Fetches 128-bit AXI4 INCR bursts into an internal flip-flop FIFO and unpacks each 128-bit word
// into two 64-bit stream beats (low half [63:0] first, high half [127:64] second).
// Signals DONE only after the last 64-bit beat is accepted by the coprocessor stream.
module dma_rd_ch
  import dma_pkg::*;
#(
  parameter int unsigned ChannelId     = 0,
  parameter int unsigned MaxBurstBeats = MAX_BURST_BEATS,
  parameter int unsigned FifoDepth     = FIFO_DEPTH
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,

  // Control from dma_regs
  input  logic                   start_i,
  input  dma_ch_cfg_t            cfg_i,
  output logic                   done_o,
  output logic                   err_o,

  // AXI4 Read Address channel (to dma_top arbiter)
  output dma_axi_ar_t            ar_o,
  output logic                   ar_valid_o,
  input  logic                   ar_ready_i,

  // AXI4 Read Data channel (from dma_top demux)
  input  dma_axi_r_t             r_i,
  input  logic                   r_valid_i,
  output logic                   r_ready_o,

  // AXI4-Stream 64-bit master (A or B)
  output logic [AB_STREAM_W-1:0] tdata_o,
  output logic                   tvalid_o,
  input  logic                   tready_i
);

  localparam int unsigned PtrW = $clog2(FifoDepth);

  dma_rd_state_e state_q, state_d;

  // 3D address generator instance
  logic        cmd_valid, cmd_ready, cmd_last, gen_abort;
  logic [31:0] cmd_addr;
  logic [7:0]  cmd_len;

  dma_addr_gen #(
    .MaxBurstBeats(MaxBurstBeats)
  ) u_addr_gen (
    .clk_i      (clk_i    ),
    .rst_ni     (rst_ni   ),
    .start_i    (start_i  ),
    .abort_i    (gen_abort),
    .cfg_i      (cfg_i    ),
    .cmd_valid_o(cmd_valid),
    .cmd_ready_i(cmd_ready),
    .cmd_addr_o (cmd_addr ),
    .cmd_len_o  (cmd_len  ),
    .cmd_last_o (cmd_last )
  );

  // Internal synchronous 128-bit FIFO (flip-flop array, datapath unreset per rtl/README.md)
  logic [AXI_DATA_W-1:0] fifo_mem [0:FifoDepth-1];
  logic [PtrW-1:0]       wr_ptr_q, rd_ptr_q;
  logic [PtrW:0]         fifo_cnt_q;
  logic                  fifo_push, fifo_pop, fifo_flush;
  logic                  fifo_empty;
  logic [PtrW:0]         fifo_free;

  assign fifo_empty = (fifo_cnt_q == '0);
  assign fifo_free  = (PtrW+1)'(FifoDepth) - fifo_cnt_q;

  always_ff @(posedge clk_i) begin : fifo_data
    if (fifo_push) begin
      fifo_mem[wr_ptr_q] <= r_i.data;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : fifo_ctrl
    if (!rst_ni) begin
      wr_ptr_q   <= '0;
      rd_ptr_q   <= '0;
      fifo_cnt_q <= '0;
    end else if (fifo_flush) begin
      wr_ptr_q   <= '0;
      rd_ptr_q   <= '0;
      fifo_cnt_q <= '0;
    end else begin
      if (fifo_push) begin
        wr_ptr_q <= wr_ptr_q + 1'b1;
      end
      if (fifo_pop) begin
        rd_ptr_q <= rd_ptr_q + 1'b1;
      end
      unique case ({fifo_push, fifo_pop})
        2'b10:   fifo_cnt_q <= fifo_cnt_q + 1'b1;
        2'b01:   fifo_cnt_q <= fifo_cnt_q - 1'b1;
        default: fifo_cnt_q <= fifo_cnt_q;
      endcase
    end
  end

  // 128-bit to 64-bit stream unpacker (low half first; handles odd 64-bit row lengths too)
  logic        half_sel_q;
  logic [28:0] row_beats64_rem_q;
  logic [28:0] row_beats64_cfg;
  logic        stream_fire;
  logic        last_row_beat64;

  assign row_beats64_cfg = cfg_i.len[31:3];
  assign tvalid_o        = !fifo_empty && (state_q != RdIdle) && (state_q != RdErrDone);
  assign tdata_o         = half_sel_q ? fifo_mem[rd_ptr_q][127:64] : fifo_mem[rd_ptr_q][63:0];
  assign stream_fire     = tvalid_o && tready_i;
  assign last_row_beat64 = (row_beats64_rem_q == 29'd1);

  // Pop the 128-bit word after the high half OR if this is an odd final 64-bit beat of a row
  assign fifo_pop = stream_fire && (half_sel_q || last_row_beat64);

  always_ff @(posedge clk_i or negedge rst_ni) begin : unpacker_ctrl
    if (!rst_ni) begin
      half_sel_q        <= 1'b0;
      row_beats64_rem_q <= '0;
    end else if (fifo_flush) begin
      half_sel_q        <= 1'b0;
      row_beats64_rem_q <= '0;
    end else if (start_i) begin
      half_sel_q        <= 1'b0;
      row_beats64_rem_q <= row_beats64_cfg;
    end else if (stream_fire) begin
      if (last_row_beat64) begin
        half_sel_q        <= 1'b0;
        row_beats64_rem_q <= row_beats64_cfg;
      end else begin
        half_sel_q        <= ~half_sel_q;
        row_beats64_rem_q <= row_beats64_rem_q - 29'd1;
      end
    end
  end

  // Read channel FSM
 
  logic          last_burst_q, last_burst_d;
  logic          err_seen_q,   err_seen_d;
  logic          has_space;
  logic          zero_len_start;

  assign zero_len_start = start_i &&
                          ((cfg_i.len == 32'd0) || (cfg_i.cnt1 == 32'd0) || (cfg_i.cnt2 == 32'd0));
  assign has_space      = (fifo_free >= ({1'b0, cmd_len} + 9'd1));

  always_comb begin : rd_fsm
    state_d      = state_q;
    last_burst_d = last_burst_q;
    err_seen_d   = err_seen_q;

    ar_valid_o = 1'b0;
    cmd_ready  = 1'b0;
    r_ready_o  = 1'b0;
    fifo_push  = 1'b0;
    fifo_flush = 1'b0;
    gen_abort  = 1'b0;
    done_o     = 1'b0;
    err_o      = 1'b0;

    unique case (state_q)
      RdIdle: begin
        if (zero_len_start) begin
          done_o = 1'b1;
        end else if (start_i) begin
          err_seen_d   = 1'b0;
          last_burst_d = 1'b0;
          state_d      = RdReqAr;
        end
      end

      RdReqAr: begin
        // Only issue AR when the FIFO can absorb the entire burst without stalling R
        if (cmd_valid && has_space) begin
          ar_valid_o = 1'b1;
          if (ar_ready_i) begin
            cmd_ready    = 1'b1;
            last_burst_d = cmd_last;
            state_d      = RdWaitR;
          end
        end
      end

      RdWaitR: begin
        r_ready_o = 1'b1;
        if (r_valid_i) begin
          if (r_i.resp != AXI_RESP_OKAY) begin
            err_seen_d = 1'b1;
          end else if (!err_seen_q) begin
            fifo_push = 1'b1;
          end

          if (r_i.last) begin
            if (err_seen_q || (r_i.resp != AXI_RESP_OKAY)) begin
              state_d = RdErrDone;
            end else if (last_burst_q) begin
              state_d = RdDrain;
            end else begin
              state_d = RdReqAr;
            end
          end
        end
      end

      RdDrain: begin
        // Wait until the last 64-bit beat has been accepted by the coprocessor stream
        if (fifo_empty) begin
          done_o  = 1'b1;
          state_d = RdIdle;
        end
      end

      RdErrDone: begin
        gen_abort  = 1'b1;
        fifo_flush = 1'b1;
        err_o      = 1'b1;
        state_d    = RdIdle;
      end

      default: state_d = RdIdle;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : rd_state_regs
    if (!rst_ni) begin
      state_q      <= RdIdle;
      last_burst_q <= 1'b0;
      err_seen_q   <= 1'b0;
    end else begin
      state_q      <= state_d;
      last_burst_q <= last_burst_d;
      err_seen_q   <= err_seen_d;
    end
  end

  // Constant AXI4 AR fields
  always_comb begin : drive_ar
    ar_o        = '0;
    ar_o.id     = AXI_ID_W'(ChannelId);
    ar_o.addr   = cmd_addr;
    ar_o.len    = cmd_len;
    ar_o.size   = AXI_SIZE_16B;
    ar_o.burst  = AXI_BURST_INCR;
    ar_o.lock   = 1'b0;
    ar_o.cache  = 4'b0000;
    ar_o.prot   = 3'b000;
    ar_o.qos    = 4'b0000;
    ar_o.region = 4'b0000;
  end

endmodule
