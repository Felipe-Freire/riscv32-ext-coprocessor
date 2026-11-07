// Instruction decoder (ID): RV32I + Zicsr, machine mode only.
//
// A trapping instruction (access fault, illegal, misaligned JAL, ECALL, EBREAK) has its
// architectural side effects cleared: rd_we, mem_re, mem_we, csr and mret. Branch, jump and
// register-read fields are left as decoded so the illegal-instruction check stays off the redirect
// and stall paths; at worst they cause a wrong-path fetch or a stall, and the trap in MEM flushes
// both.
//
// CSR instructions use the U immediate, which carries the CSR address in imm[31:20] and zimm in
// imm[19:15]; AluPassB places it in ex_result for the CSR unit in MEM.
module rv32_decoder
  import rv32_pkg::*;
(
  input  logic [31:0] instr_i,
  input  logic        instr_err_i,  // instruction access fault on fetch
  output dec_ctrl_t   ctrl_o
);

  localparam logic [11:0] FUNCT12_ECALL  = 12'h000;
  localparam logic [11:0] FUNCT12_EBREAK = 12'h001;
  localparam logic [11:0] FUNCT12_MRET   = 12'h302;
  localparam logic [11:0] FUNCT12_WFI    = 12'h105;

  localparam logic [6:0 ] FUNCT7_BASE    = 7'b000_0000;
  localparam logic [6:0 ] FUNCT7_ALT     = 7'b010_0000;  // SUB, SRA, SRAI

  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [4:0] rd, rs1;
  logic       rd_write;  // the instruction writes rd (rd_we is also 0 for x0)
  logic       illegal, misaligned, ecall, ebreak;
  dec_ctrl_t  ctrl;

  assign funct3 = instr_i[14:12];
  assign funct7 = instr_i[31:25];
  assign rd     = instr_i[11:7];
  assign rs1    = instr_i[19:15];

  always_comb begin : decode
    ctrl         = '0;
    ctrl.imm_sel = ImmI;
    ctrl.alu_op  = AluAdd;
    rd_write     = 1'b0;
    illegal      = 1'b0;
    misaligned   = 1'b0;
    ecall        = 1'b0;
    ebreak       = 1'b0;

    unique case (opcode_e'(instr_i[6:0]))
      OPCODE_LUI: begin
        ctrl.imm_sel = ImmU;
        ctrl.opb_imm = 1'b1;
        ctrl.alu_op  = AluPassB;
        rd_write     = 1'b1;
      end

      // pc + imm comes from the ID target adder through alt_pc.
      OPCODE_AUIPC: begin
        ctrl.imm_sel   = ImmU;
        ctrl.rd_alt_pc = 1'b1;
        rd_write       = 1'b1;
      end

      OPCODE_JAL: begin
        ctrl.imm_sel   = ImmJ;
        ctrl.jal       = 1'b1;
        ctrl.rd_alt_pc = 1'b1;
        rd_write       = 1'b1;
        misaligned     = instr_i[21];  // imm[1]: the PC is word-aligned, so the target is not
      end

      OPCODE_JALR: begin
        ctrl.rs1_ren   = 1'b1;
        ctrl.opb_imm   = 1'b1;
        ctrl.jalr      = 1'b1;
        ctrl.rd_alt_pc = 1'b1;
        rd_write       = 1'b1;
        illegal        = (funct3 != 3'b000);
      end

      OPCODE_BRANCH: begin
        ctrl.imm_sel = ImmB;
        ctrl.rs1_ren = 1'b1;
        ctrl.rs2_ren = 1'b1;
        ctrl.alu_op  = AluSub;
        ctrl.branch  = 1'b1;
        illegal      = (funct3 inside {3'b010, 3'b011});
      end

      OPCODE_LOAD: begin
        ctrl.rs1_ren = 1'b1;
        ctrl.opb_imm = 1'b1;
        ctrl.mem_re  = 1'b1;
        rd_write     = 1'b1;
        illegal      = (funct3 inside {3'b011, 3'b110, 3'b111});
      end

      OPCODE_STORE: begin
        ctrl.imm_sel = ImmS;
        ctrl.rs1_ren = 1'b1;
        ctrl.rs2_ren = 1'b1;
        ctrl.opb_imm = 1'b1;
        ctrl.mem_we  = 1'b1;
        illegal      = (funct3[2] || funct3[1:0] == 2'b11);
      end

      OPCODE_OP_IMM: begin
        ctrl.rs1_ren = 1'b1;
        ctrl.opb_imm = 1'b1;
        rd_write     = 1'b1;
        unique case (funct3)
          3'b000: ctrl.alu_op = AluAdd;
          3'b010: ctrl.alu_op = AluSlt;
          3'b011: ctrl.alu_op = AluSltu;
          3'b100: ctrl.alu_op = AluXor;
          3'b110: ctrl.alu_op = AluOr;
          3'b111: ctrl.alu_op = AluAnd;
          3'b001: begin
            ctrl.alu_op = AluSll;
            illegal     = (funct7 != FUNCT7_BASE);
          end
          3'b101: begin
            ctrl.alu_op = funct7[5] ? AluSra : AluSrl;
            illegal     = !(funct7 inside {FUNCT7_BASE, FUNCT7_ALT});
          end
          default: ;
        endcase
      end

      OPCODE_OP: begin
        ctrl.rs1_ren = 1'b1;
        ctrl.rs2_ren = 1'b1;
        rd_write     = 1'b1;
        if (funct7 == FUNCT7_BASE) begin
          unique case (funct3)
            3'b000: ctrl.alu_op = AluAdd;
            3'b001: ctrl.alu_op = AluSll;
            3'b010: ctrl.alu_op = AluSlt;
            3'b011: ctrl.alu_op = AluSltu;
            3'b100: ctrl.alu_op = AluXor;
            3'b101: ctrl.alu_op = AluSrl;
            3'b110: ctrl.alu_op = AluOr;
            3'b111: ctrl.alu_op = AluAnd;
            default: ;
          endcase
        end else if (funct7 == FUNCT7_ALT && funct3 == 3'b000) begin
          ctrl.alu_op = AluSub;
        end else if (funct7 == FUNCT7_ALT && funct3 == 3'b101) begin
          ctrl.alu_op = AluSra;
        end else begin
          illegal = 1'b1;  // includes the M extension
        end
      end

      // FENCE is a no-op: the core is in order and its bus accesses are non-posted. FENCE.I
      // (Zifencei) is not implemented.
      OPCODE_MISC_MEM: begin
        illegal = (funct3 != 3'b000);
      end

      OPCODE_SYSTEM: begin
        if (funct3 == 3'b000) begin
          if (rd != '0 || rs1 != '0) begin
            illegal = 1'b1;
          end else begin
            unique case (instr_i[31:20])
              FUNCT12_ECALL:  ecall     = 1'b1;
              FUNCT12_EBREAK: ebreak    = 1'b1;
              FUNCT12_MRET:   ctrl.mret = 1'b1;
              FUNCT12_WFI:    ;               // no-op
              default:       illegal   = 1'b1;
            endcase
          end
        end else if (funct3 == 3'b100) begin
          illegal = 1'b1;
        end else begin
          // CSRRW/S/C read rs1; the immediate forms take zimm from imm[19:15].
          ctrl.csr     = 1'b1;
          ctrl.imm_sel = ImmU;
          ctrl.opb_imm = 1'b1;
          ctrl.alu_op  = AluPassB;
          ctrl.rs1_ren = ~funct3[2];
          rd_write     = 1'b1;
        end
      end

      default: illegal = 1'b1;
    endcase

    ctrl.rd_we = rd_write && (rd != '0);

    // Exception priority: access fault, then illegal, then the rest.
    ctrl.exc = instr_err_i | illegal | misaligned | ecall | ebreak;
    if (instr_err_i) begin
      ctrl.exc_cause = EXC_INSTR_ACCESS_FAULT;
    end else if (illegal) begin
      ctrl.exc_cause = EXC_ILLEGAL_INSTR;
    end else if (misaligned) begin
      ctrl.exc_cause = EXC_INSTR_MISALIGNED;
    end else if (ecall) begin
      ctrl.exc_cause = EXC_ECALL_M;
    end else begin
      ctrl.exc_cause = EXC_BREAKPOINT;
    end

    if (ctrl.exc) begin
      ctrl.rd_we  = 1'b0;
      ctrl.mem_re = 1'b0;
      ctrl.mem_we = 1'b0;
      ctrl.csr    = 1'b0;
      ctrl.mret   = 1'b0;
    end
  end

  assign ctrl_o = ctrl;

endmodule
