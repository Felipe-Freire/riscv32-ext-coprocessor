// Coprocessor registers: the AXI4-Lite slave through which the core programs a job, in the system
// clock domain. coproc_top carries the launch and the end of a job across to coproc_core.
//
//   Offset  Name    Access   Bits
//   0x00    CTRL    W        0  START: writing 1 launches a job with the current DIM_*; reads 0
//   0x04    STATUS  RO, W1C  0  BUSY (RO): from an accepted START until the job has ended
//                            1  DONE (W1C): set when the last C beat has left the core
//   0x08    DIM_M   RW       DIM_CNT_W-1:0  rows of A and C
//   0x0C    DIM_N   RW       DIM_CNT_W-1:0  columns of B and C
//   0x10    DIM_K   RW       DIM_CNT_W-1:0  columns of A, rows of B
//
// While BUSY, START and writes to DIM_* are ignored: the transaction completes with OKAY but
// changes nothing, so a running job is never altered. An accepted START also clears DONE, so a
// DONE left over from the previous job cannot be mistaken for the new one. Offsets outside the
// map complete with SLVERR, which the core sees as an access fault.
//
// One write and one read can be outstanding at a time; AW and W are accepted together. rst_ni
// is expected to be synchronised to clk_i already, as for every other block in the system domain.
module coproc_regs
  import coproc_pkg::*;
