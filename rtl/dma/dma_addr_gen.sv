// DMA 3D address generator and AXI4 4 KiB boundary burst splitter.
// Computes ADDR + p*STRIDE2 + r*STRIDE1 using accumulators (no multipliers) and slices each row
// into legal AXI4 INCR bursts that never cross a 4 KiB boundary.
module dma_addr_gen
  import dma_pkg::*;
#(
  parameter int unsigned MaxBurstBeats = MAX_BURST_BEATS
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Control
  input  logic        start_i,
  input  logic        abort_i,
  input  dma_ch_cfg_t cfg_i,

  // Burst command handshake (AXI4 16-byte beat granularity)
  output logic        cmd_valid_o,
  input  logic        cmd_ready_i,
  output logic [31:0] cmd_addr_o,
  output logic [7:0]  cmd_len_o,   // AXI4 ARLEN / AWLEN (beats - 1)
  output logic        cmd_last_o   // High on the very last burst of the 3D transfer
);

  dma_addr_state_e state_q, state_d;

  logic [31:0] plane_addr_q, plane_addr_d;
  logic [31:0] row_addr_q,   row_addr_d;
  logic [31:0] cur_addr_q,   cur_addr_d;
  logic [27:0] row_beats_q,  row_beats_d;   // Total 16-byte beats per row
  logic [27:0] rem_beats_q,  rem_beats_d;   // Remaining 16-byte beats in current row
  logic [31:0] row_cnt_q,    row_cnt_d;     // Remaining rows in current plane (0-based)
  logic [31:0] plane_cnt_q,  plane_cnt_d;   // Remaining planes (0-based)

  // Combinational 4 KiB boundary and burst length calculation
  logic [8:0]  beats_to_4k;
  logic [27:0] max_beats_ext;
  logic [27:0] beats_4k_ext;
  logic [27:0] burst_beats;
  logic        end_of_row;
  logic        end_of_plane;
  logic        end_of_job;

  // Number of 16-byte beats from cur_addr_q to the next 4 KiB boundary (range 1..256)
  assign beats_to_4k   = 9'd256 - {1'b0, cur_addr_q[11:4]};
  assign beats_4k_ext  = {19'd0, beats_to_4k};
  assign max_beats_ext = 28'(MaxBurstBeats);

  always_comb begin : calc_burst
    logic [27:0] min_rem_4k;

    min_rem_4k  = (rem_beats_q < beats_4k_ext) ? rem_beats_q : beats_4k_ext;
    burst_beats = (min_rem_4k  < max_beats_ext) ? min_rem_4k  : max_beats_ext;

    end_of_row   = (rem_beats_q == burst_beats);
    end_of_plane = end_of_row && (row_cnt_q == 32'd0);
    end_of_job   = end_of_plane && (plane_cnt_q == 32'd0);
  end

  assign cmd_valid_o = (state_q == AddrRun);
  assign cmd_addr_o  = cur_addr_q;
  assign cmd_len_o   = burst_beats[7:0] - 8'd1;
  assign cmd_last_o  = end_of_job;

  // Next-state logic
  always_comb begin : next_state
    logic [27:0] init_beats;

    state_d      = state_q;
    plane_addr_d = plane_addr_q;
    row_addr_d   = row_addr_q;
    cur_addr_d   = cur_addr_q;
    row_beats_d  = row_beats_q;
    rem_beats_d  = rem_beats_q;
    row_cnt_d    = row_cnt_q;
    plane_cnt_d  = plane_cnt_q;

    // Ceiling division by 16 supports both 16-byte and 8-byte aligned row lengths
    init_beats = (cfg_i.len[31:4]) + {27'd0, |cfg_i.len[3:0]};

    unique case (state_q)
      AddrIdle: begin
        if (start_i && (init_beats != 28'd0) && (cfg_i.cnt1 != 32'd0) && (cfg_i.cnt2 != 32'd0)) begin
          state_d      = AddrRun;
          plane_addr_d = {cfg_i.addr[31:4], 4'b0000};
          row_addr_d   = {cfg_i.addr[31:4], 4'b0000};
          cur_addr_d   = {cfg_i.addr[31:4], 4'b0000};
          row_beats_d  = init_beats;
          rem_beats_d  = init_beats;
          row_cnt_d    = cfg_i.cnt1 - 32'd1;
          plane_cnt_d  = cfg_i.cnt2 - 32'd1;
        end
      end

      AddrRun: begin
        if (abort_i) begin
          state_d = AddrIdle;
        end else if (cmd_ready_i) begin
          if (!end_of_row) begin
            cur_addr_d  = cur_addr_q + {burst_beats, 4'b0000};
            rem_beats_d = rem_beats_q - burst_beats;
          end else if (!end_of_plane) begin
            row_addr_d  = row_addr_q + cfg_i.stride1;
            cur_addr_d  = row_addr_q + cfg_i.stride1;
            rem_beats_d = row_beats_q;
            row_cnt_d   = row_cnt_q - 32'd1;
          end else if (!end_of_job) begin
            plane_addr_d = plane_addr_q + cfg_i.stride2;
            row_addr_d   = plane_addr_q + cfg_i.stride2;
            cur_addr_d   = plane_addr_q + cfg_i.stride2;
            rem_beats_d  = row_beats_q;
            row_cnt_d    = cfg_i.cnt1 - 32'd1;
            plane_cnt_d  = plane_cnt_q - 32'd1;
          end else begin
            state_d = AddrIdle;
          end
        end
      end

      default: state_d = AddrIdle;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : state_regs
    if (!rst_ni) begin
      state_q      <= AddrIdle;
      plane_addr_q <= '0;
      row_addr_q   <= '0;
      cur_addr_q   <= '0;
      row_beats_q  <= '0;
      rem_beats_q  <= '0;
      row_cnt_q    <= '0;
      plane_cnt_q  <= '0;
    end else begin
      state_q      <= state_d;
      plane_addr_q <= plane_addr_d;
      row_addr_q   <= row_addr_d;
      cur_addr_q   <= cur_addr_d;
      row_beats_q  <= row_beats_d;
      rem_beats_q  <= rem_beats_d;
      row_cnt_q    <= row_cnt_d;
      plane_cnt_q  <= plane_cnt_d;
    end
  end

endmodule
