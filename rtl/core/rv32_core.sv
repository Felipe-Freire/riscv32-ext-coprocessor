// RV32I + Zicsr core, machine mode only: five-stage in-order pipeline (rtl/core/README.md,
// docs/figures/core-datapath.drawio).
//
// The top only connects the stages. Its own logic is the freeze, which holds the whole pipeline
// while MEM waits for a data response or EX waits for a grant, and the register file write enable,
// which WB qualifies with the MEM/WB valid bit.
module rv32_core
  import rv32_pkg::*;
#(
  parameter logic [XLEN-1:0] BootAddr = 32'h0000_0000
) (
  input  logic            clk_i,
  input  logic            rst_ni,

  // Instruction port
  output logic            instr_req_o,
  output logic [XLEN-1:0] instr_addr_o,
  input  logic [31:0]     instr_rdata_i,
  input  logic            instr_err_i,

  // Data port (OBI)
  output logic            data_req_o,
  input  logic            data_gnt_i,
  output logic [XLEN-1:0] data_addr_o,
  output logic            data_we_o,
  output logic [3:0]      data_be_o,
  output logic [XLEN-1:0] data_wdata_o,
  input  logic            data_rvalid_i,
  input  logic [XLEN-1:0] data_rdata_i,
  input  logic            data_err_i,

  // Interrupts
  input  logic            irq_timer_i,
  input  logic            irq_external_i
);

  // IF
  logic            ifid_valid, ifid_err;
  logic [XLEN-1:2] ifid_pc, fetch_pc;
  logic [31:0]     ifid_instr;

  // ID
  logic            stall, id_redirect;
  logic [XLEN-1:2] id_target;
  logic            idex_valid;
  idex_t           idex;

  // EX
  logic            ex_redirect, req_wait;
  logic [XLEN-1:2] ex_target;
  logic            exmem_valid;
  exmem_t          exmem;

  // MEM
  logic            mem_wait, trap;
  logic [XLEN-1:2] trap_target;
  logic            memwb_valid, memwb_rd_we;
  logic [4:0]      memwb_rd;
  logic [XLEN-1:0] memwb_data;

  logic            freeze;

  assign freeze = mem_wait | req_wait;

  rv32_if_stage #(
    .BootAddr(BootAddr)
  ) u_if_stage (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .instr_req_o  (instr_req_o),
    .instr_addr_o (instr_addr_o),
    .instr_rdata_i(instr_rdata_i),
    .instr_err_i  (instr_err_i),
    .stall_i      (stall),
    .id_redirect_i(id_redirect),
    .id_target_i  (id_target),
    .ex_redirect_i(ex_redirect),
    .ex_target_i  (ex_target),
    .trap_i       (trap),
    .trap_target_i(trap_target),
    .pc_o         (fetch_pc),
    .ifid_valid_o (ifid_valid),
    .ifid_pc_o    (ifid_pc),
    .ifid_instr_o (ifid_instr),
    .ifid_err_o   (ifid_err)
  );

  rv32_id_stage u_id_stage (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .ex_redirect_i(ex_redirect),
    .trap_i       (trap),
    .freeze_i     (freeze),
    .exmem_valid_i(exmem_valid),
    .exmem_rd_i   (exmem.rd),
    .exmem_rd_we_i(exmem.rd_we),
    .wb_rd_i      (memwb_rd),
    .wb_data_i    (memwb_data),
    .wb_we_i      (memwb_valid & memwb_rd_we),
    .ifid_valid_i (ifid_valid),
    .ifid_pc_i    (ifid_pc),
    .ifid_instr_i (ifid_instr),
    .ifid_err_i   (ifid_err),
    .pc_i         (fetch_pc),
    .stall_o      (stall),
    .id_redirect_o(id_redirect),
    .id_target_o  (id_target),
    .idex_valid_o (idex_valid),
    .idex_o       (idex)
  );

  rv32_ex_stage u_ex_stage (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .data_req_o   (data_req_o),
    .data_gnt_i   (data_gnt_i),
    .data_addr_o  (data_addr_o),
    .data_we_o    (data_we_o),
    .data_be_o    (data_be_o),
    .data_wdata_o (data_wdata_o),
    .trap_i       (trap),
    .freeze_i     (freeze),
    .mem_wait_i   (mem_wait),
    .memwb_data_i (memwb_data),
    .idex_valid_i (idex_valid),
    .idex_i       (idex),
    .ex_redirect_o(ex_redirect),
    .ex_target_o  (ex_target),
    .req_wait_o   (req_wait),
    .exmem_valid_o(exmem_valid),
    .exmem_o      (exmem)
  );

  rv32_mem_stage u_mem_stage (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .data_gnt_i    (data_gnt_i),
    .data_rvalid_i (data_rvalid_i),
    .data_rdata_i  (data_rdata_i),
    .data_err_i    (data_err_i),
    .irq_timer_i   (irq_timer_i),
    .irq_external_i(irq_external_i),
    .freeze_i      (freeze),
    .ex_req_i      (data_req_o),
    .exmem_valid_i (exmem_valid),
    .exmem_i       (exmem),
    .mem_wait_o    (mem_wait),
    .trap_o        (trap),
    .trap_target_o (trap_target),
    .memwb_valid_o (memwb_valid),
    .memwb_rd_o    (memwb_rd),
    .memwb_rd_we_o (memwb_rd_we),
    .memwb_data_o  (memwb_data)
  );

endmodule
