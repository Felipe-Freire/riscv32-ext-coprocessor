// DMA register file: AXI4-Lite 32-bit slave mapped at 0x4000_1000 (4 KiB window).
// Replicates 8 registers per channel at offset 0x20 * n (n = 0, 1, 2).
// Follows the same single-outstanding handshake style as coproc_regs.sv.
module dma_regs
  import dma_pkg::*;
#(
  parameter int unsigned AddrWidth = AXIL_ADDR_W,
  parameter type         reg_req_t = dma_axil_req_t,
  parameter type         reg_rsp_t = dma_axil_rsp_t
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,

  // AXI4-Lite slave (packed structs)
  input  reg_req_t                      reg_req_i,
  output reg_rsp_t                      reg_rsp_o,

  // Per-channel configuration and control outputs
  output dma_ch_cfg_t [NUM_CHANNELS-1:0] ch_cfg_o,
  output logic        [NUM_CHANNELS-1:0] ch_start_o,

  // Per-channel completion and error pulses (1 cycle each)
  input  logic        [NUM_CHANNELS-1:0] ch_done_i,
  input  logic        [NUM_CHANNELS-1:0] ch_err_i,

  // Level-sensitive interrupt to the RV32 core (MEIP)
  output logic                          irq_o
);

  // Per-channel state
  dma_ch_cfg_t [NUM_CHANNELS-1:0] cfg_q;
  logic        [NUM_CHANNELS-1:0] irq_en_q;
  logic        [NUM_CHANNELS-1:0] busy_q;
  logic        [NUM_CHANNELS-1:0] done_q;
  logic        [NUM_CHANNELS-1:0] err_q;

  // Byte-masked 32-bit register update helper
  function automatic logic [31:0] write_masked(
    input logic [31:0] old_val,
    input logic [31:0] wdata,
    input logic [3:0]  wstrb
  );
    logic [31:0] res;
    res = old_val;
    for (int i = 0; i < 4; i++) begin
      if (wstrb[i]) begin
        res[i*8 +: 8] = wdata[i*8 +: 8];
      end
    end
    return res;
  endfunction

  // Write channel (AW and W accepted together, one outstanding write at a time)
  logic                 wr_fire;
  logic                 wr_known;
  logic [AddrWidth-1:0] wr_addr;
  logic [1:0]           wr_ch;
  logic [4:0]           wr_off;
  logic                 b_valid_q;
  logic [1:0]           b_resp_q;

  assign wr_fire  = reg_req_i.aw_valid && reg_req_i.w_valid && !b_valid_q;
  assign wr_addr  = {reg_req_i.aw.addr[AddrWidth-1:2], 2'b00};
  assign wr_ch    = wr_addr[6:5];
  assign wr_off   = wr_addr[4:0];
  assign wr_known = (wr_addr[AddrWidth-1:7] == '0) && (wr_ch < NUM_CHANNELS);

  always_ff @(posedge clk_i or negedge rst_ni) begin : b_chan
    if (!rst_ni) begin
      b_valid_q <= 1'b0;
      b_resp_q  <= AXI_RESP_OKAY;
    end else if (wr_fire) begin
      b_valid_q <= 1'b1;
      b_resp_q  <= wr_known ? AXI_RESP_OKAY : AXI_RESP_SLVERR;
    end else if (reg_req_i.b_ready) begin
      b_valid_q <= 1'b0;
    end
  end

  // Per-channel register updates
  logic [NUM_CHANNELS-1:0] start_acc;

  always_comb begin : dec_start
    start_acc = '0;
    for (int c = 0; c < NUM_CHANNELS; c++) begin
      if (wr_fire && wr_known && (wr_ch == c[1:0]) && (wr_off == REG_CTRL) &&
          reg_req_i.w.strb[0] && reg_req_i.w.data[CTRL_START_BIT] && !busy_q[c]) begin
        start_acc[c] = 1'b1;
      end
    end
  end

  assign ch_start_o = start_acc;

  always_ff @(posedge clk_i or negedge rst_ni) begin : reg_file
    if (!rst_ni) begin
      cfg_q    <= '0;
      irq_en_q <= '0;
      busy_q   <= '0;
      done_q   <= '0;
      err_q    <= '0;
    end else begin
      for (int c = 0; c < NUM_CHANNELS; c++) begin
        logic ch_wr;
        logic done_clr;
        logic err_clr;

        ch_wr    = wr_fire && wr_known && (wr_ch == c[1:0]);
        done_clr = ch_wr && (wr_off == REG_STATUS) &&
                   reg_req_i.w.strb[0] && reg_req_i.w.data[STAT_DONE_BIT];
        err_clr  = ch_wr && (wr_off == REG_STATUS) &&
                   reg_req_i.w.strb[0] && reg_req_i.w.data[STAT_ERR_BIT];

        // BUSY: set on accepted START, cleared on DONE or ERR
        if (start_acc[c]) begin
          busy_q[c] <= 1'b1;
        end else if (ch_done_i[c] || ch_err_i[c]) begin
          busy_q[c] <= 1'b0;
        end

        // DONE (W1C): hardware completion wins over software clear in the same cycle
        if (ch_done_i[c]) begin
          done_q[c] <= 1'b1;
        end else if (start_acc[c] || done_clr) begin
          done_q[c] <= 1'b0;
        end

        // ERR (W1C): hardware error wins over software clear in the same cycle
        if (ch_err_i[c]) begin
          err_q[c] <= 1'b1;
        end else if (start_acc[c] || err_clr) begin
          err_q[c] <= 1'b0;
        end

        // Configuration registers: writes ignored while BUSY
        if (ch_wr && !busy_q[c]) begin
          unique case (wr_off)
            REG_ADDR:    cfg_q[c].addr    <= write_masked(cfg_q[c].addr,    reg_req_i.w.data, reg_req_i.w.strb);
            REG_LEN:     cfg_q[c].len     <= write_masked(cfg_q[c].len,     reg_req_i.w.data, reg_req_i.w.strb);
            REG_CNT1:    cfg_q[c].cnt1    <= write_masked(cfg_q[c].cnt1,    reg_req_i.w.data, reg_req_i.w.strb);
            REG_STRIDE1: cfg_q[c].stride1 <= write_masked(cfg_q[c].stride1, reg_req_i.w.data, reg_req_i.w.strb);
            REG_CNT2:    cfg_q[c].cnt2    <= write_masked(cfg_q[c].cnt2,    reg_req_i.w.data, reg_req_i.w.strb);
            REG_STRIDE2: cfg_q[c].stride2 <= write_masked(cfg_q[c].stride2, reg_req_i.w.data, reg_req_i.w.strb);
            REG_CTRL: begin
              if (reg_req_i.w.strb[0]) begin
                irq_en_q[c] <= reg_req_i.w.data[CTRL_IRQ_EN_BIT];
              end
            end
            default: ;
          endcase
        end
      end
    end
  end

  assign ch_cfg_o = cfg_q;
  assign irq_o    = |(irq_en_q & (done_q | err_q));

  // Read channel (one outstanding read at a time)
  logic                 rd_fire;
  logic                 rd_known;
  logic [AddrWidth-1:0] rd_addr;
  logic [1:0]           rd_ch;
  logic [4:0]           rd_off;
  logic [31:0]          rd_data;
  logic                 r_valid_q;
  logic [31:0]          r_data_q;
  logic [1:0]           r_resp_q;

  assign rd_fire  = reg_req_i.ar_valid && !r_valid_q;
  assign rd_addr  = {reg_req_i.ar.addr[AddrWidth-1:2], 2'b00};
  assign rd_ch    = rd_addr[6:5];
  assign rd_off   = rd_addr[4:0];
  assign rd_known = (rd_addr[AddrWidth-1:7] == '0) && (rd_ch < NUM_CHANNELS);

  always_comb begin : rd_mux
    rd_data = '0;
    if (rd_known) begin
      unique case (rd_off)
        REG_ADDR:    rd_data = cfg_q[rd_ch].addr;
        REG_LEN:     rd_data = cfg_q[rd_ch].len;
        REG_CNT1:    rd_data = cfg_q[rd_ch].cnt1;
        REG_STRIDE1: rd_data = cfg_q[rd_ch].stride1;
        REG_CNT2:    rd_data = cfg_q[rd_ch].cnt2;
        REG_STRIDE2: rd_data = cfg_q[rd_ch].stride2;
        REG_CTRL: begin
          // START always reads as 0
          rd_data[CTRL_IRQ_EN_BIT] = irq_en_q[rd_ch];
        end
        REG_STATUS: begin
          rd_data[STAT_BUSY_BIT] = busy_q[rd_ch];
          rd_data[STAT_DONE_BIT] = done_q[rd_ch];
          rd_data[STAT_ERR_BIT]  = err_q[rd_ch];
        end
        default: rd_data = '0;
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : r_chan
    if (!rst_ni) begin
      r_valid_q <= 1'b0;
      r_data_q  <= '0;
      r_resp_q  <= AXI_RESP_OKAY;
    end else if (rd_fire) begin
      r_valid_q <= 1'b1;
      r_data_q  <= rd_data;
      r_resp_q  <= rd_known ? AXI_RESP_OKAY : AXI_RESP_SLVERR;
    end else if (reg_req_i.r_ready) begin
      r_valid_q <= 1'b0;
    end
  end

  // Drive packed AXI4-Lite response struct
  always_comb begin : drive_rsp
    reg_rsp_o          = '0;
    reg_rsp_o.aw_ready = wr_fire;
    reg_rsp_o.w_ready  = wr_fire;
    reg_rsp_o.b_valid  = b_valid_q;
    reg_rsp_o.b.resp   = b_resp_q;
    reg_rsp_o.ar_ready = !r_valid_q;
    reg_rsp_o.r_valid  = r_valid_q;
    reg_rsp_o.r.data   = r_data_q;
    reg_rsp_o.r.resp   = r_resp_q;
  end

endmodule
