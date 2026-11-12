// Memory stage: data response, load alignment, CSRs and traps (rv32_csr), the WB mux and the MEM/WB
// register.
//
// MEM is the commit point. An instruction whose request was granted in EX waits here for the
// response; while it waits (mem_wait_o) the whole pipeline holds. A trap or MRET redirects the
// fetch, and a trapping instruction leaves MEM invalid, so it never writes a register.
//
// The response can arrive while the pipeline holds for another reason: EX sent the next request in
// the same cycle and has no grant yet. MEM then keeps the response (rsp_q) until it advances.
module rv32_mem_stage
  import rv32_pkg::*;
(
  input  logic            clk_i,
  input  logic            rst_ni,

  // Data port (OBI response) and interrupts
  input  logic            data_gnt_i,
  input  logic            data_rvalid_i,
  input  logic [XLEN-1:0] data_rdata_i,
  input  logic            data_err_i,
  input  logic            irq_timer_i,
  input  logic            irq_external_i,

  // Control
  input  logic            freeze_i,       // the pipeline holds this cycle
  input  logic            ex_req_i,       // EX sends a data request this cycle

  // EX/MEM
  input  logic            exmem_valid_i,
  input  exmem_t          exmem_i,

  // Control to earlier stages
  output logic            mem_wait_o,
  output logic            trap_o,
  output logic [XLEN-1:2] trap_target_o,

  // MEM/WB
  output logic            memwb_valid_o,
  output logic [4:0]      memwb_rd_o,
  output logic            memwb_rd_we_o,
  output logic [XLEN-1:0] memwb_data_o
);

  logic            access_fault, kill, req_pending_q;
  logic            rsp_valid, rsp_held_q;
  logic [XLEN-1:0] rsp_data, rsp_data_q;
  exc_cause_e      exc_cause;
  logic [XLEN-1:0] load_data, csr_rdata, wb_data;
  logic            memwb_valid_q, memwb_rd_we_q;
  logic [4:0]      memwb_rd_q;
  logic [XLEN-1:0] memwb_data_q;

  // An error response always traps, which drops the EX request, so a held response has no error.
  always_ff @(posedge clk_i or negedge rst_ni) begin : rsp_held_reg
    if (!rst_ni) begin
      rsp_held_q <= 1'b0;
    end else begin
      rsp_held_q <= freeze_i & (rsp_held_q | (exmem_valid_i & exmem_i.req & data_rvalid_i));
    end
  end

  always_ff @(posedge clk_i) begin : rsp_data_reg
    if (freeze_i && data_rvalid_i) begin
      rsp_data_q <= data_rdata_i;
    end
  end

  assign rsp_valid = data_rvalid_i | rsp_held_q;
  assign rsp_data  = rsp_held_q ? rsp_data_q : data_rdata_i;

  assign mem_wait_o   = exmem_valid_i & exmem_i.req & ~rsp_valid;
  assign access_fault = exmem_valid_i & exmem_i.req & data_rvalid_i & data_err_i;

  // A request EX sent without a grant must stay until granted, so no interrupt may flush it.
  always_ff @(posedge clk_i or negedge rst_ni) begin : req_pending_reg
    if (!rst_ni) begin
      req_pending_q <= 1'b0;
    end else begin
      req_pending_q <= ex_req_i & ~data_gnt_i;
    end
  end

  assign exc_cause = exmem_i.exc   ? exmem_i.exc_cause      :
                     exmem_i.mem_we ? EXC_STORE_ACCESS_FAULT : EXC_LOAD_ACCESS_FAULT;

  rv32_csr u_csr (
    .clk_i,
    .rst_ni,
    .irq_timer_i,
    .irq_external_i,
    .freeze_i,
    .valid_i      (exmem_valid_i & ~mem_wait_o),
    .pc_i         (exmem_i.pc),
    .exc_i        (exmem_i.exc | access_fault),
    .exc_cause_i  (exc_cause),
    .irq_allowed_i(~exmem_i.req & ~req_pending_q),
    .csr_i        (exmem_i.csr),
    .csr_addr_i   (exmem_i.csr_addr),
    .csr_op_i     (exmem_i.funct3[1:0]),
    .csr_write_i  (exmem_i.csr_write),
    .csr_wdata_i  (exmem_i.ex_result),
    .mret_i       (exmem_i.mret),
    .csr_rdata_o  (csr_rdata),
    .kill_o       (kill),
    .trap_o,
    .trap_target_o
  );

  rv32_load_align u_load_align (
    .addr_i  (exmem_i.ex_result[1:0]),
    .funct3_i(exmem_i.funct3),
    .data_i  (rsp_data),
    .data_o  (load_data)
  );

  always_comb begin : wb_mux
    if (exmem_i.csr) begin
      wb_data = csr_rdata;
    end else if (exmem_i.mem_re) begin
      wb_data = load_data;
    end else begin
      wb_data = exmem_i.ex_result;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : memwb_valid_reg
    if (!rst_ni) begin
      memwb_valid_q <= 1'b0;
    end else if (!freeze_i) begin
      memwb_valid_q <= exmem_valid_i & ~kill;
    end
  end

  always_ff @(posedge clk_i) begin : memwb_reg
    if (!freeze_i) begin
      memwb_rd_q    <= exmem_i.rd;
      memwb_rd_we_q <= exmem_i.rd_we;
      memwb_data_q  <= wb_data;
    end
  end

  assign memwb_valid_o = memwb_valid_q;
  assign memwb_rd_o    = memwb_rd_q;
  assign memwb_rd_we_o = memwb_rd_we_q;
  assign memwb_data_o  = memwb_data_q;

endmodule
