// RV32I Branch Cond: eq / lt / ltu
//
// Depending on the operation, can change the next operation that needs to be loaded

module rv32_branch_cond
  import rv32_pkg::*;
(
  input  logic        jal_i,
  input  logic        jalr_i,
  input  logic        branch_i,
  input  logic [2: 0] funct3_i,
  input  logic        eq_i,
  input  logic        lt_i,
  input  logic        ltu_i,
  output logic        jmp_o
);

  logic cond_should_jmp;

  always_comb begin
    cond_should_jmp = 1'b0;

    unique case (branch_funct3_t'(funct3_i))
      BRANCH_IF_EQ:
        cond_should_jmp = eq_i;
      BRANCH_IF_NOT_EQ:
        cond_should_jmp = ~eq_i;
      BRANCH_IF_LE:
        cond_should_jmp = lt_i;
      BRANCH_IF_GEQ:
        cond_should_jmp = ~lt_i;
      BRANCH_IF_LE_UNSIGNED:
        cond_should_jmp = ltu_i;
      BRANCH_IF_GEQ_UNSIGNED:
        cond_should_jmp = ~ltu_i;
      default:
        cond_should_jmp = 1'b0;
    endcase
  end

  assign jmp_o = jal_i || jalr_i || (cond_should_jmp && branch_i);

endmodule