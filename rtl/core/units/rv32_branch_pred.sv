// Branch prediction in ID: target adder, static backward-taken / forward-not-taken prediction and
// the JAL redirect.
//
// alt_pc is the path ID did not take, so EX redirects to it on a misprediction: the fall-through
// of a predicted-taken branch or the target of a predicted-not-taken one. It also carries the
// link of JAL and JALR and the AUIPC result, which comes from the target adder.
module rv32_branch_pred
  import rv32_pkg::*;
(
  input  logic            valid_i,        // the instruction in ID is valid
  input  logic            branch_i,
  input  logic            jal_i,
  input  logic            jalr_i,
  input  logic [XLEN-1:2] pc_i,           // PC of the instruction in ID
  input  logic [XLEN-1:2] pc_next_i,      // pc_i + 4
  input  logic [XLEN-1:2] imm_i,          // bits 1:0 cannot carry into the word-aligned PC

  output logic            id_redirect_o,
  output logic [XLEN-1:2] id_target_o,
  output logic            pred_taken_o,
  output logic [XLEN-1:2] alt_pc_o
);

  // If imm[1] is set the target is misaligned: the instruction traps before the wrong-path fetch
  // can matter.
  assign id_target_o = pc_i + imm_i;

  // A negative immediate is a backward branch, which is usually a loop.
  assign pred_taken_o  = branch_i & imm_i[XLEN-1];
  assign id_redirect_o = valid_i & (jal_i | pred_taken_o);

  assign alt_pc_o = (jal_i | jalr_i | pred_taken_o) ? pc_next_i : id_target_o;

endmodule
