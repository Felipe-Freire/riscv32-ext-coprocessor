// rv32_redirect_logic
module tb_rv32_redirect_logic;
  import rv32_pkg::*;

  logic            jmp;
  logic [XLEN-1:0] imm;
  logic            flush_id;
  logic            flush_if;
  logic            ex_redirect;
  logic [XLEN-1:2] ex_target;

  int errors = 0, checks = 0;

  rv32_redirect_logic dut (
    .jmp_i         (jmp),
    .imm_i         (imm),
    .flush_id_o    (flush_id),
    .flush_if_o    (flush_if),
    .ex_redirect_o (ex_redirect),
    .ex_target_o   (ex_target)
  );

  // Setup inputs
  task automatic setup_test (
    logic            jmp_i,
    logic [XLEN-1:0] imm_i
  );
    jmp = jmp_i;
    imm = imm_i;
  endtask

  // Report errors
  task automatic fail(string msg);
    errors++;
    if (errors <= 10)
      $display("FAIL: %s", msg);
  endtask

  // Check all outputs
  task automatic check (
    logic            expected_flush_id,
    logic            expected_flush_if,
    logic            expected_redirect,
    logic [XLEN-1:2] expected_target
  );
    #1;
    checks++;

    if (flush_id !== expected_flush_id)
      fail($sformatf("flush_id: expected=%b dut=%b",
                     expected_flush_id, flush_id));

    if (flush_if !== expected_flush_if)
      fail($sformatf("flush_if: expected=%b dut=%b",
                     expected_flush_if, flush_if));

    if (ex_redirect !== expected_redirect)
      fail($sformatf("ex_redirect: expected=%b dut=%b",
                     expected_redirect, ex_redirect));

    if (ex_target !== expected_target)
      fail($sformatf("ex_target: expected=%h dut=%h",
                     expected_target, ex_target));

  endtask

  initial begin

    // No jump: all control outputs should be zero
    setup_test(0, 'h00000000);
    check(0, 0, 0, 'h00000000);

    // No jump with non-zero immediate
    setup_test(0, 'h00001000);
    check(0, 0, 0, 'h00001000);

    // JAL: redirect and flush
    setup_test(1, 'h00000100);
    check(1, 1, 1, 'h00000100);

    // JALR: redirect and flush
    setup_test(1, 'h00002000);
    check(1, 1, 1, 'h00002000);

    // Jump with negative immediate
    setup_test(1, 'hFFFFFFFC);
    check(1, 1, 1, 'hFFFFFFFC);

    // Jump with maximum positive immediate
    setup_test(1, 'h7FFFFFFC);
    check(1, 1, 1, 'h7FFFFFFC);

    // Jump with zero immediate
    setup_test(1, 'h00000000);
    check(1, 1, 1, 'h00000000);

    // Jump disabled after a previous jump
    setup_test(0, 'h00003000);
    check(0, 0, 0, 'h00003000);

    // Change immediate while jump remains enabled
    setup_test(1, 'h00004000);
    check(1, 1, 1, 'h00004000);

    // Summary
    $display("----------------------------");
    $display("Tests completed: %0d", checks);
    $display("Errors:          %0d", errors);
    $display("----------------------------");

    if (errors == 0)
      $display("TEST PASSED");
    else
      $display("TEST FAILED");

    $finish;

  end

endmodule