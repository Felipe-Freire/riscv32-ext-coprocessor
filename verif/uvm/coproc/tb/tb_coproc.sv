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

  coproc_top #(
    .Dim         (Dim  ),
    .CDataWidth  (CW   ),
    .RegAddrWidth(RegAw)
  ) dut (
    .clk_i           (tb_if.clk_sys        ),
    .rst_ni          (tb_if.rst_n          ),
    .clk_acc_i       (tb_if.clk_acc        ),
    .s_axil_awaddr_i (axil.awaddr[RegAw-1:0]),
    .s_axil_awvalid_i(axil.awvalid         ),
    .s_axil_awready_o(axil.awready         ),
    .s_axil_wdata_i  (axil.wdata           ),
    .s_axil_wstrb_i  (axil.wstrb           ),
    .s_axil_wvalid_i (axil.wvalid          ),
    .s_axil_wready_o (axil.wready          ),
    .s_axil_bresp_o  (axil.bresp           ),
    .s_axil_bvalid_o (axil.bvalid          ),
    .s_axil_bready_i (axil.bready          ),
    .s_axil_araddr_i (axil.araddr[RegAw-1:0]),
    .s_axil_arvalid_i(axil.arvalid         ),
    .s_axil_arready_o(axil.arready         ),
    .s_axil_rdata_o  (axil.rdata           ),
    .s_axil_rresp_o  (axil.rresp           ),
    .s_axil_rvalid_o (axil.rvalid          ),
    .s_axil_rready_i (axil.rready          ),
    .a_tdata_i       (a_if.tdata[AbW-1:0]  ),
    .a_tvalid_i      (a_if.tvalid          ),
    .a_tready_o      (a_if.tready          ),
    .b_tdata_i       (b_if.tdata[AbW-1:0]  ),
    .b_tvalid_i      (b_if.tvalid          ),
    .b_tready_o      (b_if.tready          ),
    .c_tdata_o       (c_tdata              ),
    .c_tvalid_o      (c_if.tvalid          ),
    .c_tready_i      (c_if.tready          )
  );

  initial begin
    uvm_config_db #(virtual coproc_tb_if)::set(null, "uvm_test_top", "tb_vif", tb_if);
    uvm_config_db #(virtual axil_if)::set(null, "uvm_test_top", "axil_vif", axil);
    uvm_config_db #(virtual axis_if)::set(null, "uvm_test_top", "a_vif", a_if);
    uvm_config_db #(virtual axis_if)::set(null, "uvm_test_top", "b_vif", b_if);
    uvm_config_db #(virtual axis_if)::set(null, "uvm_test_top", "c_vif", c_if);
    run_test();
  end

endmodule
