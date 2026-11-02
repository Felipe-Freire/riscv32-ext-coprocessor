// Fetch stage: PC register, next-PC selection and the IF/ID register.
//
// The PC register drives the instruction memory address, so no redirect logic sits in front of
// the memory. The memory output is the IF/ID instruction (no flop): it arrives one cycle after
// the request and stays unchanged while instr_req_o is low, which is how IF/ID holds during a
// stall. IF/ID only adds the valid bit and the PC.
//
// While IF/ID is valid, pc_o = ifid_pc_o + 4: it is the link and fall-through value for ID.
module rv32_if_stage
  import rv32_pkg::*;
#(
  parameter logic [XLEN-1:0] BootAddr = 32'h0000_0000
) (
  input  logic            clk_i,
  input  logic            rst_ni,

  // Instruction memory (Boot ROM / I-TCM)
  output logic            instr_req_o,
  output logic [XLEN-1:0] instr_addr_o,
  input  logic [31:0]     instr_rdata_i,
  input  logic            instr_err_i,

  // Pipeline control. A redirect also discards the instruction being fetched. Trap and EX
  // redirects are taken even during a stall; the ID redirect waits until ID advances.
  input  logic            stall_i,        // hold PC and IF/ID
  input  logic            id_redirect_i,  // JAL or predicted-taken branch in ID
  input  logic [XLEN-1:2] id_target_i,
  input  logic            ex_redirect_i,  // mispredicted branch or JALR in EX
  input  logic [XLEN-1:2] ex_target_i,
  input  logic            trap_i,         // trap or MRET in MEM
  input  logic [XLEN-1:2] trap_target_i,

  output logic [XLEN-1:2] pc_o,           // PC being fetched

  // IF/ID
  output logic            ifid_valid_o,
  output logic [XLEN-1:2] ifid_pc_o,
  output logic [31:0]     ifid_instr_o,   // memory output
  output logic            ifid_err_o      // instruction access fault, memory output
);

  logic [XLEN-1:2] pc_q, pc_d;
  logic            pc_en;
  logic            ifid_valid_q;
  logic [XLEN-1:2] ifid_pc_q;

  // Priority: the oldest instruction wins (trap in MEM, then EX, then ID).
  always_comb begin : next_pc
    if (trap_i) begin
      pc_d = trap_target_i;
    end else if (ex_redirect_i) begin
      pc_d = ex_target_i;
    end else if (id_redirect_i) begin
      pc_d = id_target_i;
    end else begin
      pc_d = pc_q + 1'b1;
    end
  end

  // PC and IF/ID share this enable. During a stall the ID redirect is ignored, so the stalled
  // branch stays in IF/ID and redirects again once ID advances.
  assign pc_en = trap_i | ex_redirect_i | ~stall_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin : pc_reg
    if (!rst_ni) begin
      pc_q <= BootAddr[XLEN-1:2];
    end else if (pc_en) begin
      pc_q <= pc_d;
    end
  end

  // The instruction entering IF/ID is the one fetched from pc_q, so it is on the wrong path
  // whenever a redirect is taken in the same cycle.
  always_ff @(posedge clk_i or negedge rst_ni) begin : ifid_valid_reg
    if (!rst_ni) begin
      ifid_valid_q <= 1'b0;
    end else if (pc_en) begin
      ifid_valid_q <= ~(trap_i | ex_redirect_i | id_redirect_i);
    end
  end

  always_ff @(posedge clk_i) begin : ifid_pc_reg
    if (pc_en) begin
      ifid_pc_q <= pc_q;
    end
  end

  // The request only depends on stall_i, not on the redirects, which arrive late in the cycle.
  assign instr_req_o  = ~stall_i;
  assign instr_addr_o = {pc_q, 2'b00};
  assign pc_o         = pc_q;

  assign ifid_valid_o = ifid_valid_q;
  assign ifid_pc_o    = ifid_pc_q;
  assign ifid_instr_o = instr_rdata_i;
  assign ifid_err_o   = instr_err_i;

endmodule
