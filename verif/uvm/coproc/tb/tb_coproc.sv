// UVM testbench top for coproc_top: the two clocks, the interfaces, the DUT and run_test().
module tb_coproc;

  import uvm_pkg::*;
  import axis_agent_pkg::AXIS_MAX_DW;
  import coproc_test_pkg::*;
  `include "uvm_macros.svh"

  localparam int unsigned Dim   = coproc_pkg::ARRAY_DIM;
  localparam int unsigned AbW   = Dim * coproc_pkg::DATA_W;
  localparam int unsigned CW    = 128;
  localparam int unsigned RegAw = 12;

  coproc_tb_if tb_if ();

  initial begin : gen_clk_sys
    wait (tb_if.clocks_on);
    forever #(tb_if.sys_period / 2) tb_if.clk_sys = ~tb_if.clk_sys;
  end

  initial begin : gen_clk_acc
    wait (tb_if.clocks_on);
    #(tb_if.acc_phase);
    forever #(tb_if.acc_period / 2) tb_if.clk_acc = ~tb_if.clk_acc;
  end

  axil_if axil (.clk_i(tb_if.clk_sys), .rst_ni(tb_if.rst_n));
  axis_if a_if (.clk_i(tb_if.clk_sys), .rst_ni(tb_if.rst_n));
  axis_if b_if (.clk_i(tb_if.clk_sys), .rst_ni(tb_if.rst_n));
  axis_if c_if (.clk_i(tb_if.clk_sys), .rst_ni(tb_if.rst_n));

  logic [CW-1:0] c_tdata;

  assign c_if.tdata = AXIS_MAX_DW'(c_tdata);

  // The agents drive on the clock edge; their outputs reach the DUT InDelay later, as the input
  // delay of the synthesis constraints assumes. At gate level with SDF, an input that changed on
  // the edge itself would break the hold time of the flops it reaches through a short path (the
  // source registers of the CDC FIFOs take a_tdata and b_tdata straight in). The monitors sample
  // the interfaces, so they see the same handshakes as the DUT.
  localparam time InDelay = 1ns;

  logic [RegAw-1:0] awaddr_d, araddr_d;
  logic [31:0]      wdata_d;
  logic [3:0]       wstrb_d;
  logic             awvalid_d, wvalid_d, bready_d, arvalid_d, rready_d;
  logic [AbW-1:0]   a_tdata_d, b_tdata_d;
  logic             a_tvalid_d, b_tvalid_d, c_tready_d;

  assign #InDelay {awaddr_d, awvalid_d, wdata_d, wstrb_d, wvalid_d, bready_d, araddr_d, arvalid_d,
                   rready_d} = {axil.awaddr[RegAw-1:0], axil.awvalid, axil.wdata, axil.wstrb,
                                axil.wvalid, axil.bready, axil.araddr[RegAw-1:0], axil.arvalid,
                                axil.rready};
  assign #InDelay {a_tdata_d, a_tvalid_d, b_tdata_d, b_tvalid_d, c_tready_d} =
                  {a_if.tdata[AbW-1:0], a_if.tvalid, b_if.tdata[AbW-1:0], b_if.tvalid, c_if.tready};

  // At gate level (make gls defines GLS) the netlist has no parameters: it was synthesized with
  // the defaults, which are these values.
  coproc_top
`ifndef GLS
  #(
    .Dim         (Dim  ),
    .CDataWidth  (CW   ),
    .RegAddrWidth(RegAw)
  )
`endif
  dut (
    .clk_i           (tb_if.clk_sys        ),
    .rst_ni          (tb_if.rst_n          ),
    .clk_acc_i       (tb_if.clk_acc        ),
    .s_axil_awaddr_i (awaddr_d             ),
    .s_axil_awvalid_i(awvalid_d            ),
    .s_axil_awready_o(axil.awready         ),
    .s_axil_wdata_i  (wdata_d              ),
    .s_axil_wstrb_i  (wstrb_d              ),
    .s_axil_wvalid_i (wvalid_d             ),
    .s_axil_wready_o (axil.wready          ),
    .s_axil_bresp_o  (axil.bresp           ),
    .s_axil_bvalid_o (axil.bvalid          ),
    .s_axil_bready_i (bready_d             ),
    .s_axil_araddr_i (araddr_d             ),
    .s_axil_arvalid_i(arvalid_d            ),
    .s_axil_arready_o(axil.arready         ),
    .s_axil_rdata_o  (axil.rdata           ),
    .s_axil_rresp_o  (axil.rresp           ),
    .s_axil_rvalid_o (axil.rvalid          ),
    .s_axil_rready_i (rready_d             ),
    .a_tdata_i       (a_tdata_d            ),
    .a_tvalid_i      (a_tvalid_d           ),
    .a_tready_o      (a_if.tready          ),
    .b_tdata_i       (b_tdata_d            ),
    .b_tvalid_i      (b_tvalid_d           ),
    .b_tready_o      (b_if.tready          ),
    .c_tdata_o       (c_tdata              ),
    .c_tvalid_o      (c_if.tvalid          ),
    .c_tready_i      (c_tready_d           )
  );

  initial begin
    uvm_config_db #(virtual coproc_tb_if)::set(null, "uvm_test_top", "tb_vif", tb_if);
    uvm_config_db #(virtual axil_if)::set(null, "uvm_test_top", "axil_vif", axil);
    uvm_config_db #(virtual axis_if)::set(null, "uvm_test_top", "a_vif", a_if);
    uvm_config_db #(virtual axis_if)::set(null, "uvm_test_top", "b_vif", b_if);
    uvm_config_db #(virtual axis_if)::set(null, "uvm_test_top", "c_vif", c_if);
    run_test();
  end

  // UVM ends with exit status 0 even after UVM_ERROR or UVM_FATAL: turn them into a simulator
  // error, so the run fails (verif/README.md). The counts are read here, not in declarations,
  // which would run once at time 0.
  final begin : exit_status
    uvm_report_server server;
    int unsigned      errors;
    server = uvm_report_server::get_server();
    errors = server.get_severity_count(UVM_ERROR) + server.get_severity_count(UVM_FATAL);
    if (errors != 0) $error("%0d UVM_ERROR or UVM_FATAL reports", errors);
  end

endmodule
