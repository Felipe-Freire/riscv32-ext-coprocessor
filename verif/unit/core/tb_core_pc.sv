// Self-checking testbench for core_pc.
//
// Inputs are driven on the falling edge and the PC is checked against a reference model after
// every rising edge. Directed tests cover each feature, then random stimulus runs against the model.
//
// Run (from the repository root):
//   iverilog -g2012 -o build/tb_core_pc rtl/core/core_pc.sv verif/unit/core/tb_core_pc.sv
//   vvp -n build/tb_core_pc

module tb_core_pc;

  localparam logic [31:0] BootAddr     = 32'h0000_1000;
  localparam int unsigned NumRandCycles = 10000;

  logic        clk;
  logic        rst_n;
  logic        stall;
  logic        pc_set;
  logic [31:0] pc_target;
  logic [31:0] pc;

  logic [31:0] pc_exp;
  int unsigned num_checks;
  int unsigned num_errors;

  core_pc #(
    .BootAddr(BootAddr)
  ) dut (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .stall_i    (stall),
    .pc_set_i   (pc_set),
    .pc_target_i(pc_target),
    .pc_o       (pc)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Reference model: same priority as the spec (reset, then redirect, then stall, then +4).
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_exp <= BootAddr;
    end else if (pc_set) begin
      pc_exp <= pc_target;
    end else if (!stall) begin
      pc_exp <= pc_exp + 32'd4;
    end
  end

  task automatic check(input string what);
    num_checks++;
    if (pc !== pc_exp) begin
      num_errors++;
      $error("[%0t] %s: pc = 0x%08h, expected 0x%08h", $time, what, pc, pc_exp);
    end
  endtask

  // Drive inputs for one cycle, then check the PC after the rising edge.
  task automatic step(input logic st, input logic set, input logic [31:0] tgt, input string what);
    @(negedge clk);
    stall     = st;
    pc_set    = set;
    pc_target = tgt;
    @(posedge clk);
    #1;
    check(what);
  endtask

  task automatic apply_reset();
    @(negedge clk);
    rst_n = 1'b0;
    #1;
    check("reset asserted (asynchronous)");
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
  endtask

  initial begin
    num_checks = 0;
    num_errors = 0;
    rst_n      = 1'b1;
    stall      = 1'b0;
    pc_set     = 1'b0;
    pc_target  = '0;

    // Reset: PC loads BootAddr without waiting for a clock edge
    apply_reset();
    check("after reset");

    // Sequential fetch: +4 per cycle
    repeat (4) step(1'b0, 1'b0, '0, "increment");

    // Stall: PC holds
    repeat (3) step(1'b1, 1'b0, '0, "stall");
    step(1'b0, 1'b0, '0, "resume after stall");

    // Redirect: PC loads the target, then keeps incrementing from it
    step(1'b0, 1'b1, 32'h0000_2000, "redirect");
    step(1'b0, 1'b0, '0, "increment after redirect");

    // Redirect during a stall wins over the stall
    step(1'b1, 1'b1, 32'h0000_3000, "redirect during stall");
    step(1'b1, 1'b0, '0, "stall after redirect");

    // Back-to-back redirects
    step(1'b0, 1'b1, 32'h0000_4000, "back-to-back redirect 1");
    step(1'b0, 1'b1, 32'h0000_5000, "back-to-back redirect 2");

    // Wrap-around at the top of the address space
    step(1'b0, 1'b1, 32'hFFFF_FFF8, "redirect near top");
    step(1'b0, 1'b0, '0, "increment to top");
    step(1'b0, 1'b0, '0, "wrap to 0");

    // Reset in the middle of execution
    step(1'b0, 1'b1, 32'h0000_6000, "redirect before reset");
    apply_reset();
    check("after second reset");

    // Random stimulus against the model
    for (int unsigned i = 0; i < NumRandCycles; i++) begin
      step(($urandom % 4) == 0,                // stall 25% of cycles
           ($urandom % 8) == 0,                // redirect 12.5% of cycles
           {$urandom} & 32'hFFFF_FFFC,         // aligned target
           "random");
    end

    if (num_errors == 0) begin
      $display("TEST PASSED (%0d checks)", num_checks);
    end else begin
      $display("TEST FAILED (%0d errors in %0d checks)", num_errors, num_checks);
    end
    $finish;
  end

  // Watchdog
  initial begin
    #(10 * (NumRandCycles + 1000));
    $fatal(1, "Timeout");
  end

endmodule
