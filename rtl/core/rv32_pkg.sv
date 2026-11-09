// RV32 core package: ISA encodings and the control types passed between the core units.
//
// Only definitions used by more than one unit live here. Encodings that only the decoder reads
// (funct3/funct7 of OP and OP-IMM, the SYSTEM funct12 values) stay in the decoder. Pipeline:
// docs/figures/core-datapath.drawio. Instructions, CSRs and traps: rtl/core/README.md.
package rv32_pkg;

  parameter int unsigned XLEN = 32;

  // ===========================================================================================
  // ISA encodings
  // ===========================================================================================

  typedef enum logic [6:0] {
    OPCODE_LOAD     = 7'b000_0011,
    OPCODE_MISC_MEM = 7'b000_1111,
    OPCODE_OP_IMM   = 7'b001_0011,
    OPCODE_AUIPC    = 7'b001_0111,
    OPCODE_STORE    = 7'b010_0011,
    OPCODE_OP       = 7'b011_0011,
    OPCODE_LUI      = 7'b011_0111,
    OPCODE_BRANCH   = 7'b110_0011,
    OPCODE_JALR     = 7'b110_0111,
    OPCODE_JAL      = 7'b110_1111,
    OPCODE_SYSTEM   = 7'b111_0011
  } opcode_e;

  // funct3 travels down the pipeline unchanged, and each unit reads its own fields:
  //   rv32_branch_cond:              [2:1] = 00 eq, 10 lt, 11 ltu; [0] inverts the condition
  //   rv32_store_align, load_align:  [1:0] = 00 byte, 01 half, 10 word; [2] zero-extends a load
  //   rv32_csr:                      [1:0] = 01 write, 10 set, 11 clear; [2] selects zimm, not rs1

  // mcause exception codes (privileged spec) that this core raises.
  typedef enum logic [3:0] {
    EXC_INSTR_MISALIGNED   = 4'd0,   // jump or taken branch to a target that is not 4-byte aligned
    EXC_INSTR_ACCESS_FAULT = 4'd1,
    EXC_ILLEGAL_INSTR      = 4'd2,
    EXC_BREAKPOINT         = 4'd3,   // EBREAK
    EXC_LOAD_MISALIGNED    = 4'd4,
    EXC_LOAD_ACCESS_FAULT  = 4'd5,
    EXC_STORE_MISALIGNED   = 4'd6,
    EXC_STORE_ACCESS_FAULT = 4'd7,
    EXC_ECALL_M            = 4'd11   // ECALL from M-mode
  } exc_cause_e;

  // ===========================================================================================
  // Control passed from decode to execute
  // ===========================================================================================

  // ALU operation. Branches use AluSub, and the branch unit reads the ALU comparison flags.
  // Loads, stores and JALR use AluAdd, and the adder output is the address.
  typedef enum logic [3:0] {
    AluAdd,
    AluSub,
    AluSll,
    AluSlt,
    AluSltu,
    AluXor,
    AluSrl,
    AluSra,
    AluOr,
    AluAnd,
    AluPassB    // LUI: result = immediate
  } alu_op_e;

  typedef enum logic [2:0] {
    ImmI,
    ImmS,
    ImmB,
    ImmU,
    ImmJ
  } imm_sel_e;

  // Source of an EX operand. The hazard unit picks it in ID and it is registered in ID/EX, so the
  // forwarding comparators are not on the EX path.
  typedef enum logic [1:0] {
    FwdNone,    // value read from the register file in ID
    FwdExMem,   // result of the previous instruction
    FwdMemWb    // result of the instruction before that
  } fwd_sel_e;

  // Decoder output (ID).
  typedef struct packed {
    logic       exc;        // fetch fault, illegal, misaligned JAL, ECALL, EBREAK: trap in MEM
    exc_cause_e exc_cause;
    logic       rs1_ren;    // reads rs1 / rs2; hazard detection ignores the field otherwise
    logic       rs2_ren;
    imm_sel_e   imm_sel;
    logic       opb_imm;    // ALU operand B = immediate instead of rs2
    alu_op_e    alu_op;
    logic       rd_alt_pc;  // rd = alt_pc: link of JAL / JALR, or pc + imm for AUIPC
    logic       branch;     // conditional branch, resolved in EX
    logic       jal;        // redirected in ID
    logic       jalr;       // redirected in EX
    logic       mem_re;
    logic       mem_we;
    logic       csr;        // CSR access, done in MEM
    logic       mret;
    logic       rd_we;      // 0 when rd == x0, so x0 is never written or forwarded
  } dec_ctrl_t;

  // ID/EX pipeline register. Its valid bit is a separate flop with reset; a flush clears only
  // that bit, so every side effect downstream is qualified with it.
  typedef struct packed {
    logic [XLEN-1:2] pc;
    logic [XLEN-1:2] alt_pc;      // path not taken in ID, link of JAL / JALR, AUIPC result
    logic [XLEN-1:0] rs1_data;
    logic [XLEN-1:0] rs2_data;
    logic [XLEN-1:0] imm;
    fwd_sel_e        fwd_a;       // operand A, from rs1
    fwd_sel_e        fwd_b;       // operand B and store data, both from rs2
    logic            opb_imm;
    alu_op_e         alu_op;
    logic            rd_alt_pc;
    logic            branch;
    logic            pred_taken;
    logic            jalr;
    logic [2:0]      funct3;
    logic            mem_re;
    logic            mem_we;
    logic [4:0]      rd;
    logic            rd_we;
    logic            exc;
    exc_cause_e      exc_cause;
    logic            csr;
    logic            mret;
  } idex_t;

  // EX/MEM pipeline register, next to its exmem_valid bit. Loads and stores issued their request in
  // EX, so only the response is handled in MEM.
  typedef struct packed {
    logic [XLEN-1:2] pc;
    logic [XLEN-1:0] ex_result;   // ALU result, link/AUIPC value, load/store address, CSR operand
    logic [11:0]     csr_addr;
    logic [2:0]      funct3;
    logic [4:0]      rd;
    logic            rd_we;
    logic            mem_re;
    logic            mem_we;
    logic            req;         // data request granted in EX: MEM waits for its response
    logic            csr;
    logic            csr_write;   // CSRRW, or CSRRS / CSRRC with a nonzero rs1 or zimm field
    logic            mret;
    logic            exc;         // exception from ID or EX: trap in MEM
    exc_cause_e      exc_cause;
  } exmem_t;

endpackage
