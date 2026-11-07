// rv32_branch_cond: 
module tb_rv32_branch_cond;
  import rv32_pkg::*;

  logic        jal, jalr, branch, eq, lt, ltu, jmp;
  logic [2: 0] funct3;
  int          errors = 0, checks = 0;

  rv32_branch_cond dut (
    .jal_i(jal),
    .jalr_i(jalr),
    .branch_i(branch),
    .funct3_i(funct3),
    .eq_i(eq),
    .lt_i(lt),
    .ltu_i(ltu),
    .jmp_o(jmp)
  );

  task automatic setup_test (
    logic        jal_i,
    logic        jalr_i,
    logic        branch_i,
    logic        eq_i,
    logic        lt_i,
    logic        ltu_i,
    logic [2:0]  funct3_i
  );
    jal    = jal_i;
    jalr   = jalr_i;
    branch = branch_i;
    eq     = eq_i;
    lt     = lt_i;
    ltu    = ltu_i;
    funct3 = funct3_i;
  endtask

  task automatic fail(string msg);
    errors++;
    if (errors <= 10) $display("FAIL: %s", msg);
  endtask

  task automatic check(logic expected_result);
    #1;
    checks++;
    if (jmp !== expected_result) begin
      fail($sformatf("expected=%b dut=%b", expected_result, jmp));
    end

  endtask

  initial begin
    // JAL / JALR
    setup_test(1, 0, 0, 0, 0, 0, BRANCH_IF_EQ); check(1);
    setup_test(0, 1, 0, 0, 0, 0, BRANCH_IF_EQ); check(1);
    // BEQ
    setup_test(0, 0, 1, 1, 0, 0, BRANCH_IF_EQ); check(1);
    setup_test(0, 0, 1, 0, 0, 0, BRANCH_IF_EQ); check(0);
    // BNE
    setup_test(0, 0, 1, 0, 0, 0, BRANCH_IF_NOT_EQ); check(1);
    setup_test(0, 0, 1, 1, 0, 0, BRANCH_IF_NOT_EQ); check(0);
    // BLT
    setup_test(0, 0, 1, 0, 1, 0, BRANCH_IF_LE); check(1);
    setup_test(0, 0, 1, 0, 0, 0, BRANCH_IF_LE); check(0);
    // BGE
    setup_test(0, 0, 1, 0, 0, 0, BRANCH_IF_GEQ); check(1);
    setup_test(0, 0, 1, 0, 1, 0, BRANCH_IF_GEQ); check(0);
    // BLTU
    setup_test(0, 0, 1, 0, 0, 1, BRANCH_IF_LE_UNSIGNED); check(1);
    setup_test(0, 0, 1, 0, 0, 0, BRANCH_IF_LE_UNSIGNED); check(0);
    // BGEU
    setup_test(0, 0, 1, 0, 0, 0, BRANCH_IF_GEQ_UNSIGNED); check(1);
    setup_test(0, 0, 1, 0, 0, 1, BRANCH_IF_GEQ_UNSIGNED); check(0);
    // Branch disabled
    setup_test(0, 0, 0, 1, 0, 0, BRANCH_IF_EQ); check(0);
    // Branch enabled
    setup_test(0, 0, 1, 1, 0, 0, BRANCH_IF_EQ); check(1);

    setup_test(0, 0, 1, 1, 0, 0, 3'b010); check(0);
    setup_test(0, 0, 1, 1, 0, 0, 3'b011); check(0);

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