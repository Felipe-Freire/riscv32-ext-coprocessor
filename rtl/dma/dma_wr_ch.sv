// DMA write channel (Channel 2: Coprocessor C 128-bit AXI4-Stream -> L2 SRAM).
// Buffers incoming C beats in an internal flip-flop FIFO and only issues AW once enough beats
// for the entire burst are buffered, preventing AXI4 write deadlocks.
// Signals DONE only after receiving the B response for the final burst.
module dma_wr_ch
  import dma_pkg::*;
#(
  parameter int unsigned ChannelId     = 0,
  parameter int unsigned MaxBurstBeats = MAX_BURST_BEATS,
  parameter int unsigned FifoDepth     = FIFO_DEPTH
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // Control from dma_regs
  input  logic                  start_i,
  input  dma_ch_cfg_t           cfg_i,
  output logic                  done_o,
  output logic                  err_o,

  // AXI4-Stream 128-bit slave (C)
  input  logic [C_STREAM_W-1:0] tdata_i,
  input  logic                  tvalid_i,
  output logic                  tready_o,

  // AXI4 Write channels (direct to dma_top master port)
  output dma_axi_aw_t           aw_o,
  output logic                  aw_valid_o,
  input  logic                  aw_ready_i,
  output dma_axi_w_t            w_o,
  output logic                  w_valid_o,
  input  logic                  w_ready_i,
  input  dma_axi_b_t            b_i,
  input  logic                  b_valid_i,
  output logic                  b_ready_o
);

  localparam int unsigned PtrW = $clog2(FifoDepth);

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
  logic                  fifo_full;

  assign fifo_full = (fifo_cnt_q == (PtrW+1)'(FifoDepth));

  always_ff @(posedge clk_i) begin : fifo_data
    if (fifo_push) begin
      fifo_mem[wr_ptr_q] <= tdata_i;
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

  // Write channel FSM
  dma_wr_state_e state_q, state_d;
  logic [7:0]    w_cnt_q, w_cnt_d;
  logic          last_burst_q, last_burst_d;
  logic          has_data;
  logic          zero_len_start;

  assign zero_len_start = start_i &&
                          ((cfg_i.len == 32'd0) || (cfg_i.cnt1 == 32'd0) || (cfg_i.cnt2 == 32'd0));
  assign has_data       = (fifo_cnt_q >= ({1'b0, cmd_len} + 9'd1));

  // Accept incoming C stream beats whenever channel is active and FIFO is not full
  assign tready_o  = (state_q != WrIdle) && (state_q != WrErrDone) && !fifo_full;
  assign fifo_push = tvalid_i && tready_o;

  always_comb begin : wr_fsm
    state_d      = state_q;
    w_cnt_d      = w_cnt_q;
    last_burst_d = last_burst_q;

    aw_valid_o = 1'b0;
    cmd_ready  = 1'b0;
    w_valid_o  = 1'b0;
    fifo_pop   = 1'b0;
    b_ready_o  = 1'b0;
    fifo_flush = 1'b0;
    gen_abort  = 1'b0;
    done_o     = 1'b0;
    err_o      = 1'b0;

    unique case (state_q)
      WrIdle: begin
        if (zero_len_start) begin
          done_o = 1'b1;
        end else if (start_i) begin
          last_burst_d = 1'b0;
          state_d      = WrWaitDat;
        end
      end

      WrWaitDat: begin
        if (cmd_valid && has_data) begin
          state_d = WrReqAw;
        end
      end

      WrReqAw: begin
        aw_valid_o = 1'b1;
        if (aw_ready_i) begin
          cmd_ready    = 1'b1;
          w_cnt_d      = cmd_len;
          last_burst_d = cmd_last;
          state_d      = WrSendW;
        end
      end

      WrSendW: begin
        w_valid_o = 1'b1;
        if (w_ready_i) begin
          fifo_pop = 1'b1;
          if (w_cnt_q == 8'd0) begin
            state_d = WrWaitB;
          end else begin
            w_cnt_d = w_cnt_q - 8'd1;
          end
        end
      end

      WrWaitB: begin
        b_ready_o = 1'b1;
        if (b_valid_i) begin
          if (b_i.resp != AXI_RESP_OKAY) begin
            state_d = WrErrDone;
          end else if (last_burst_q) begin
            done_o  = 1'b1;
            state_d = WrIdle;
          end else begin
            state_d = WrWaitDat;
          end
        end
      end

      WrErrDone: begin
        gen_abort  = 1'b1;
        fifo_flush = 1'b1;
        err_o      = 1'b1;
        state_d    = WrIdle;
      end

      default: state_d = WrIdle;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : wr_state_regs
    if (!rst_ni) begin
      state_q      <= WrIdle;
      w_cnt_q      <= '0;
      last_burst_q <= 1'b0;
    end else begin
      state_q      <= state_d;
      w_cnt_q      <= w_cnt_d;
      last_burst_q <= last_burst_d;
    end
  end

  // Drive AXI4 AW and W channels
  always_comb begin : drive_aw_w
    aw_o        = '0;
    aw_o.id     = AXI_ID_W'(ChannelId);
    aw_o.addr   = cmd_addr;
    aw_o.len    = cmd_len;
    aw_o.size   = AXI_SIZE_16B;
    aw_o.burst  = AXI_BURST_INCR;
    aw_o.lock   = 1'b0;
    aw_o.cache  = 4'b0000;
    aw_o.prot   = 3'b000;
    aw_o.qos    = 4'b0000;
    aw_o.region = 4'b0000;

    w_o         = '0;
    w_o.data    = fifo_mem[rd_ptr_q];
    w_o.strb    = {AXI_STRB_W{1'b1}};
    w_o.last    = (w_cnt_q == 8'd0);
  end

endmodule