#(
  // Byte address within the block's window (4 KiB).
  parameter int unsigned AddrWidth = 12
) (
  input  logic clk_i,
  input  logic rst_ni,

  // AXI4-Lite slave. AWPROT and ARPROT are not used.
  input  logic [AddrWidth-1:0] s_axil_awaddr_i,
  input  logic                 s_axil_awvalid_i,
  output logic                 s_axil_awready_o,
  input  logic [31:0]          s_axil_wdata_i,
  input  logic [3:0]           s_axil_wstrb_i,
  input  logic                 s_axil_wvalid_i,
  output logic                 s_axil_wready_o,
  output logic [1:0]           s_axil_bresp_o,
  output logic                 s_axil_bvalid_o,
  input  logic                 s_axil_bready_i,
  input  logic [AddrWidth-1:0] s_axil_araddr_i,
  input  logic                 s_axil_arvalid_i,
  output logic                 s_axil_arready_o,
  output logic [31:0]          s_axil_rdata_o,
  output logic [1:0]           s_axil_rresp_o,
  output logic                 s_axil_rvalid_o,
  input  logic                 s_axil_rready_i,

  // Job launch, towards the clock-domain crossing. start_valid_o is held until start_ready_i;
  // the dimensions are stable from START until the job has ended.
  output logic start_valid_o,
  input  logic start_ready_i,
  output dim_t dim_m_o,
  output dim_t dim_n_o,
  output dim_t dim_k_o,

  // End of the job, from the clock-domain crossing: a one-cycle pulse.
  input  logic done_i
);

  localparam logic [1:0] RespOkay   = 2'b00;
  localparam logic [1:0] RespSlvErr = 2'b10;

  localparam logic [AddrWidth-1:0] CtrlOffset   = 'h00;
  localparam logic [AddrWidth-1:0] StatusOffset = 'h04;
  localparam logic [AddrWidth-1:0] DimMOffset   = 'h08;
  localparam logic [AddrWidth-1:0] DimNOffset   = 'h0C;
  localparam logic [AddrWidth-1:0] DimKOffset   = 'h10;

  localparam int unsigned CtrlStartBit  = 0;
  localparam int unsigned StatusBusyBit = 0;
  localparam int unsigned StatusDoneBit = 1;

  logic busy_q, done_q, start_q;
  dim_t dim_m_q, dim_n_q, dim_k_q;

  // Write channel

  logic                 wr_fire, wr_known;
  logic [AddrWidth-1:0] wr_addr;
  logic                 wr_ctrl, wr_status, wr_dim_m, wr_dim_n, wr_dim_k;
  logic                 start_acc, done_clr;
  logic                 b_valid_q;
  logic [1:0]           b_resp_q;

  // AW and W are taken in the same cycle, and only once the previous response has been taken.
  assign wr_fire          = s_axil_awvalid_i && s_axil_wvalid_i && !b_valid_q;
  assign s_axil_awready_o = wr_fire;
  assign s_axil_wready_o  = wr_fire;

  // Registers are word-aligned: the two low address bits are ignored.
  assign wr_addr   = {s_axil_awaddr_i[AddrWidth-1:2], 2'b00};
  assign wr_ctrl   = wr_fire && (wr_addr == CtrlOffset);
  assign wr_status = wr_fire && (wr_addr == StatusOffset);
  assign wr_dim_m  = wr_fire && (wr_addr == DimMOffset);
  assign wr_dim_n  = wr_fire && (wr_addr == DimNOffset);
  assign wr_dim_k  = wr_fire && (wr_addr == DimKOffset);
  assign wr_known  = (wr_addr == CtrlOffset) || (wr_addr == StatusOffset) ||
                     (wr_addr == DimMOffset) || (wr_addr == DimNOffset)   ||
                     (wr_addr == DimKOffset);

  // START and DONE both sit in byte 0.
  assign start_acc = wr_ctrl && s_axil_wstrb_i[0] && s_axil_wdata_i[CtrlStartBit] && !busy_q;
  assign done_clr  = wr_status && s_axil_wstrb_i[0] && s_axil_wdata_i[StatusDoneBit];

  // A DIM_* write takes only the bytes enabled by WSTRB.
  function automatic dim_t write_dim(dim_t old, logic [31:0] wdata, logic [3:0] wstrb);
    dim_t res;
    res = old;
    for (int i = 0; i < int'(DIM_CNT_W); i++) begin
      if (wstrb[i/8]) begin
        res[i] = wdata[i];
      end
    end
    return res;
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin : b_chan
    if (!rst_ni) begin
      b_valid_q <= 1'b0;
      b_resp_q  <= RespOkay;
    end else if (wr_fire) begin
      b_valid_q <= 1'b1;
      b_resp_q  <= wr_known ? RespOkay : RespSlvErr;
    end else if (s_axil_bready_i) begin
      b_valid_q <= 1'b0;
    end
  end

  assign s_axil_bvalid_o = b_valid_q;
  assign s_axil_bresp_o  = b_resp_q;

  // Register file

  always_ff @(posedge clk_i or negedge rst_ni) begin : reg_file
    if (!rst_ni) begin
      busy_q  <= 1'b0;
      done_q  <= 1'b0;
      start_q <= 1'b0;
      dim_m_q <= '0;
      dim_n_q <= '0;
      dim_k_q <= '0;
    end else begin
      // BUSY: an accepted START and the end of that job can never fall in the same cycle, since
      // a START is only accepted while not busy.
      if (start_acc) begin
        busy_q <= 1'b1;
      end else if (done_i) begin
        busy_q <= 1'b0;
      end

      // DONE: the end of a job wins over a clear in the same cycle, so it is never lost.
      if (done_i) begin
        done_q <= 1'b1;
      end else if (start_acc || done_clr) begin
        done_q <= 1'b0;
      end

      // Launch request, held until the crossing takes it.
      if (start_acc) begin
        start_q <= 1'b1;
      end else if (start_ready_i) begin
        start_q <= 1'b0;
      end

      if (wr_dim_m && !busy_q) begin
        dim_m_q <= write_dim(dim_m_q, s_axil_wdata_i, s_axil_wstrb_i);
      end
      if (wr_dim_n && !busy_q) begin
        dim_n_q <= write_dim(dim_n_q, s_axil_wdata_i, s_axil_wstrb_i);
      end
      if (wr_dim_k && !busy_q) begin
        dim_k_q <= write_dim(dim_k_q, s_axil_wdata_i, s_axil_wstrb_i);
      end
    end
  end

  assign start_valid_o = start_q;
  assign dim_m_o       = dim_m_q;
  assign dim_n_o       = dim_n_q;
  assign dim_k_o       = dim_k_q;

  // Read channel

  logic                 rd_fire, rd_known;
  logic [AddrWidth-1:0] rd_addr;
  logic [31:0]          rd_data;
  logic                 r_valid_q;
  logic [31:0]          r_data_q;
  logic [1:0]           r_resp_q;

  assign s_axil_arready_o = !r_valid_q;
  assign rd_fire          = s_axil_arvalid_i && !r_valid_q;
  assign rd_addr          = {s_axil_araddr_i[AddrWidth-1:2], 2'b00};

  always_comb begin : rd_mux
    rd_data  = '0;
    rd_known = 1'b1;
    unique case (rd_addr)
      CtrlOffset: begin
        rd_data = '0;  // START always reads as 0
      end
      StatusOffset: begin
        rd_data[StatusBusyBit] = busy_q;
        rd_data[StatusDoneBit] = done_q;
      end
      DimMOffset: rd_data[DIM_CNT_W-1:0] = dim_m_q;
      DimNOffset: rd_data[DIM_CNT_W-1:0] = dim_n_q;
      DimKOffset: rd_data[DIM_CNT_W-1:0] = dim_k_q;
      default:    rd_known = 1'b0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : r_chan
    if (!rst_ni) begin
      r_valid_q <= 1'b0;
      r_data_q  <= '0;
      r_resp_q  <= RespOkay;
    end else if (rd_fire) begin
      r_valid_q <= 1'b1;
      r_data_q  <= rd_data;
      r_resp_q  <= rd_known ? RespOkay : RespSlvErr;
    end else if (s_axil_rready_i) begin
      r_valid_q <= 1'b0;
    end
  end

  assign s_axil_rvalid_o = r_valid_q;
  assign s_axil_rdata_o  = r_data_q;
  assign s_axil_rresp_o  = r_resp_q;

endmodule
