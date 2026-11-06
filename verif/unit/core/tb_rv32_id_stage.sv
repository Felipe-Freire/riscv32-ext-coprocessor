// rv32_id_stage, directed: ID/EX contents, write-through, forwarding selects, load-use and CSR
// stalls, branch prediction, freeze and flush. Also covers rv32_hazard and rv32_branch_pred.
module tb_rv32_id_stage;
  import rv32_pkg::*;

  localparam logic [31:0] ADD_X3  = 32'h0020_81B3;  // add x3, x1, x2
  localparam logic [31:0] ADD_X5  = 32'h0031_82B3;  // add x5, x3, x3
  localparam logic [31:0] ADD_X7  = 32'h0003_03B3;  // add x7, x6, x0
  localparam logic [31:0] LW_X6   = 32'h0000_A303;  // lw x6, 0(x1)
  localparam logic [31:0] CSR_X6  = 32'h3400_2373;  // csrrs x6, mscratch, x0
  localparam logic [31:0] LUI_X7  = 32'h0003_03B7;  // lui x7, 0x30: its rs1 field reads as x6
  localparam logic [31:0] JAL     = 32'h4000_01EF;  // jal x3, .+1024
  localparam logic [31:0] BEQ_BWD = 32'hFE20_88E3;  // beq x1, x2, .-16
  localparam logic [31:0] BEQ_FWD = 32'h0020_8863;  // beq x1, x2, .+16
  localparam logic [31:0] AUIPC   = 32'h1234_5197;  // auipc x3, 0x12345
  localparam logic [31:0] JALR    = 32'hFFC0_81E7;  // jalr x3, -4(x1)

  localparam logic [31:2] PC = 30'h0000_0400;

  logic        clk = 1'b0, rst_n = 1'b0;
  logic        ex_redirect = 1'b0, trap = 1'b0, freeze = 1'b0;
  logic        exmem_valid = 1'b0, exmem_rd_we = 1'b0;
  logic [4:0]  exmem_rd = '0, wb_rd = '0;
  logic [31:0] wb_data = '0;
  logic        wb_we = 1'b0;
  logic        ifid_valid = 1'b0;
  logic [31:2] ifid_pc = PC, pc_next, id_target;
  logic [31:0] ifid_instr = '0;
  logic        stall, id_redirect, idex_valid;
  idex_t       idex;
  int          errors = 0, checks = 0;

  assign pc_next = ifid_pc + 1'b1;

  rv32_id_stage dut (
    .clk_i        (clk),
    .rst_ni       (rst_n),
    .ex_redirect_i(ex_redirect),
    .trap_i       (trap),
    .freeze_i     (freeze),
    .exmem_valid_i(exmem_valid),
    .exmem_rd_i   (exmem_rd),
    .exmem_rd_we_i(exmem_rd_we),
    .wb_rd_i      (wb_rd),
    .wb_data_i    (wb_data),
    .wb_we_i      (wb_we),
    .ifid_valid_i (ifid_valid),
    .ifid_pc_i    (ifid_pc),
    .ifid_instr_i (ifid_instr),
    .ifid_err_i   (1'b0),
    .pc_i         (pc_next),
    .stall_o      (stall),
    .id_redirect_o(id_redirect),
    .id_target_o  (id_target),
    .idex_valid_o (idex_valid),
    .idex_o       (idex)
  );

  always #5 clk = ~clk;

  task automatic eq(string what, logic [31:0] got, logic [31:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL: %s = %h, expected %h", what, got, exp);
    end
  endtask

  // Puts an instruction in ID. Control set before the call stays applied.
  task automatic present(logic [31:0] word, logic [31:2] pc = PC);
    @(negedge clk);
    ifid_valid = 1'b1;
    ifid_instr = word;
    ifid_pc    = pc;
    #1;
  endtask

  task automatic tick();
    @(posedge clk);
    #1;
  endtask

  task automatic step(logic [31:0] word, logic [31:2] pc = PC);
    present(word, pc);
    tick();
  endtask

  task automatic write_reg(logic [4:0] rd, logic [31:0] data);
    @(negedge clk);
    {wb_we, wb_rd, wb_data} = {1'b1, rd, data};
    @(posedge clk);
    #1;
    wb_we = 1'b0;
  endtask

  task automatic set_exmem(logic valid, logic [4:0] rd, logic rd_we);
    {exmem_valid, exmem_rd, exmem_rd_we} = {valid, rd, rd_we};
  endtask

  initial begin
    repeat (2) @(negedge clk);
    eq("reset valid", idex_valid, 1'b0);
    rst_n = 1'b1;
    write_reg(5'd1, 32'h11);
    write_reg(5'd2, 32'h22);

    // ID/EX contents
    step(ADD_X3);
    eq("valid", idex_valid, 1'b1);
    eq("pc", idex.pc, PC);
    eq("rs1_data", idex.rs1_data, 32'h11);
    eq("rs2_data", idex.rs2_data, 32'h22);
    eq("alu_op", idex.alu_op, AluAdd);
    eq("rd", idex.rd, 5'd3);
    eq("rd_we", idex.rd_we, 1'b1);

    // Write-through: WB writes x1 while ID reads it
    {wb_we, wb_rd, wb_data} = {1'b1, 5'd1, 32'h33};
    step(ADD_X3);
    wb_we = 1'b0;
    eq("write-through", idex.rs1_data, 32'h33);

    // Forwarding: EX holds add x3, so x3 comes from EX/MEM; the nearest instruction wins
    set_exmem(1'b1, 5'd3, 1'b1);
    step(ADD_X5);
    eq("fwd_a from EX", idex.fwd_a, FwdExMem);
    eq("fwd_b from EX", idex.fwd_b, FwdExMem);
    // EX now holds add x5, and only MEM writes x3
    step(ADD_X5);
    eq("fwd_a from MEM", idex.fwd_a, FwdMemWb);
    eq("fwd_b from MEM", idex.fwd_b, FwdMemWb);
    set_exmem(1'b1, 5'd3, 1'b0);
    step(ADD_X5);
    eq("MEM does not write", idex.fwd_a, FwdNone);
    set_exmem(1'b0, 5'd3, 1'b1);
    step(ADD_X5);
    eq("MEM not valid", idex.fwd_a, FwdNone);
    // rs1 and rs2 forward independently: only x2 comes from MEM
    set_exmem(1'b1, 5'd2, 1'b1);
    step(ADD_X3);
    eq("rs1 not forwarded", idex.fwd_a, FwdNone);
    eq("rs2 forwarded", idex.fwd_b, FwdMemWb);
    set_exmem(1'b0, 5'd0, 1'b0);

    // Load-use: one stall and a bubble, then the value comes from MEM/WB
    step(LW_X6);
    present(ADD_X7);
    eq("load-use stall", stall, 1'b1);
    tick();
    eq("load-use bubble", idex_valid, 1'b0);
    set_exmem(1'b1, 5'd6, 1'b1);
    present(ADD_X7);
    eq("stall over", stall, 1'b0);
    tick();
    eq("after stall", idex_valid, 1'b1);
    eq("after stall fwd_a", idex.fwd_a, FwdMemWb);
    set_exmem(1'b0, 5'd0, 1'b0);

    // No stall when ID does not read the register or is not valid
    step(LW_X6);
    present(LUI_X7);
    eq("lui after load", stall, 1'b0);
    tick();
    step(LW_X6);
    @(negedge clk);
    ifid_valid = 1'b0;
    ifid_instr = ADD_X7;
    #1;
    eq("invalid ID", stall, 1'b0);
    tick();

    // A flushed instruction in EX neither stalls nor forwards
    ex_redirect = 1'b1;
    step(LW_X6);
    ex_redirect = 1'b0;
    present(ADD_X7);
    eq("flushed EX stall", stall, 1'b0);
    tick();
    eq("flushed EX fwd_a", idex.fwd_a, FwdNone);

    // A CSR read stalls like a load
    step(CSR_X6);
    present(ADD_X7);
    eq("csr stall", stall, 1'b1);
    tick();

    // Branch prediction
    present(JAL);
    eq("jal redirect", id_redirect, 1'b1);
    eq("jal target", id_target, PC + 30'h100);
    tick();
    eq("jal alt_pc", idex.alt_pc, PC + 1);
    eq("jal link", idex.rd_alt_pc, 1'b1);

    @(negedge clk);
    ifid_valid = 1'b0;
    ifid_instr = JAL;
    #1;
    eq("invalid jal", id_redirect, 1'b0);

    present(BEQ_BWD);
    eq("backward redirect", id_redirect, 1'b1);
    eq("backward target", id_target, PC - 4);
    tick();
    eq("backward pred", idex.pred_taken, 1'b1);
    eq("backward alt_pc", idex.alt_pc, PC + 1);

    present(BEQ_FWD);
    eq("forward redirect", id_redirect, 1'b0);
    tick();
    eq("forward pred", idex.pred_taken, 1'b0);
    eq("forward alt_pc", idex.alt_pc, PC + 4);

    step(AUIPC);
    eq("auipc alt_pc", idex.alt_pc, PC + 30'h048D_1400);
    step(JALR);
    eq("jalr alt_pc", idex.alt_pc, PC + 1);

    // Freeze holds ID/EX, even against a repeated EX redirect
    step(ADD_X3, PC + 8);
    freeze      = 1'b1;
    ex_redirect = 1'b1;
    present(ADD_X5);
    eq("freeze stall", stall, 1'b1);
    tick();
    eq("frozen valid", idex_valid, 1'b1);
    eq("frozen pc", idex.pc, PC + 8);

    // Once it advances, the EX redirect discards the instruction entering ID/EX
    freeze = 1'b0;
    step(ADD_X5);
    eq("ex redirect", idex_valid, 1'b0);
    ex_redirect = 1'b0;

    // A trap clears ID/EX, also during a freeze
    step(ADD_X3);
    trap = 1'b1;
    step(ADD_X5);
    eq("trap", idex_valid, 1'b0);
    trap = 1'b0;
    step(ADD_X3);
    freeze = 1'b1;
    trap   = 1'b1;
    step(ADD_X5);
    eq("trap during freeze", idex_valid, 1'b0);

    if (errors == 0) $display("PASS: %0d checks", checks);
    else             $display("FAIL: %0d errors in %0d checks", errors, checks);
    $finish;
  end

endmodule
