// Branch prediction in ID: target adder, static backward-taken / forward-not-taken prediction and
// the JAL redirect.
//
// alt_pc is the path ID did not take, so EX redirects to it on a misprediction: the fall-through
// of a predicted-taken branch or the target of a predicted-not-taken one. It also carries the
// link of JAL and JALR and the AUIPC result, which comes from the target adder.
//
// The target adder is on the critical path of ID: memory output, immediate, adder, alt_pc and the
// PC all in one cycle. It only ever needs three immediates, B (branch), J (JAL) and U (AUIPC), so
// it takes them straight from the instruction bits with two opcode bits as the select, instead of
// waiting for the decoder and rv32_imm_gen:
//
//   opcode[6:2]  BRANCH 11000, JALR 11001, JAL 11011, AUIPC 00101
//   opcode[6] = 0 -> U;  opcode[6] = 1 -> opcode[3] ? J : B
//
// For every other opcode the target is meaningless, and nothing uses it: id_redirect_o needs JAL or
// a branch, and alt_pc_o is only read by branches, JAL, JALR (both take pc_next_i) and AUIPC.
module rv32_branch_pred
  import rv32_pkg::*;
(
  input  logic            valid_i,        // the instruction in ID is valid
  input  logic            branch_i,
  input  logic            jal_i,
  input  logic            jalr_i,
  input  logic [XLEN-1:2] pc_i,           // PC of the instruction in ID
  input  logic [XLEN-1:2] pc_next_i,      // pc_i + 4
  input  logic [31:0]     instr_i,        // instruction in ID, straight from the memory

  output logic            id_redirect_o,
  output logic [XLEN-1:2] id_target_o,
  output logic            pred_taken_o,
  output logic [XLEN-1:2] alt_pc_o
);

  logic [XLEN-1:0] imm_b, imm_j, imm_u, target_imm;

  assign imm_b = {{20{instr_i[31]}}, instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
  assign imm_j = {{12{instr_i[31]}}, instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
  assign imm_u = {instr_i[31:12], 12'b0};

  assign target_imm = !instr_i[6] ? imm_u : (instr_i[3] ? imm_j : imm_b);

  // If imm[1] is set the target is misaligned: the instruction traps before the wrong-path fetch
  // can matter. Bits 1:0 cannot carry into the word-aligned PC.
  assign id_target_o = pc_i + target_imm[XLEN-1:2];

  // A negative immediate is a backward branch, which is usually a loop. Every immediate has its
  // sign in instr[31].
  assign pred_taken_o  = branch_i & instr_i[31];
  assign id_redirect_o = valid_i & (jal_i | pred_taken_o);

  assign alt_pc_o = (jal_i | jalr_i | pred_taken_o) ? pc_next_i : id_target_o;

endmodule
