// Immediate generator: sign-extends the immediate of each instruction format to XLEN.
//
// U also serves the CSR instructions: imm[31:20] is the CSR address and imm[19:15] is zimm.
module rv32_imm_gen
  import rv32_pkg::*;
(
  input  logic [31:7]     instr_i,
  input  imm_sel_e        imm_sel_i,
  output logic [XLEN-1:0] imm_o
);

  always_comb begin : imm_mux
    unique case (imm_sel_i)
      ImmI:    imm_o = {{21{instr_i[31]}}, instr_i[30:20]};
      ImmS:    imm_o = {{21{instr_i[31]}}, instr_i[30:25], instr_i[11:7]};
      ImmB:    imm_o = {{20{instr_i[31]}}, instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
      ImmU:    imm_o = {instr_i[31:12], 12'b0};
      ImmJ:    imm_o = {{12{instr_i[31]}}, instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
      default: imm_o = '0;
    endcase
  end

endmodule
