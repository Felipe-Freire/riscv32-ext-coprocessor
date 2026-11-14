// Coprocessor top: the block instantiated in soc_top, at 0x4000_2000 on the AXI4-Lite bus and on
// the three DMA streams.
//
//                 clk_i                    |                 clk_acc_i
//                                          |
//   AXI4-Lite --> coproc_regs --start+dims-|-> cdc_2phase --> start_i, dim_*_i  \
//                      ^                   |                                     |
//                      +-------done--------|-- cdc_2phase <-- done_o            coproc_core
//                                          |                                     |
//   A stream  -------------------------->  cdc_fifo_gray  ------------------->  |
//   B stream  -------------------------->  cdc_fifo_gray  ------------------->  |
//   C stream  <--------------------------  cdc_fifo_gray  <-------------------  /
//
// Everything in front of the array runs on clk_i; coproc_core runs on clk_acc_i so it can reach its
// own f_max. The two domains meet only here: an asynchronous FIFO per stream, and a two-phase
// handshake each way for the start of a job (carrying DIM_*) and its end. Nothing else in the SoC
// sees clk_acc_i. Tying clk_acc_i to clk_i is allowed; the crossings then only add latency.
//
// The crossings are the cdc_fifo_gray and cdc_2phase modules of the PULP common_cells library.
//
// Reset: rst_ni is asynchronous and active low, already synchronised to clk_i. The array domain
// gets its own copy, asserted together with rst_ni and released on clk_acc_i. For scan, that
// synchroniser needs the usual test-mode bypass when DFT is added.
module coproc_top
  import coproc_pkg::*;
