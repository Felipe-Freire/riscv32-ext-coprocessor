// rv32_branch_cond: the six branch conditions, each taken and not taken.
module tb_rv32_branch_cond;
  import rv32_pkg::*;

  localparam logic [2:0] BEQ  = 3'b000;
  localparam logic [2:0] BNE  = 3'b001;
  localparam logic [2:0] BLT  = 3'b100;
  localparam logic [2:0] BGE  = 3'b101;
  localparam logic [2:0] BLTU = 3'b110;
  localparam logic [2:0] BGEU = 3'b111;

  logic        eq, lt, ltu, taken;
  logic [2:0]  funct3;
  int          errors = 0, checks = 0;

  rv32_branch_cond dut (
    .funct3_i(funct3),
    .eq_i    (eq),
    .lt_i    (lt),
    .ltu_i   (ltu),
    .taken_o (taken)
  );

  task automatic setup_test (
    logic       eq_i,
    logic       lt_i,
    logic       ltu_i,
    logic [2:0] funct3_i
  );
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
    if (taken !== expected_result) begin
      fail($sformatf("funct3=%b expected=%b dut=%b", funct3, expected_result, taken));
    end
  endtask

  initial begin
    // BEQ
    setup_test(1, 0, 0, BEQ);  check(1);
    setup_test(0, 1, 1, BEQ);  check(0);
    // BNE
    setup_test(0, 0, 0, BNE);  check(1);
    setup_test(1, 0, 0, BNE);  check(0);
    // BLT
    setup_test(0, 1, 0, BLT);  check(1);
    setup_test(0, 0, 1, BLT);  check(0);
    // BGE
    setup_test(1, 0, 1, BGE);  check(1);
    setup_test(0, 1, 0, BGE);  check(0);
    // BLTU
    setup_test(0, 0, 1, BLTU); check(1);
    setup_test(0, 1, 0, BLTU); check(0);
    // BGEU
    setup_test(0, 1, 0, BGEU); check(1);
    setup_test(0, 0, 1, BGEU); check(0);

    $display("----------------------------");
    $display("Tests completed: %0d", checks);
    $display("Errors:          %0d", errors);
    $display("----------------------------");
    if (errors == 0) $display("PASS");
    else             $display("FAIL");

    $finish;
  end

endmodule
