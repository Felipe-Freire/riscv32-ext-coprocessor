// DMA top-level module: 3-channel 3D DMA controller for the riscv32-ext-coprocessor SoC.
//   Channel 0: L2 SRAM (AXI4 128-bit) -> Coprocessor A stream (AXI4-Stream 64-bit)
//   Channel 1: L2 SRAM (AXI4 128-bit) -> Coprocessor B stream (AXI4-Stream 64-bit)
//   Channel 2: Coprocessor C stream (AXI4-Stream 128-bit) -> L2 SRAM (AXI4 128-bit)
//
// Channels 0 and 1 share the AXI4 read channel via a 2-way round-robin arbiter using ARID/RID.
// Channel 2 connects directly to the AXI4 write channel so reads and writes execute in parallel.
module dma_top
  import dma_pkg::*;
#(
  parameter int unsigned RegAddrWidth  = AXIL_ADDR_W,
  parameter int unsigned MaxBurstBeats = MAX_BURST_BEATS,
  parameter int unsigned FifoDepth     = FIFO_DEPTH,
  parameter type         reg_req_t     = dma_axil_req_t,
  parameter type         reg_rsp_t     = dma_axil_rsp_t,
  parameter type         axi_req_t     = dma_axi_req_t,
  parameter type         axi_rsp_t     = dma_axi_rsp_t
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,

  // AXI4-Lite slave: registers (0x4000_1000)
  input  reg_req_t               reg_req_i,
  output reg_rsp_t               reg_rsp_o,

  // AXI4 master, 128-bit: L2 SRAM
  output axi_req_t               axi_req_o,
  input  axi_rsp_t               axi_rsp_i,

  // A stream (Channel 0 -> coprocessor)
  output logic [AB_STREAM_W-1:0] a_tdata_o,
  output logic                   a_tvalid_o,
  input  logic                   a_tready_i,

  // B stream (Channel 1 -> coprocessor)
  output logic [AB_STREAM_W-1:0] b_tdata_o,
  output logic                   b_tvalid_o,
  input  logic                   b_tready_i,

  // C stream (coprocessor -> Channel 2)
  input  logic [C_STREAM_W-1:0]  c_tdata_i,
  input  logic                   c_tvalid_i,
  output logic                   c_tready_o,

  // Interrupt to the RV32 core (MEIP)
  output logic                   irq_o
);

  // Register file signals
  dma_ch_cfg_t [NUM_CHANNELS-1:0] ch_cfg;
  logic        [NUM_CHANNELS-1:0] ch_start;
  logic        [NUM_CHANNELS-1:0] ch_done;
  logic        [NUM_CHANNELS-1:0] ch_err;

  dma_regs #(
    .AddrWidth(RegAddrWidth),
    .reg_req_t(reg_req_t   ),
    .reg_rsp_t(reg_rsp_t   )
  ) u_regs (
    .clk_i     (clk_i    ),
    .rst_ni    (rst_ni   ),
    .reg_req_i (reg_req_i),
    .reg_rsp_o (reg_rsp_o),
    .ch_cfg_o  (ch_cfg   ),
    .ch_start_o(ch_start ),
    .ch_done_i (ch_done  ),
    .ch_err_i  (ch_err   ),
    .irq_o     (irq_o    )
  );

  // Internal read channel signals (Ch0 and Ch1)
  dma_axi_ar_t [1:0] rd_ar;
  logic        [1:0] rd_ar_valid;
  logic        [1:0] rd_ar_ready;
  dma_axi_r_t        rd_r;
  logic        [1:0] rd_r_valid;
  logic        [1:0] rd_r_ready;

  // Channel 0: L2 -> A stream
  dma_rd_ch #(
    .ChannelId    (CH_A         ),
    .MaxBurstBeats(MaxBurstBeats),
    .FifoDepth    (FifoDepth    )
  ) u_ch_a (
    .clk_i     (clk_i          ),
    .rst_ni    (rst_ni         ),
    .start_i   (ch_start[CH_A] ),
    .cfg_i     (ch_cfg[CH_A]   ),
    .done_o    (ch_done[CH_A]  ),
    .err_o     (ch_err[CH_A]   ),
    .ar_o      (rd_ar[0]       ),
    .ar_valid_o(rd_ar_valid[0] ),
    .ar_ready_i(rd_ar_ready[0] ),
    .r_i       (rd_r           ),
    .r_valid_i (rd_r_valid[0]  ),
    .r_ready_o (rd_r_ready[0]  ),
    .tdata_o   (a_tdata_o      ),
    .tvalid_o  (a_tvalid_o     ),
    .tready_i  (a_tready_i     )
  );

  // Channel 1: L2 -> B stream
  dma_rd_ch #(
    .ChannelId    (CH_B         ),
    .MaxBurstBeats(MaxBurstBeats),
    .FifoDepth    (FifoDepth    )
  ) u_ch_b (
    .clk_i     (clk_i          ),
    .rst_ni    (rst_ni         ),
    .start_i   (ch_start[CH_B] ),
    .cfg_i     (ch_cfg[CH_B]   ),
    .done_o    (ch_done[CH_B]  ),
    .err_o     (ch_err[CH_B]   ),
    .ar_o      (rd_ar[1]       ),
    .ar_valid_o(rd_ar_valid[1] ),
    .ar_ready_i(rd_ar_ready[1] ),
    .r_i       (rd_r           ),
    .r_valid_i (rd_r_valid[1]  ),
    .r_ready_o (rd_r_ready[1]  ),
    .tdata_o   (b_tdata_o      ),
    .tvalid_o  (b_tvalid_o     ),
    .tready_i  (b_tready_i     )
  );

  // Internal write channel signals (Ch2)
  dma_axi_aw_t wr_aw;
  logic        wr_aw_valid;
  dma_axi_w_t  wr_w;
  logic        wr_w_valid;
  dma_axi_b_t  wr_b;
  logic        wr_b_ready;

  // Channel 2: C stream -> L2
  dma_wr_ch #(
    .ChannelId    (0            ),
    .MaxBurstBeats(MaxBurstBeats),
    .FifoDepth    (FifoDepth    )
  ) u_ch_c (
    .clk_i     (clk_i             ),
    .rst_ni    (rst_ni            ),
    .start_i   (ch_start[CH_C]    ),
    .cfg_i     (ch_cfg[CH_C]      ),
    .done_o    (ch_done[CH_C]     ),
    .err_o     (ch_err[CH_C]      ),
    .tdata_i   (c_tdata_i         ),
    .tvalid_i  (c_tvalid_i        ),
    .tready_o  (c_tready_o        ),
    .aw_o      (wr_aw             ),
    .aw_valid_o(wr_aw_valid       ),
    .aw_ready_i(axi_rsp_i.aw_ready),
    .w_o       (wr_w              ),
    .w_valid_o (wr_w_valid        ),
    .w_ready_i (axi_rsp_i.w_ready ),
    .b_i       (wr_b              ),
    .b_valid_i (axi_rsp_i.b_valid ),
    .b_ready_o (wr_b_ready        )
  );

  // 2-way round-robin AR arbiter with AXI4 stability lock until ar_ready
  logic ar_prio_q;   // Next preferred channel (0 or 1)
  logic ar_lock_q;   // Holds selection stable while ar_valid && !ar_ready
  logic ar_sel_q;    // Locked channel index
  logic ar_grant;    // Active granted channel (0 or 1)
  logic ar_any_req;

  assign ar_any_req = |rd_ar_valid;

  always_comb begin : ar_arb_comb
    if (ar_lock_q) begin
      ar_grant = ar_sel_q;
    end else if (rd_ar_valid == 2'b11) begin
      ar_grant = ar_prio_q;
    end else if (rd_ar_valid[1]) begin
      ar_grant = 1'b1;
    end else begin
      ar_grant = 1'b0;
    end

    rd_ar_ready           = 2'b00;
    rd_ar_ready[ar_grant] = ar_any_req && axi_rsp_i.ar_ready;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : ar_arb_regs
    if (!rst_ni) begin
      ar_prio_q <= 1'b0;
      ar_lock_q <= 1'b0;
      ar_sel_q  <= 1'b0;
    end else if (ar_any_req) begin
      if (axi_rsp_i.ar_ready) begin
        ar_lock_q <= 1'b0;
        ar_prio_q <= ~ar_grant;
      end else if (!ar_lock_q) begin
        ar_lock_q <= 1'b1;
        ar_sel_q  <= ar_grant;
      end
    end else begin
      ar_lock_q <= 1'b0;
    end
  end

  // R channel demux by RID (ID 0 -> Ch0, ID 1 -> Ch1)
  logic r_sel;
  assign r_sel = axi_rsp_i.r.id[0];

  always_comb begin : r_demux
    rd_r.id    = axi_rsp_i.r.id[AXI_ID_W-1:0];
    rd_r.data  = axi_rsp_i.r.data;
    rd_r.resp  = axi_rsp_i.r.resp;
    rd_r.last  = axi_rsp_i.r.last;

    rd_r_valid        = 2'b00;
    rd_r_valid[r_sel] = axi_rsp_i.r_valid;

    wr_b.id   = axi_rsp_i.b.id[AXI_ID_W-1:0];
    wr_b.resp = axi_rsp_i.b.resp;
  end

  // Drive AXI4 master packed request struct
  always_comb begin : drive_axi_req
    axi_req_o           = '0;

    // Write channels (Channel 2)
    axi_req_o.aw.id     = wr_aw.id;
    axi_req_o.aw.addr   = wr_aw.addr;
    axi_req_o.aw.len    = wr_aw.len;
    axi_req_o.aw.size   = wr_aw.size;
    axi_req_o.aw.burst  = wr_aw.burst;
    axi_req_o.aw.lock   = wr_aw.lock;
    axi_req_o.aw.cache  = wr_aw.cache;
    axi_req_o.aw.prot   = wr_aw.prot;
    axi_req_o.aw.qos    = wr_aw.qos;
    axi_req_o.aw.region = wr_aw.region;
    axi_req_o.aw_valid  = wr_aw_valid;

    axi_req_o.w.data    = wr_w.data;
    axi_req_o.w.strb    = wr_w.strb;
    axi_req_o.w.last    = wr_w.last;
    axi_req_o.w_valid   = wr_w_valid;

    axi_req_o.b_ready   = wr_b_ready;

    // Read channels (Arbitrated Ch0 / Ch1)
    axi_req_o.ar.id     = rd_ar[ar_grant].id;
    axi_req_o.ar.addr   = rd_ar[ar_grant].addr;
    axi_req_o.ar.len    = rd_ar[ar_grant].len;
    axi_req_o.ar.size   = rd_ar[ar_grant].size;
    axi_req_o.ar.burst  = rd_ar[ar_grant].burst;
    axi_req_o.ar.lock   = rd_ar[ar_grant].lock;
    axi_req_o.ar.cache  = rd_ar[ar_grant].cache;
    axi_req_o.ar.prot   = rd_ar[ar_grant].prot;
    axi_req_o.ar.qos    = rd_ar[ar_grant].qos;
    axi_req_o.ar.region = rd_ar[ar_grant].region;
    axi_req_o.ar_valid  = ar_any_req;

    axi_req_o.r_ready   = rd_r_ready[r_sel];
  end

endmodule
