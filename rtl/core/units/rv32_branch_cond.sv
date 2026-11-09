// RV32I branch condition (EX): evaluates the condition of a conditional branch from the ALU
// comparison flags, which the ALU computes with AluSub.
//
// funct3[2:1] picks the flag (00 eq, 10 lt, 11 ltu) and funct3[0] inverts it, which covers BEQ/BNE,
// BLT/BGE and BLTU/BGEU. Whether a branch redirects is decided by rv32_redirect_logic.
module rv32_branch_cond
  import rv32_pkg::*;
(
  input  logic [2:0] funct3_i,
  input  logic       eq_i,
  input  logic       lt_i,
  input  logic       ltu_i,
  output logic       taken_o
);

  logic cond;

  always_comb begin : condition
    unique case (funct3_i[2:1])
      2'b00:   cond = eq_i;    // BEQ, BNE
      2'b10:   cond = lt_i;    // BLT, BGE
      2'b11:   cond = ltu_i;   // BLTU, BGEU
      default: cond = 1'b0;    // 010, 011: illegal, the decoder raises the exception
    endcase
  end

  assign taken_o = cond ^ funct3_i[0];

endmodule
