// CSRs and trap control (MEM, the commit point): machine-mode CSRs, exceptions, interrupts and
// MRET.
//
// The instruction in MEM traps when it carries an exception (from ID, EX or its own data access) or
// accesses a CSR illegally. An interrupt is taken on the instruction in MEM, which then does not
// execute and becomes mepc. It waits instead when that instruction is a load or store, because the
// request already left in EX.
//
// A trapping instruction never writes a CSR. CSR writes and the minstret count happen only in the
// cycle the instruction leaves MEM.
module rv32_csr
  import rv32_pkg::*;
(
  input  logic            clk_i,
  input  logic            rst_ni,

  input  logic            irq_timer_i,
  input  logic            irq_external_i,
  input  logic            freeze_i,       // MEM holds its instruction this cycle

  // Instruction in MEM
  input  logic            valid_i,        // valid, and its data response (if any) has arrived
  input  logic [XLEN-1:2] pc_i,
  input  logic            exc_i,
  input  exc_cause_e      exc_cause_i,
  input  logic            irq_allowed_i,  // the instruction may be replaced by an interrupt
  input  logic            csr_i,
  input  csr_num_e        csr_addr_i,
  input  logic [1:0]      csr_op_i,       // funct3[1:0]: 01 write, 10 set, 11 clear
  input  logic            csr_write_i,    // the instruction writes the CSR
  input  logic [XLEN-1:0] csr_wdata_i,    // rs1 or zimm
  input  logic            mret_i,

  output logic [XLEN-1:0] csr_rdata_o,
  output logic            kill_o,         // exception or interrupt: the instruction does not retire
  output logic            trap_o,         // redirect the fetch: exception, interrupt or MRET
  output logic [XLEN-1:2] trap_target_o
);

  logic            mie_q, mpie_q;          // mstatus.MIE, mstatus.MPIE
  logic            mtie_q, meie_q;         // mie.MTIE, mie.MEIE
  logic            mtip_q, meip_q;         // mip, registered interrupt lines
  logic [XLEN-1:2] mtvec_q, mepc_q;
  logic [XLEN-1:0] mscratch_q;
  logic            mcause_irq_q;
  logic [3:0]      mcause_code_q;
  logic [63:0]     mcycle_q, minstret_q;

  logic            implemented, illegal;
  logic [XLEN-1:0] wdata;
  mstatus_t        wdata_mstatus;
  mix_t            wdata_mie;
  mcause_t         wdata_mcause;
  logic            exc_take, irq_take, mret_take, csr_we, retire;
  logic            irq_timer, irq_external;
  logic [3:0]      cause_code;

  // ---- Read -----------------------------------------------------------------------------------

  always_comb begin : csr_read
    implemented = 1'b1;
    unique case (csr_addr_i)
      CSR_MSTATUS:   csr_rdata_o = mstatus_t'{mpp: PRIV_LVL_M, mpie: mpie_q, mie: mie_q, default: '0};
      CSR_MISA:      csr_rdata_o = MISA_VALUE;
      CSR_MIE:       csr_rdata_o = mix_t'{mei: meie_q, mti: mtie_q, default: '0};
      CSR_MTVEC:     csr_rdata_o = {mtvec_q, 2'b00};
      CSR_MSCRATCH:  csr_rdata_o = mscratch_q;
      CSR_MEPC:      csr_rdata_o = {mepc_q, 2'b00};
      CSR_MCAUSE:    csr_rdata_o = mcause_t'{irq: mcause_irq_q, code: mcause_code_q,
                                             default: '0};
      CSR_MTVAL:     csr_rdata_o = '0;
      CSR_MIP:       csr_rdata_o = mix_t'{mei: meip_q, mti: mtip_q, default: '0};
      CSR_MCYCLE:    csr_rdata_o = mcycle_q[31:0];
      CSR_MCYCLEH:   csr_rdata_o = mcycle_q[63:32];
      CSR_MINSTRET:  csr_rdata_o = minstret_q[31:0];
      CSR_MINSTRETH: csr_rdata_o = minstret_q[63:32];
      CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID: csr_rdata_o = '0;
      default: begin
        csr_rdata_o = '0;
        implemented = 1'b0;
      end
    endcase
  end

  // Addresses with bits 11:10 = 11 are read-only. Writes to read-only fields of a read/write CSR
  // (misa, mtval, mip) are ignored.
  assign illegal = csr_i & (~implemented | (csr_write_i & (csr_addr_i[11:10] == 2'b11)));

  always_comb begin : write_value
    unique case (csr_op_i)
      2'b01:   wdata = csr_wdata_i;
      2'b10:   wdata = csr_rdata_o | csr_wdata_i;
      default: wdata = csr_rdata_o & ~csr_wdata_i;
    endcase
  end

  // The value written, seen through the layout of the CSR it goes to.
  assign wdata_mstatus = mstatus_t'(wdata);
  assign wdata_mie     = mix_t'(wdata);
  assign wdata_mcause  = mcause_t'(wdata);

  // ---- Trap decision --------------------------------------------------------------------------

  assign irq_external = meip_q & meie_q;
  assign irq_timer    = mtip_q & mtie_q;

  assign exc_take  = valid_i & (exc_i | illegal);
  assign irq_take  = valid_i & ~exc_take & irq_allowed_i & mie_q & (irq_external | irq_timer);
  assign mret_take = valid_i & mret_i & ~exc_take & ~irq_take;

  assign kill_o        = exc_take | irq_take;
  assign trap_o        = kill_o | mret_take;
  assign trap_target_o = mret_take ? mepc_q : mtvec_q;

  // External interrupts have priority over the timer.
  always_comb begin : trap_cause
    if (irq_take) begin
      cause_code = irq_external ? IRQ_EXTERNAL : IRQ_TIMER;
    end else if (exc_i) begin
      cause_code = exc_cause_i;
    end else begin
      cause_code = EXC_ILLEGAL_INSTR;
    end
  end

  assign csr_we = valid_i & csr_i & csr_write_i & ~kill_o & ~freeze_i;
  assign retire = valid_i & ~kill_o & ~freeze_i;

  // ---- State ----------------------------------------------------------------------------------

  always_ff @(posedge clk_i or negedge rst_ni) begin : irq_lines
    if (!rst_ni) begin
      mtip_q <= 1'b0;
      meip_q <= 1'b0;
    end else begin
      mtip_q <= irq_timer_i;
      meip_q <= irq_external_i;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : trap_regs
    if (!rst_ni) begin
      mie_q         <= 1'b0;
      mpie_q        <= 1'b0;
      mtie_q        <= 1'b0;
      meie_q        <= 1'b0;
      mtvec_q       <= '0;
      mepc_q        <= '0;
      mscratch_q    <= '0;
      mcause_irq_q  <= 1'b0;
      mcause_code_q <= '0;
    end else if (kill_o) begin
      mepc_q        <= pc_i;
      mcause_irq_q  <= irq_take;
      mcause_code_q <= cause_code;
      mpie_q        <= mie_q;
      mie_q         <= 1'b0;
    end else if (mret_take) begin
      mie_q         <= mpie_q;
      mpie_q        <= 1'b1;
    end else if (csr_we) begin
      unique case (csr_addr_i)
        CSR_MSTATUS: begin
          mie_q  <= wdata_mstatus.mie;
          mpie_q <= wdata_mstatus.mpie;
        end
        CSR_MIE: begin
          mtie_q <= wdata_mie.mti;
          meie_q <= wdata_mie.mei;
        end
        CSR_MTVEC:    mtvec_q    <= wdata[XLEN-1:2];
        CSR_MSCRATCH: mscratch_q <= wdata;
        CSR_MEPC:     mepc_q     <= wdata[XLEN-1:2];
        CSR_MCAUSE: begin
          mcause_irq_q  <= wdata_mcause.irq;
          mcause_code_q <= wdata_mcause.code;
        end
        default: ;
      endcase
    end
  end

  // A write to a counter replaces the increment of that cycle.
  always_ff @(posedge clk_i or negedge rst_ni) begin : counters
    if (!rst_ni) begin
      mcycle_q   <= '0;
      minstret_q <= '0;
    end else begin
      if (csr_we && csr_addr_i == CSR_MCYCLE) begin
        mcycle_q[31:0] <= wdata;
      end else if (csr_we && csr_addr_i == CSR_MCYCLEH) begin
        mcycle_q[63:32] <= wdata;
      end else begin
        mcycle_q <= mcycle_q + 1'b1;
      end
      if (csr_we && csr_addr_i == CSR_MINSTRET) begin
        minstret_q[31:0] <= wdata;
      end else if (csr_we && csr_addr_i == CSR_MINSTRETH) begin
        minstret_q[63:32] <= wdata;
      end else if (retire) begin
        minstret_q <= minstret_q + 1'b1;
      end
    end
  end

endmodule
