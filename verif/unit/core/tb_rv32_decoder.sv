// rv32_decoder + rv32_imm_gen, directed: one check per RV32I and Zicsr instruction, then writes to
// x0, illegal encodings and traps. Encodings come from the GNU assembler.
module tb_rv32_decoder;
  import rv32_pkg::*;

  logic [31:0] instr, imm;
  logic        err = 1'b0;
  dec_ctrl_t   ctrl;
  int          errors = 0, checks = 0;

  rv32_decoder u_decoder (
    .instr_i    (instr),
    .instr_err_i(err),
    .ctrl_o     (ctrl)
  );

  rv32_imm_gen u_imm_gen (
    .instr_i  (instr[31:7]),
    .imm_sel_i(ctrl.imm_sel),
    .imm_o    (imm)
  );

  task automatic fail(string name, string what);
    errors++;
    $display("FAIL: %s: %s", name, what);
  endtask

  // Compares the whole control word. exc_cause only counts when exc is set.
  task automatic check(string name, logic [31:0] word, dec_ctrl_t exp);
    instr = word;
    #1;
    checks++;
    if (!exp.exc) exp.exc_cause = ctrl.exc_cause;
    if (ctrl !== exp) fail(name, $sformatf("ctrl %h, expected %h", ctrl, exp));
  endtask

  task automatic check_imm(string name, logic [31:0] word, dec_ctrl_t exp, logic [31:0] exp_imm);
    check(name, word, exp);
    if (imm !== exp_imm) fail(name, $sformatf("imm %h, expected %h", imm, exp_imm));
  endtask

  task automatic op(string name, logic [31:0] word, alu_op_e alu);
    dec_ctrl_t e = '0;
    e.rs1_ren = 1'b1;
    e.rs2_ren = 1'b1;
    e.rd_we   = 1'b1;
    e.alu_op  = alu;
    check(name, word, e);
  endtask

  task automatic op_imm(string name, logic [31:0] word, alu_op_e alu, logic [31:0] exp_imm);
    dec_ctrl_t e = '0;
    e.rs1_ren = 1'b1;
    e.opb_imm = 1'b1;
    e.rd_we   = 1'b1;
    e.alu_op  = alu;
    check_imm(name, word, e, exp_imm);
  endtask

  task automatic load(string name, logic [31:0] word);
    dec_ctrl_t e = '0;
    e.rs1_ren = 1'b1;
    e.opb_imm = 1'b1;
    e.mem_re  = 1'b1;
    e.rd_we   = 1'b1;
    check_imm(name, word, e, 32'hFFFF_FFFC);
  endtask

  task automatic store(string name, logic [31:0] word);
    dec_ctrl_t e = '0;
    e.imm_sel = ImmS;
    e.rs1_ren = 1'b1;
    e.rs2_ren = 1'b1;
    e.opb_imm = 1'b1;
    e.mem_we  = 1'b1;
    check_imm(name, word, e, 32'hFFFF_FFFC);
  endtask

  task automatic branch(string name, logic [31:0] word);
    dec_ctrl_t e = '0;
    e.imm_sel = ImmB;
    e.rs1_ren = 1'b1;
    e.rs2_ren = 1'b1;
    e.alu_op  = AluSub;
    e.branch  = 1'b1;
    check_imm(name, word, e, 32'hFFFF_FFF0);
  endtask

  task automatic csr(string name, logic [31:0] word, logic rs1_ren, logic [31:0] exp_imm);
    dec_ctrl_t e = '0;
    e.csr     = 1'b1;
    e.imm_sel = ImmU;
    e.opb_imm = 1'b1;
    e.alu_op  = AluPassB;
    e.rs1_ren = rs1_ren;
    e.rd_we   = 1'b1;
    check_imm(name, word, e, exp_imm);
  endtask

  // A trapping instruction has no architectural side effect.
  task automatic trap(string name, logic [31:0] word, exc_cause_e cause, logic fault = 1'b0);
    err   = fault;
    instr = word;
    #1;
    checks++;
    if (ctrl.exc !== 1'b1 || ctrl.exc_cause !== cause) begin
      fail(name, $sformatf("exc %b cause %s", ctrl.exc, ctrl.exc_cause.name()));
    end
    if ({ctrl.rd_we, ctrl.mem_re, ctrl.mem_we, ctrl.csr, ctrl.mret} !== '0) begin
      fail(name, "side effect not cleared");
    end
    err = 1'b0;
  endtask

  initial begin
    dec_ctrl_t e;

    op("add",  32'h0020_81B3, AluAdd);
    op("sub",  32'h4020_81B3, AluSub);
    op("sll",  32'h0020_91B3, AluSll);
    op("slt",  32'h0020_A1B3, AluSlt);
    op("sltu", 32'h0020_B1B3, AluSltu);
    op("xor",  32'h0020_C1B3, AluXor);
    op("srl",  32'h0020_D1B3, AluSrl);
    op("sra",  32'h4020_D1B3, AluSra);
    op("or",   32'h0020_E1B3, AluOr);
    op("and",  32'h0020_F1B3, AluAnd);

    op_imm("addi",  32'hFFB0_8193, AluAdd,  32'hFFFF_FFFB);
    op_imm("slti",  32'hFFB0_A193, AluSlt,  32'hFFFF_FFFB);
    op_imm("sltiu", 32'hFFB0_B193, AluSltu, 32'hFFFF_FFFB);
    op_imm("xori",  32'hFFB0_C193, AluXor,  32'hFFFF_FFFB);
    op_imm("ori",   32'hFFB0_E193, AluOr,   32'hFFFF_FFFB);
    op_imm("andi",  32'hFFB0_F193, AluAnd,  32'hFFFF_FFFB);
    op_imm("slli",  32'h0070_9193, AluSll,  32'h0000_0007);
    op_imm("srli",  32'h0070_D193, AluSrl,  32'h0000_0007);
    op_imm("srai",  32'h4070_D193, AluSra,  32'h0000_0407);

    load("lb",  32'hFFC0_8183);
    load("lh",  32'hFFC0_9183);
    load("lw",  32'hFFC0_A183);
    load("lbu", 32'hFFC0_C183);
    load("lhu", 32'hFFC0_D183);

    store("sb", 32'hFE20_8E23);
    store("sh", 32'hFE20_9E23);
    store("sw", 32'hFE20_AE23);

    branch("beq",  32'hFE20_88E3);
    branch("bne",  32'hFE20_98E3);
    branch("blt",  32'hFE20_C8E3);
    branch("bge",  32'hFE20_D8E3);
    branch("bltu", 32'hFE20_E8E3);
    branch("bgeu", 32'hFE20_F8E3);

    csr("csrrw",  32'h3050_91F3, 1'b1, 32'h3050_9000);
    csr("csrrs",  32'h3050_A1F3, 1'b1, 32'h3050_A000);
    csr("csrrc",  32'h3050_B1F3, 1'b1, 32'h3050_B000);
    csr("csrrwi", 32'h3054_D1F3, 1'b0, 32'h3054_D000);
    csr("csrrsi", 32'h3054_E1F3, 1'b0, 32'h3054_E000);
    csr("csrrci", 32'h3054_F1F3, 1'b0, 32'h3054_F000);

    e = '0;
    e.imm_sel = ImmU;
    e.opb_imm = 1'b1;
    e.alu_op  = AluPassB;
    e.rd_we   = 1'b1;
    check_imm("lui", 32'h1234_51B7, e, 32'h1234_5000);

    e = '0;
    e.imm_sel   = ImmU;
    e.rd_alt_pc = 1'b1;
    e.rd_we     = 1'b1;
    check_imm("auipc", 32'h1234_5197, e, 32'h1234_5000);

    e = '0;
    e.imm_sel   = ImmJ;
    e.jal       = 1'b1;
    e.rd_alt_pc = 1'b1;
    e.rd_we     = 1'b1;
    check_imm("jal", 32'h4000_01EF, e, 32'h0000_0400);

    e = '0;
    e.rs1_ren   = 1'b1;
    e.opb_imm   = 1'b1;
    e.jalr      = 1'b1;
    e.rd_alt_pc = 1'b1;
    e.rd_we     = 1'b1;
    check_imm("jalr", 32'hFFC0_81E7, e, 32'hFFFF_FFFC);

    e = '0;
    check("fence", 32'h0FF0_000F, e);
    check("wfi",   32'h1050_0073, e);

    e.mret = 1'b1;
    check("mret", 32'h3020_0073, e);

    // x0 is never written, but a load to x0 still reads memory.
    e = '0;
    e.rs1_ren = 1'b1;
    e.rs2_ren = 1'b1;
    check("add x0", 32'h0020_8033, e);

    e = '0;
    e.rs1_ren = 1'b1;
    e.opb_imm = 1'b1;
    e.mem_re  = 1'b1;
    check("lw x0", 32'hFFC0_A003, e);

    trap("ecall",          32'h0000_0073, EXC_ECALL_M);
    trap("ebreak",         32'h0010_0073, EXC_BREAKPOINT);
    trap("jal misaligned", 32'h4020_01EF, EXC_INSTR_MISALIGNED);
    trap("access fault",   32'h0020_81B3, EXC_INSTR_ACCESS_FAULT, 1'b1);

    trap("mul",            32'h0220_8033, EXC_ILLEGAL_INSTR);
    trap("fence.i",        32'h0000_100F, EXC_ILLEGAL_INSTR);
    trap("c.nop",          32'h0000_0001, EXC_ILLEGAL_INSTR);
    trap("all zeros",      32'h0000_0000, EXC_ILLEGAL_INSTR);
    trap("all ones",       32'hFFFF_FFFF, EXC_ILLEGAL_INSTR);
    trap("ld",             32'h0000_B283, EXC_ILLEGAL_INSTR);
    trap("sd",             32'h0011_3023, EXC_ILLEGAL_INSTR);
    trap("sret",           32'h1020_0073, EXC_ILLEGAL_INSTR);
    trap("wfi with rd",    32'h1050_0173, EXC_ILLEGAL_INSTR);
    trap("ecall with rs1", 32'h0000_8073, EXC_ILLEGAL_INSTR);
    trap("slli shamt[5]",  32'h0202_9293, EXC_ILLEGAL_INSTR);
    trap("jalr funct3",    32'h0000_2067, EXC_ILLEGAL_INSTR);
    trap("branch funct3",  32'h0000_A063, EXC_ILLEGAL_INSTR);
    trap("sub funct3",     32'h4000_1033, EXC_ILLEGAL_INSTR);
    trap("system funct3",  32'h0000_4073, EXC_ILLEGAL_INSTR);

    if (errors == 0) $display("PASS: %0d checks", checks);
    else             $display("FAIL: %0d errors in %0d checks", errors, checks);
    $finish;
  end

endmodule
