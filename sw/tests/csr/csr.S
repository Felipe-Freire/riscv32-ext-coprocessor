// Zicsr: CSRRW, CSRRS, CSRRC and their immediate forms, over the CSRs the core implements
// (rtl/core/rv32_pkg.sv). Written in assembly, since C has no way to name a CSR operand form.
//
// Values are only checked where the core and Spike must agree. mcycle and minstret are compared
// for the fact that they advance, never for their value: the reference has no pipeline, so the
// numbers differ by design. cmp_trace.py knows about that (--volatile-csr).
//
// mtvec and mepc are written 4-byte aligned on purpose: the core keeps bits [31:2] and reads the
// low two back as zero, while Spike keeps the mode bits of mtvec, so an unaligned write would
// read back differently on the two sides for a legal reason.
//
// main returns 0, or the number of the check that failed.

#define MSTATUS   0x300
#define MISA      0x301
#define MIE       0x304
#define MTVEC     0x305
#define MSCRATCH  0x340
#define MEPC      0x341
#define MCYCLE    0xB00
#define MINSTRET  0xB02
#define MCYCLEH   0xB80
#define MINSTRETH 0xB82

  .section .text
  .globl main
main:
  addi sp, sp, -16
  li   a0, 0

  // ---- mscratch: the one freely writable 32-bit CSR, so every operand form goes through it

  // 1. CSRRW writes, CSRRS with rs1 = x0 reads
  addi a0, a0, 1
  li   t0, 0xDEADBEEF
  csrw mscratch, t0            // csrrw x0, mscratch, t0
  csrr t1, mscratch            // csrrs t1, mscratch, x0
  bne  t1, t0, fail

  // 2. CSRRW returns the old value and installs the new one
  addi a0, a0, 1
  li   t0, 0x12345678
  csrrw t1, mscratch, t0
  li   t2, 0xDEADBEEF
  bne  t1, t2, fail
  csrr t1, mscratch
  bne  t1, t0, fail

  // 3. CSRRS sets bits and returns the value from before
  addi a0, a0, 1
  li   t0, 0x000000FF
  csrrs t1, mscratch, t0
  li   t2, 0x12345678
  bne  t1, t2, fail
  csrr t1, mscratch
  li   t2, 0x123456FF
  bne  t1, t2, fail

  // 4. CSRRC clears bits
  addi a0, a0, 1
  li   t0, 0x0000000F
  csrrc t1, mscratch, t0
  li   t2, 0x123456FF
  bne  t1, t2, fail
  csrr t1, mscratch
  li   t2, 0x123456F0
  bne  t1, t2, fail

  // 5. CSRRWI: the 5-bit zimm field replaces rs1
  addi a0, a0, 1
  csrrwi t1, mscratch, 31
  li   t2, 0x123456F0
  bne  t1, t2, fail
  csrr t1, mscratch
  li   t2, 31
  bne  t1, t2, fail

  // 6. CSRRSI and CSRRCI
  addi a0, a0, 1
  csrrci t1, mscratch, 15      // 31 & ~15 = 16
  csrr t1, mscratch
  li   t2, 16
  bne  t1, t2, fail
  csrrsi t1, mscratch, 3       // 16 | 3 = 19
  csrr t1, mscratch
  li   t2, 19
  bne  t1, t2, fail

  // 7. A read-only access leaves the CSR alone: CSRRS and CSRRC with rs1 = x0, CSRRSI with zimm 0
  addi a0, a0, 1
  csrrs t1, mscratch, x0
  csrrc t1, mscratch, x0
  csrrsi t1, mscratch, 0
  csrr t1, mscratch
  li   t2, 19
  bne  t1, t2, fail

  // 8. A write with rd = x0 still writes
  addi a0, a0, 1
  li   t0, 0x5A5A5A5A
  csrrw x0, mscratch, t0
  csrr t1, mscratch
  bne  t1, t0, fail

  // ---- Read-only CSRs

  // 9. misa: MXL = 32 and extension I, nothing else
  addi a0, a0, 1
  csrr t0, misa
  li   t1, 0x40000100
  bne  t0, t1, fail

  // 10. mhartid: the only hart
  addi a0, a0, 1
  csrr t0, mhartid
  bne  t0, zero, fail

  // ---- Counters: checked for advancing, never for their value

  // 11. mcycle moves on
  addi a0, a0, 1
  csrr t0, mcycle
  nop
  nop
  csrr t1, mcycle
  beq  t0, t1, fail
  sltu t2, t0, t1              // and it counts up
  beq  t2, zero, fail

  // 12. minstret moves on
  addi a0, a0, 1
  csrr t0, minstret
  nop
  nop
  csrr t1, minstret
  sltu t2, t0, t1
  beq  t2, zero, fail

  // 13. Both counters are writable, and the high words are still zero this early
  addi a0, a0, 1
  csrw mcycle, zero
  csrr t0, mcycle
  li   t1, 1000                // whatever the pipeline does, it is not thousands of cycles
  bgeu t0, t1, fail
  csrw minstret, zero
  csrr t0, minstret
  bgeu t0, t1, fail

  // 14. mcycleh and minstreth
  addi a0, a0, 1
  csrr t0, mcycleh
  bne  t0, zero, fail
  csrr t0, minstreth
  bne  t0, zero, fail
  csrw mcycleh, zero
  csrr t0, mcycleh
  bne  t0, zero, fail

  // ---- Trap CSRs, written without taking a trap

  // 15. mtvec, 4-byte aligned
  addi a0, a0, 1
  la   t0, main
  csrw mtvec, t0
  csrr t1, mtvec
  bne  t1, t0, fail

  // 16. mepc, 4-byte aligned
  addi a0, a0, 1
  la   t0, main
  csrw mepc, t0
  csrr t1, mepc
  bne  t1, t0, fail

  // 17. mstatus.MIE, bit 3: set it, read it back, clear it again
  addi a0, a0, 1
  csrrsi t1, mstatus, 8
  csrr t0, mstatus
  andi t1, t0, 8
  beq  t1, zero, fail
  csrrci t1, mstatus, 8
  csrr t0, mstatus
  andi t1, t0, 8
  bne  t1, zero, fail

  // 18. mie: MTIE is bit 7, MEIE bit 11
  addi a0, a0, 1
  li   t0, 0x880               // both
  csrs mie, t0
  csrr t1, mie
  bne  t1, t0, fail
  csrc mie, t0
  csrr t1, mie
  bne  t1, zero, fail

  // 19. Left in a clean state: mtvec and mepc back to zero
  addi a0, a0, 1
  csrw mtvec, zero
  csrw mepc, zero
  csrr t0, mtvec
  bne  t0, zero, fail
  csrr t0, mepc
  bne  t0, zero, fail

  li   a0, 0
fail:
  addi sp, sp, 16
  ret
