// Signals of the core_pc ports. The testbench top drives the reset; the driver drives the rest
// of the inputs through drv_cb.

interface core_pc_if (
  input logic clk_i
);

  logic        rst_ni;
  logic        stall;
  logic        pc_set;
  logic [31:0] pc_target;
  logic [31:0] pc;

  clocking drv_cb @(posedge clk_i);
    default input #1step output #1;
    output stall, pc_set, pc_target;
  endclocking

  clocking mon_cb @(posedge clk_i);
    default input #1step;
    input rst_ni, stall, pc_set, pc_target, pc;
  endclocking

endinterface
