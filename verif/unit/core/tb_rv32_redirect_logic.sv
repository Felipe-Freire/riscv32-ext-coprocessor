// rv32_redirect_logic: redirect on a misprediction or JALR, its target, and misaligned targets.
module tb_rv32_redirect_logic;
  import rv32_pkg::*;

  logic            valid, branch, jalr, pred_taken, taken, imm_bit1;
  logic [XLEN-1:2] alt_pc;
  logic [XLEN-1:0] adder;
  logic            ex_redirect, misaligned;
  logic [XLEN-1:2] ex_target;

  int errors = 0, checks = 0;

  rv32_redirect_logic dut (
    .valid_i       (valid),
    .branch_i      (branch),
    .jalr_i        (jalr),
    .pred_taken_i  (pred_taken),
    .taken_i       (taken),
    .alt_pc_i      (alt_pc),
    .adder_i       (adder),
    .imm_bit1_i    (imm_bit1),
    .ex_redirect_o (ex_redirect),
    .ex_target_o   (ex_target),
    .misaligned_o  (misaligned)
  );

  // Setup inputs
  task automatic setup_test (
    logic            valid_i,
    logic            branch_i,
    logic            jalr_i,
    logic            pred_taken_i,
    logic            taken_i,
    logic [XLEN-1:0] alt_pc_i,
    logic [XLEN-1:0] adder_i,
    logic            imm_bit1_i
  );
    valid      = valid_i;
    branch     = branch_i;
    jalr       = jalr_i;
    pred_taken = pred_taken_i;
    taken      = taken_i;
    alt_pc     = alt_pc_i[XLEN-1:2];
    adder      = adder_i;
    imm_bit1   = imm_bit1_i;
  endtask

  // Report errors
  task automatic fail(string msg);
    errors++;
    if (errors <= 10)
      $display("FAIL: %s", msg);
  endtask

  // Check all outputs; the target only matters with a redirect
  task automatic check (
    logic            expected_redirect,
    logic [XLEN-1:0] expected_target,
    logic            expected_misaligned
  );
    #1;
    checks++;

    if (ex_redirect !== expected_redirect)
      fail($sformatf("ex_redirect: expected=%b dut=%b",
                     expected_redirect, ex_redirect));

    if (expected_redirect && ex_target !== expected_target[XLEN-1:2])
      fail($sformatf("ex_target: expected=%h dut=%h",
                     expected_target, {ex_target, 2'b00}));

    if (misaligned !== expected_misaligned)
      fail($sformatf("misaligned: expected=%b dut=%b",
                     expected_misaligned, misaligned));
  endtask

  initial begin

    // Not a control transfer: no redirect
    setup_test(1, 0, 0, 0, 1, 'h0000_1000, 'h0000_2000, 0);
    check(0, 'h0, 0);

    // Branch predicted not taken, not taken: no redirect
    setup_test(1, 1, 0, 0, 0, 'h0000_1000, 'h0000_2000, 0);
    check(0, 'h0, 0);

    // Branch predicted not taken, taken: redirect to the target (alt_pc)
    setup_test(1, 1, 0, 0, 1, 'h0000_1000, 'h0000_2000, 0);
    check(1, 'h0000_1000, 0);

    // Branch predicted taken (backward), taken: ID already redirected
    setup_test(1, 1, 0, 1, 1, 'h0000_0104, 'h0000_2000, 0);
    check(0, 'h0, 0);

    // Branch predicted taken, not taken: redirect to the fall-through (alt_pc)
    setup_test(1, 1, 0, 1, 0, 'h0000_0104, 'h0000_2000, 0);
    check(1, 'h0000_0104, 0);

    // JALR: redirect to rs1 + imm, bit 0 cleared
    setup_test(1, 0, 1, 0, 0, 'h0000_0104, 'h0000_2001, 0);
    check(1, 'h0000_2000, 0);

    // JALR with a misaligned target
    setup_test(1, 0, 1, 0, 0, 'h0000_0104, 'h0000_2002, 0);
    check(1, 'h0000_2000, 1);

    // Taken branch with a misaligned offset; a not-taken one is fine
    setup_test(1, 1, 0, 0, 1, 'h0000_1002, 'h0000_2000, 1);
    check(1, 'h0000_1000, 1);
    setup_test(1, 1, 0, 0, 0, 'h0000_1002, 'h0000_2000, 1);
    check(0, 'h0, 0);

    // Invalid instruction in EX (bubble): no redirect
    setup_test(0, 0, 1, 0, 0, 'h0000_0104, 'h0000_2000, 0);
    check(0, 'h0, 0);

    // Summary
    $display("----------------------------");
    $display("Tests completed: %0d", checks);
    $display("Errors:          %0d", errors);
    $display("----------------------------");

    if (errors == 0) $display("PASS");
    else             $display("FAIL");

    $finish;

  end

endmodule
