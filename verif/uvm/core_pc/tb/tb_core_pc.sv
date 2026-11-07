// UVM testbench top for rv32_pc: clock, reset, DUT, interface, run_test().

module tb_core_pc;

  import uvm_pkg::*;
  import core_pc_test_pkg::*;
  `include "uvm_macros.svh"

  localparam logic [31:0] BootAddr = 32'h0000_1000;

  logic clk;

  initial clk = 1'b0;
  always #5ns clk = ~clk;

  core_pc_if pc_if (
    .clk_i(clk)
  );

  logic [31:2] pc_word;

  rv32_pc #(
    .BootAddr(BootAddr)
  ) dut (
    .clk_i      (clk),
    .rst_ni     (pc_if.rst_ni),
    .stall_i    (pc_if.stall),
    .pc_set_i   (pc_if.pc_set),
    .pc_target_i(pc_if.pc_target[31:2]),
    .pc_o       (pc_word)
  );

  assign pc_if.pc = {pc_word, 2'b00};

  initial begin
    pc_if.rst_ni = 1'b1;
    #1ns pc_if.rst_ni = 1'b0;
    repeat (3) @(negedge clk);
    pc_if.rst_ni = 1'b1;
  end

  initial begin
    uvm_config_db #(virtual core_pc_if)::set(null, "uvm_test_top", "vif", pc_if);
    uvm_config_db #(logic [31:0])::set(null, "uvm_test_top", "boot_addr", BootAddr);
    run_test();
  end

endmodule
