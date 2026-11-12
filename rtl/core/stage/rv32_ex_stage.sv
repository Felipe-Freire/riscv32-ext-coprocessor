// Execute stage: operand forwarding, ALU, branch resolution, the data request and the EX/MEM
// register.
//
// Loads and stores send their request here, with the address straight from the ALU adder, so the
// D-TCM answers in MEM. A request waits while MEM still waits for the previous response, and it is
// dropped when the instruction in MEM traps in the same cycle, which keeps exceptions precise: no
// instruction younger than a trap reaches the memory.
//
// For a CSR instruction, ex_result carries the CSR operand (rs1 or zimm) and csr_addr the address,
// both taken from the U immediate the decoder selects.
module rv32_ex_stage
  import rv32_pkg::*;
(
  input  logic            clk_i,
  input  logic            rst_ni,

  // Data port (OBI request)
  output logic            data_req_o,
  input  logic            data_gnt_i,
  output logic [XLEN-1:0] data_addr_o,
  output logic            data_we_o,
  output logic [3:0]      data_be_o,
  output logic [XLEN-1:0] data_wdata_o,

  // Control from later stages
  input  logic            trap_i,         // the instruction in MEM traps: discard the one in EX
  input  logic            freeze_i,       // the pipeline holds this cycle
  input  logic            mem_wait_i,     // MEM waits for a response: no new request
  input  logic [XLEN-1:0] memwb_data_i,   // forwarding source FwdMemWb

  // ID/EX
  input  logic            idex_valid_i,
  input  idex_t           idex_i,

  // Control to earlier stages
  output logic            ex_redirect_o,
  output logic [XLEN-1:2] ex_target_o,
  output logic            req_wait_o,     // request not granted yet: the pipeline holds

  // EX/MEM
  output logic            exmem_valid_o,
  output exmem_t          exmem_o
);

  logic [XLEN-1:0] rs1_fwd, rs2_fwd, opb;
  logic [XLEN-1:0] alu_result, adder, csr_operand;
  logic            eq, lt, ltu, taken;
  logic            mem_op, instr_misaligned, access_misaligned;
  logic            exc;
  exc_cause_e      exc_cause;
  logic            exmem_valid_q;
  exmem_t          exmem_d, exmem_q;

  // ---- Operands -------------------------------------------------------------------------------

  // The selects were chosen in ID against the producers one stage behind (rv32_hazard).
  function automatic logic [XLEN-1:0] fwd(fwd_sel_e sel, logic [XLEN-1:0] rf_value);
    unique case (sel)
      FwdExMem: return exmem_q.ex_result;
      FwdMemWb: return memwb_data_i;
      default:  return rf_value;
    endcase
  endfunction

  always_comb begin : operands
    rs1_fwd = fwd(idex_i.fwd_a, idex_i.rs1_data);
    rs2_fwd = fwd(idex_i.fwd_b, idex_i.rs2_data);
    opb     = idex_i.opb_imm ? idex_i.imm : rs2_fwd;
  end

  rv32_alu u_alu (
    .op_i    (idex_i.alu_op),
    .a_i     (rs1_fwd),
    .b_i     (opb),
    .result_o(alu_result),
    .adder_o (adder),
    .eq_o    (eq),
    .lt_o    (lt),
    .ltu_o   (ltu)
  );

  // ---- Branch resolution ----------------------------------------------------------------------

  rv32_branch_cond u_branch_cond (
    .funct3_i(idex_i.funct3),
    .eq_i    (eq),
    .lt_i    (lt),
    .ltu_i   (ltu),
    .taken_o (taken)
  );

  // While the pipeline is frozen the redirect repeats every cycle, to the same target. That is
  // harmless: IF does not fetch during a freeze, and the instruction in ID is on the wrong path.
  rv32_redirect_logic u_redirect_logic (
    .valid_i      (idex_valid_i),
    .branch_i     (idex_i.branch),
    .jalr_i       (idex_i.jalr),
    .pred_taken_i (idex_i.pred_taken),
    .taken_i      (taken),
    .alt_pc_i     (idex_i.alt_pc),
    .adder_i      (adder),
    .imm_bit1_i   (idex_i.imm[1]),
    .ex_redirect_o,
    .ex_target_o,
    .misaligned_o (instr_misaligned)
  );

  // ---- Data request ---------------------------------------------------------------------------

  assign mem_op = idex_i.mem_re | idex_i.mem_we;

  rv32_store_align u_store_align (
    .addr_i      (adder[1:0]),
    .funct3_i    (idex_i.funct3),
    .data_i      (rs2_fwd),
    .be_o        (data_be_o),
    .data_o      (data_wdata_o),
    .misaligned_o(access_misaligned)
  );

  // An exception from ID keeps its cause; EX adds misaligned targets and accesses.
  always_comb begin : ex_exception
    exc       = idex_i.exc;
    exc_cause = idex_i.exc_cause;
    if (!idex_i.exc) begin
      if (instr_misaligned) begin
        exc       = 1'b1;
        exc_cause = EXC_INSTR_MISALIGNED;
      end else if (mem_op && access_misaligned) begin
        exc       = 1'b1;
        exc_cause = idex_i.mem_we ? EXC_STORE_MISALIGNED : EXC_LOAD_MISALIGNED;
      end
    end
  end

  assign data_req_o  = idex_valid_i & mem_op & ~exc & ~trap_i & ~mem_wait_i;
  assign data_addr_o = adder;
  assign data_we_o   = idex_i.mem_we;
  assign req_wait_o  = data_req_o & ~data_gnt_i;

  // ---- Result and EX/MEM ----------------------------------------------------------------------

  assign csr_operand = idex_i.funct3[2] ? {27'b0, idex_i.imm[19:15]} : rs1_fwd;

  always_comb begin : exmem_next
    exmem_d.pc        = idex_i.pc;
    exmem_d.csr_addr  = csr_num_e'(idex_i.imm[31:20]);
    exmem_d.funct3    = idex_i.funct3;
    exmem_d.rd        = idex_i.rd;
    exmem_d.rd_we     = idex_i.rd_we;
    exmem_d.mem_re    = idex_i.mem_re;
    exmem_d.mem_we    = idex_i.mem_we;
    exmem_d.req       = data_req_o & data_gnt_i;
    exmem_d.csr       = idex_i.csr;
    exmem_d.csr_write = (idex_i.funct3[1:0] == 2'b01) | (idex_i.imm[19:15] != '0);
    exmem_d.mret      = idex_i.mret;
    exmem_d.exc       = exc;
    exmem_d.exc_cause = exc_cause;
    if (idex_i.rd_alt_pc) begin
      exmem_d.ex_result = {idex_i.alt_pc, 2'b00};
    end else if (idex_i.csr) begin
      exmem_d.ex_result = csr_operand;
    end else begin
      exmem_d.ex_result = alu_result;   // for loads and stores, the address
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : exmem_valid_reg
    if (!rst_ni) begin
      exmem_valid_q <= 1'b0;
    end else if (trap_i) begin
      exmem_valid_q <= 1'b0;
    end else if (!freeze_i) begin
      exmem_valid_q <= idex_valid_i;
    end
  end

  always_ff @(posedge clk_i) begin : exmem_reg
    if (!freeze_i) begin
      exmem_q <= exmem_d;
    end
  end

  assign exmem_valid_o = exmem_valid_q;
  assign exmem_o       = exmem_q;

endmodule
