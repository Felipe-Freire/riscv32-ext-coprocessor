// Clocks and reset of the coprocessor testbench. The test sets the periods and the phase of
// clk_acc_i before clocks_on; the periods may also change between jobs. reset() is asynchronous
// on assertion and releases on a falling edge of clk_sys.
interface coproc_tb_if;

  realtime sys_period = 10ns;
  realtime acc_period = 10ns;
  realtime acc_phase  = 0ns;
  bit      clocks_on  = 1'b0;

  logic clk_sys = 1'b0;
  logic clk_acc = 1'b0;
  logic rst_n   = 1'b0;

  task automatic reset(int unsigned cycles);
    rst_n = 1'b0;
    repeat (cycles) @(posedge clk_sys);
    @(negedge clk_sys);
    rst_n = 1'b1;
  endtask

endinterface
