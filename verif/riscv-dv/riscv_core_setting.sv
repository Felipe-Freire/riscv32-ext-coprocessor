// riscv-dv target for rv32_core (vendor/riscv-dv, custom target: run.py --custom_target <this dir>).
// Describes what the core implements, so the generated programs stay inside it. Based on
// vendor/riscv-dv/target/rv32i/riscv_core_setting.sv; the differences are the core's own:
//   - mtvec has no MODE field (always direct), so no vectored interrupt mode;
//   - no mcounteren (no U mode), and misaligned loads and stores trap instead of completing;
//   - FENCE.I and WFI cannot be co-simulated against standalone Spike (sw/README.md).
// Interrupts are tied off in tb_rv32_core_cosim, so none are generated.

// ---- Processor feature configuration

parameter int XLEN = 32;
parameter satp_mode_t SATP_MODE = BARE;
privileged_mode_t supported_privileged_mode[] = {MACHINE_MODE};

riscv_instr_name_t unsupported_instr[] = {FENCE_I, WFI};

// RV32I with Zicsr: no M, no C.
riscv_instr_group_t supported_isa[$] = {RV32I};

mtvec_mode_t supported_interrupt_mode[$] = {DIRECT};
int max_interrupt_vector_num = 16;

bit support_pmp = 0;
bit support_epmp = 0;
bit support_debug_mode = 0;
bit support_umode_trap = 0;
bit support_sfence = 0;
bit support_unaligned_load_store = 1'b0;

// Unused here, but the generator needs them defined.
parameter int NUM_FLOAT_GPR = 32;
parameter int NUM_GPR = 32;
parameter int NUM_VEC_GPR = 32;
parameter int VECTOR_EXTENSION_ENABLE = 0;
parameter int VLEN = 512;
parameter int ELEN = 32;
parameter int SELEN = 8;
parameter int VELEN = int'($ln(ELEN)/$ln(2)) - 3;
parameter int MAX_LMUL = 8;
parameter int NUM_HARTS = 1;

// ---- Implemented CSRs (rtl/core/rv32_pkg.sv, rtl/core/units/rv32_csr.sv)

`ifdef DSIM
privileged_reg_t implemented_csr[] = {
`else
const privileged_reg_t implemented_csr[] = {
`endif
    MVENDORID,
    MARCHID,
    MIMPID,
    MHARTID,
    MSTATUS,
    MISA,
    MIE,
    MTVEC,
    MSCRATCH,
    MEPC,
    MCAUSE,
    MTVAL,
    MIP,
    MCYCLE,
    MINSTRET,
    MCYCLEH,
    MINSTRETH
};

bit [11:0] custom_csr[] = {
};

// ---- Supported interrupts and exceptions

`ifdef DSIM
interrupt_cause_t implemented_interrupt[] = {
`else
const interrupt_cause_t implemented_interrupt[] = {
`endif
    M_TIMER_INTR,
    M_EXTERNAL_INTR
};

`ifdef DSIM
exception_cause_t implemented_exception[] = {
`else
const exception_cause_t implemented_exception[] = {
`endif
    INSTRUCTION_ADDRESS_MISALIGNED,
    INSTRUCTION_ACCESS_FAULT,
    ILLEGAL_INSTRUCTION,
    BREAKPOINT,
    LOAD_ADDRESS_MISALIGNED,
    LOAD_ACCESS_FAULT,
    STORE_AMO_ADDRESS_MISALIGNED,
    STORE_AMO_ACCESS_FAULT,
    ECALL_MMODE
};