#(
  parameter int unsigned Dim          = ARRAY_DIM,
  // C stream width. Must be a multiple of ACC_W and divide the Dim accumulators of a tile row.
  parameter int unsigned CDataWidth   = 128,
  // Byte address width of the register port: the block's 4 KiB window.
  parameter int unsigned RegAddrWidth = 12,
  // Depth of each stream FIFO, 2**FifoLogDepth beats. 8 beats cover the pointer round trip
  // through the synchronisers, so a stream can move one beat per cycle.
  parameter int unsigned FifoLogDepth = 3,
  // A and B stream width: one int8 element per PE row / column.
  localparam int unsigned ABDataWidth = Dim * DATA_W
) (
  // System clock domain: the register port and the three streams.
  input  logic clk_i,
  input  logic rst_ni,
  // Array clock domain.
  input  logic clk_acc_i,

  // AXI4-Lite register port; the map is in coproc_regs.
  input  logic [RegAddrWidth-1:0] s_axil_awaddr_i,
  input  logic                    s_axil_awvalid_i,
  output logic                    s_axil_awready_o,
  input  logic [31:0]             s_axil_wdata_i,
  input  logic [3:0]              s_axil_wstrb_i,
  input  logic                    s_axil_wvalid_i,
  output logic                    s_axil_wready_o,
  output logic [1:0]              s_axil_bresp_o,
  output logic                    s_axil_bvalid_o,
  input  logic                    s_axil_bready_i,
  input  logic [RegAddrWidth-1:0] s_axil_araddr_i,
  input  logic                    s_axil_arvalid_i,
  output logic                    s_axil_arready_o,
  output logic [31:0]             s_axil_rdata_o,
  output logic [1:0]              s_axil_rresp_o,
  output logic                    s_axil_rvalid_o,
  input  logic                    s_axil_rready_i,

  // A stream from DMA channel 0: one beat is A[tile row][k], element r in byte lane r.
  input  logic [ABDataWidth-1:0] a_tdata_i,
  input  logic                   a_tvalid_i,
  output logic                   a_tready_o,

  // B stream from DMA channel 1: one beat is B[k][tile column], element c in byte lane c.
  input  logic [ABDataWidth-1:0] b_tdata_i,
  input  logic                   b_tvalid_i,
  output logic                   b_tready_o,

  // C stream to DMA channel 2: tiles in row-major order, each tile row-major, CDataWidth/ACC_W
  // int32 accumulators per beat, lowest column first.
  output logic [CDataWidth-1:0] c_tdata_o,
  output logic                  c_tvalid_o,
  input  logic                  c_tready_i
);

  typedef logic [ABDataWidth-1:0] ab_beat_t;
  typedef logic [CDataWidth-1:0]  c_beat_t;

  // What crosses with the start of a job.
  typedef struct packed {
    dim_t m;
    dim_t n;
    dim_t k;
  } dims_t;

  // Array domain reset

  logic [1:0] rst_acc_sync_q;
  logic       rst_acc_n;

  always_ff @(posedge clk_acc_i or negedge rst_ni) begin : rst_acc_sync
    if (!rst_ni) begin
      rst_acc_sync_q <= 2'b00;
    end else begin
      rst_acc_sync_q <= {rst_acc_sync_q[0], 1'b1};
    end
  end

  assign rst_acc_n = rst_acc_sync_q[1];

  // System domain: registers

  logic  start_valid_sys, start_ready_sys, done_sys;
  dims_t dims_sys;

  coproc_regs #(
    .AddrWidth(RegAddrWidth)
  ) u_regs (
    .clk_i           (clk_i           ),
    .rst_ni          (rst_ni          ),
    .s_axil_awaddr_i (s_axil_awaddr_i ),
    .s_axil_awvalid_i(s_axil_awvalid_i),
    .s_axil_awready_o(s_axil_awready_o),
    .s_axil_wdata_i  (s_axil_wdata_i  ),
    .s_axil_wstrb_i  (s_axil_wstrb_i  ),
    .s_axil_wvalid_i (s_axil_wvalid_i ),
    .s_axil_wready_o (s_axil_wready_o ),
    .s_axil_bresp_o  (s_axil_bresp_o  ),
    .s_axil_bvalid_o (s_axil_bvalid_o ),
    .s_axil_bready_i (s_axil_bready_i ),
    .s_axil_araddr_i (s_axil_araddr_i ),
    .s_axil_arvalid_i(s_axil_arvalid_i),
    .s_axil_arready_o(s_axil_arready_o),
    .s_axil_rdata_o  (s_axil_rdata_o  ),
    .s_axil_rresp_o  (s_axil_rresp_o  ),
    .s_axil_rvalid_o (s_axil_rvalid_o ),
    .s_axil_rready_i (s_axil_rready_i ),
    .start_valid_o   (start_valid_sys ),
    .start_ready_i   (start_ready_sys ),
    .dim_m_o         (dims_sys.m      ),
    .dim_n_o         (dims_sys.n      ),
    .dim_k_o         (dims_sys.k      ),
    .done_i          (done_sys        )
  );

  // Control crossings

  logic  start_valid_acc, start_ready_acc;
  dims_t dims_acc;
  logic  core_start, core_busy, core_done, done_ready_acc;

  // Start of a job, with its dimensions. The core only takes it while idle; coproc_regs keeps
  // BUSY set until the end of the previous job has crossed back, so in practice it is always idle.
  cdc_2phase #(
    .T(dims_t)
  ) u_cdc_start (
    .src_rst_ni (rst_ni         ),
    .src_clk_i  (clk_i          ),
    .src_data_i (dims_sys       ),
    .src_valid_i(start_valid_sys),
    .src_ready_o(start_ready_sys),
    .dst_rst_ni (rst_acc_n      ),
    .dst_clk_i  (clk_acc_i      ),
    .dst_data_o (dims_acc       ),
    .dst_valid_o(start_valid_acc),
    .dst_ready_i(start_ready_acc)
  );

  assign start_ready_acc = !core_busy;
  assign core_start      = start_valid_acc && !core_busy;

  // End of a job: done_o of the core is a one-cycle pulse, and the next one is at least a full
  // job away, so the handshake is always free when it comes (checked below).
  cdc_2phase #(
    .T(logic)
  ) u_cdc_done (
    .src_rst_ni (rst_acc_n     ),
    .src_clk_i  (clk_acc_i     ),
    .src_data_i (1'b0          ),
    .src_valid_i(core_done     ),
    .src_ready_o(done_ready_acc),
    .dst_rst_ni (rst_ni        ),
    .dst_clk_i  (clk_i         ),
    .dst_data_o (              ),
    .dst_valid_o(done_sys      ),
    .dst_ready_i(1'b1          )
  );

  // Stream crossings

  ab_beat_t a_tdata_acc, b_tdata_acc;
  logic     a_tvalid_acc, a_tready_acc, b_tvalid_acc, b_tready_acc;
  c_beat_t  c_tdata_acc;
  logic     c_tvalid_acc, c_tready_acc;

  cdc_fifo_gray #(
    .T        (ab_beat_t        ),
    .LOG_DEPTH(int'(FifoLogDepth))
  ) u_fifo_a (
    .src_rst_ni (rst_ni      ),
    .src_clk_i  (clk_i       ),
    .src_data_i (a_tdata_i   ),
    .src_valid_i(a_tvalid_i  ),
    .src_ready_o(a_tready_o  ),
    .dst_rst_ni (rst_acc_n   ),
    .dst_clk_i  (clk_acc_i   ),
    .dst_data_o (a_tdata_acc ),
    .dst_valid_o(a_tvalid_acc),
    .dst_ready_i(a_tready_acc)
  );

  cdc_fifo_gray #(
    .T        (ab_beat_t        ),
    .LOG_DEPTH(int'(FifoLogDepth))
  ) u_fifo_b (
    .src_rst_ni (rst_ni      ),
    .src_clk_i  (clk_i       ),
    .src_data_i (b_tdata_i   ),
    .src_valid_i(b_tvalid_i  ),
    .src_ready_o(b_tready_o  ),
    .dst_rst_ni (rst_acc_n   ),
    .dst_clk_i  (clk_acc_i   ),
    .dst_data_o (b_tdata_acc ),
    .dst_valid_o(b_tvalid_acc),
    .dst_ready_i(b_tready_acc)
  );

  cdc_fifo_gray #(
    .T        (c_beat_t         ),
    .LOG_DEPTH(int'(FifoLogDepth))
  ) u_fifo_c (
    .src_rst_ni (rst_acc_n   ),
    .src_clk_i  (clk_acc_i   ),
    .src_data_i (c_tdata_acc ),
    .src_valid_i(c_tvalid_acc),
    .src_ready_o(c_tready_acc),
    .dst_rst_ni (rst_ni      ),
    .dst_clk_i  (clk_i       ),
    .dst_data_o (c_tdata_o   ),
    .dst_valid_o(c_tvalid_o  ),
    .dst_ready_i(c_tready_i  )
  );

  // Array domain: the core

  coproc_core #(
    .Dim       (Dim       ),
    .CDataWidth(CDataWidth)
  ) u_core (
    .clk_i     (clk_acc_i   ),
    .rst_ni    (rst_acc_n   ),
    .start_i   (core_start  ),
    .dim_m_i   (dims_acc.m  ),
    .dim_n_i   (dims_acc.n  ),
    .dim_k_i   (dims_acc.k  ),
    .busy_o    (core_busy   ),
    .done_o    (core_done   ),
    .a_tdata_i (a_tdata_acc ),
    .a_tvalid_i(a_tvalid_acc),
    .a_tready_o(a_tready_acc),
    .b_tdata_i (b_tdata_acc ),
    .b_tvalid_i(b_tvalid_acc),
    .b_tready_o(b_tready_acc),
    .c_tdata_o (c_tdata_acc ),
    .c_tvalid_o(c_tvalid_acc),
    .c_tready_i(c_tready_acc)
  );

`ifndef SYNTHESIS
  // The end of a job is never dropped: the previous end has been acknowledged long before.
  done_not_dropped : assert property (@(posedge clk_acc_i) disable iff (!rst_acc_n)
    core_done |-> done_ready_acc)
    else $error("coproc_top: end of job lost in the clock-domain crossing");

  // The start of a job only arrives while the core is idle.
  start_when_idle : assert property (@(posedge clk_acc_i) disable iff (!rst_acc_n)
    start_valid_acc |-> !core_busy)
    else $error("coproc_top: job started while the core was busy");
`endif

endmodule
