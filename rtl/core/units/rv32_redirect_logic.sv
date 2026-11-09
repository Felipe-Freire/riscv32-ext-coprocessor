// Redirect logic (EX): decides whether the fetch must be corrected, and where to.
//
// ID already redirected JAL and the branches it predicted taken, so EX only redirects when a branch
// resolves against its prediction, or for JALR, whose target needs rs1. On a misprediction the
// target is alt_pc, the path ID did not take. IF and ID derive their flushes from ex_redirect_o.
//
// A taken branch or a JALR whose target is not word-aligned raises an
// instruction-address-misaligned exception, which EX attaches to the instruction.
module rv32_redirect_logic
  import rv32_pkg::*;
(
  input  logic            valid_i,       // valid instruction in EX
  input  logic            branch_i,
  input  logic            jalr_i,
  input  logic            pred_taken_i,
  input  logic            taken_i,       // from rv32_branch_cond
  input  logic [XLEN-1:2] alt_pc_i,
  input  logic [XLEN-1:0] adder_i,       // ALU adder: rs1 + imm, the JALR target
  input  logic            imm_bit1_i,    // imm[1]: the branch target is misaligned when set

  output logic            ex_redirect_o,
  output logic [XLEN-1:2] ex_target_o,
  output logic            misaligned_o
);

  assign ex_redirect_o = valid_i & ((branch_i & (taken_i ^ pred_taken_i)) | jalr_i);

  // JALR clears bit 0 of the target; bit 1 set means a misaligned target.
  assign ex_target_o = jalr_i ? adder_i[XLEN-1:2] : alt_pc_i;

  assign misaligned_o = (branch_i & taken_i & imm_bit1_i) | (jalr_i & adder_i[1]);

endmodule
