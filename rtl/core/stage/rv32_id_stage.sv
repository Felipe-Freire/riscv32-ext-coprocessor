// Decode stage: decoder, immediate generator, register file, branch prediction, hazard unit and
// the ID/EX register.
//
// The hazard unit drives stall_o for the fetch stage. The register file is read here and written
// from WB.
module rv32_id_stage
  import rv32_pkg::*;
(
  input  logic            clk_i,
  input  logic            rst_ni,

  // Control from later stages
  input  logic            ex_redirect_i,  // discards the instruction in ID
  input  logic            trap_i,         // discards the instructions in ID and EX
  input  logic            freeze_i,       // bus access waiting in MEM: the whole pipeline holds
  input  logic            exmem_valid_i,
  input  logic [4:0]      exmem_rd_i,
  input  logic            exmem_rd_we_i,

  // Register file write port (WB)
  input  logic [4:0]      wb_rd_i,
  input  logic [XLEN-1:0] wb_data_i,
  input  logic            wb_we_i,

  // IF/ID
  input  logic            ifid_valid_i,
  input  logic [XLEN-1:2] ifid_pc_i,
  input  logic [31:0]     ifid_instr_i,
  input  logic            ifid_err_i,
  input  logic [XLEN-1:2] pc_i,           // PC being fetched: ifid_pc_i + 4 while IF/ID is valid

  // Control to the fetch stage
  output logic            stall_o,
  output logic            id_redirect_o,
  output logic [XLEN-1:2] id_target_o,

  // ID/EX
  output logic            idex_valid_o,
  output idex_t           idex_o
);

  logic [4:0]      rs1, rs2;
  dec_ctrl_t       ctrl;
  logic [XLEN-1:0] imm, rs1_data, rs2_data;
  logic [XLEN-1:2] alt_pc;
  logic            pred_taken, bubble;
  fwd_sel_e        fwd_a, fwd_b;
  logic            idex_valid_q;
  idex_t           idex_d, idex_q;

  assign rs1 = ifid_instr_i[19:15];
  assign rs2 = ifid_instr_i[24:20];

  rv32_decoder u_decoder (
    .instr_i    (ifid_instr_i),
    .instr_err_i(ifid_err_i),
    .ctrl_o     (ctrl)
  );

  rv32_imm_gen u_imm_gen (
    .instr_i  (ifid_instr_i[31:7]),
    .imm_sel_i(ctrl.imm_sel),
    .imm_o    (imm)
  );

  rv32_regfile u_regfile (
    .clk_i,
    .rs1_addr_i(rs1),
    .rs1_data_o(rs1_data),
    .rs2_addr_i(rs2),
    .rs2_data_o(rs2_data),
    .rd_addr_i (wb_rd_i),
    .rd_data_i (wb_data_i),
    .rd_we_i   (wb_we_i)
  );

  rv32_branch_pred u_branch_pred (
    .valid_i      (ifid_valid_i),
    .branch_i     (ctrl.branch),
    .jal_i        (ctrl.jal),
    .jalr_i       (ctrl.jalr),
    .pc_i         (ifid_pc_i),
    .pc_next_i    (pc_i),
    .imm_i        (imm[XLEN-1:2]),
    .id_redirect_o,
    .id_target_o,
    .pred_taken_o (pred_taken),
    .alt_pc_o     (alt_pc)
  );

  rv32_hazard u_hazard (
    .ifid_valid_i,
    .rs1_i       (rs1),
    .rs2_i       (rs2),
    .rs1_ren_i   (ctrl.rs1_ren),
    .rs2_ren_i   (ctrl.rs2_ren),
    .idex_valid_i(idex_valid_q),
    .idex_rd_i   (idex_q.rd),
    .idex_rd_we_i(idex_q.rd_we),
    .idex_late_i (idex_q.mem_re | idex_q.csr),
    .exmem_valid_i,
    .exmem_rd_i,
    .exmem_rd_we_i,
    .freeze_i,
    .stall_o,
    .bubble_o    (bubble),
    .fwd_a_o     (fwd_a),
    .fwd_b_o     (fwd_b)
  );

  always_comb begin : idex_next
    idex_d.pc         = ifid_pc_i;
    idex_d.alt_pc     = alt_pc;
    idex_d.rs1_data   = rs1_data;
    idex_d.rs2_data   = rs2_data;
    idex_d.imm        = imm;
    idex_d.fwd_a      = fwd_a;
    idex_d.fwd_b      = fwd_b;
    idex_d.opb_imm    = ctrl.opb_imm;
    idex_d.alu_op     = ctrl.alu_op;
    idex_d.rd_alt_pc  = ctrl.rd_alt_pc;
    idex_d.branch     = ctrl.branch;
    idex_d.pred_taken = pred_taken;
    idex_d.jalr       = ctrl.jalr;
    idex_d.funct3     = ifid_instr_i[14:12];
    idex_d.mem_re     = ctrl.mem_re;
    idex_d.mem_we     = ctrl.mem_we;
    idex_d.rd         = ifid_instr_i[11:7];
    idex_d.rd_we      = ctrl.rd_we;
    idex_d.exc        = ctrl.exc;
    idex_d.exc_cause  = ctrl.exc_cause;
    idex_d.csr        = ctrl.csr;
    idex_d.mret       = ctrl.mret;
  end

  // A bubble or an EX redirect replaces the instruction entering ID/EX. While frozen, ID/EX still
  // holds the instruction in EX, so only a trap can clear it.
  always_ff @(posedge clk_i or negedge rst_ni) begin : idex_valid_reg
    if (!rst_ni) begin
      idex_valid_q <= 1'b0;
    end else if (trap_i) begin
      idex_valid_q <= 1'b0;
    end else if (!freeze_i) begin
      idex_valid_q <= ifid_valid_i & ~bubble & ~ex_redirect_i;
    end
  end

  always_ff @(posedge clk_i) begin : idex_reg
    if (!freeze_i) begin
      idex_q <= idex_d;
    end
  end

  assign idex_valid_o = idex_valid_q;
  assign idex_o       = idex_q;

endmodule
