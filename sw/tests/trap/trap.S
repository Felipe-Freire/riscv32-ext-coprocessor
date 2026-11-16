// Exceptions and MRET: every cause the core raises (rtl/core/rv32_pkg.sv exc_cause_e), checked
// through mcause and mepc, plus the mstatus.MIE / MPIE handling of a trap and its return.
//
// The handler always returns to the address the test left in s0, instead of mepc + 4. That way the
// same handler works for a fetch fault and for a misaligned jump, where mepc + 4 is not a sane
// place to resume.
//
// Registers across a trap: s0 the resume address, s1 mcause, s2 mepc, s3 mtval (read to exercise
// the path, never compared: this core reads it as zero and the reference does not, which is why
// mtval is in the volatile set of cmp_trace.py).
//
// main returns 0, or the number of the check that failed.

#define CAUSE_INSTR_MISALIGNED   0
#define CAUSE_INSTR_ACCESS_FAULT 1
#define CAUSE_ILLEGAL_INSTR      2
#define CAUSE_BREAKPOINT         3
#define CAUSE_LOAD_MISALIGNED    4
#define CAUSE_LOAD_ACCESS_FAULT  5
#define CAUSE_STORE_MISALIGNED   6
#define CAUSE_STORE_ACCESS_FAULT 7
#define CAUSE_ECALL_M           11

// Checks mcause against \cause and mepc against \at, then counts the check.
.macro CHECK_TRAP cause, at
  li   t0, \cause
  bne  s1, t0, fail
  la   t0, \at
  bne  s2, t0, fail
.endm

  .section .text
  .globl main
main:
  addi sp, sp, -16
  li   a0, 0

  la   t0, handler
  csrw mtvec, t0

  // 1. ECALL: cause 11, mepc at the ECALL itself
  addi a0, a0, 1
  la   s0, resume1
  li   s1, -1
ecall_at:
  ecall
resume1:
  CHECK_TRAP CAUSE_ECALL_M, ecall_at

  // 2. EBREAK: cause 3
  addi a0, a0, 1
  la   s0, resume2
  li   s1, -1
ebreak_at:
  ebreak
resume2:
  CHECK_TRAP CAUSE_BREAKPOINT, ebreak_at

  // 3. Illegal instruction: an all-ones word is not an encoding
  addi a0, a0, 1
  la   s0, resume3
  li   s1, -1
illegal_at:
  .word 0xFFFFFFFF
resume3:
  CHECK_TRAP CAUSE_ILLEGAL_INSTR, illegal_at

  // 4. An unimplemented CSR is illegal too (0x7C0 is not one of the core's CSRs)
  addi a0, a0, 1
  la   s0, resume4
  li   s1, -1
badcsr_at:
  csrr t1, 0x7C0
resume4:
  CHECK_TRAP CAUSE_ILLEGAL_INSTR, badcsr_at

  // FENCE.I is not checked here. This core does not implement Zifencei and raises an illegal
  // instruction for any MISC_MEM with funct3 != 0, but Spike executes fence.i as a no-op whatever
  // its --isa says, so the two cannot agree and the program would fail on the reference. Like WFI,
  // it is outside what standalone Spike can co-simulate (sw/tests/fence/fence.S).

  // 5. Misaligned load: a word load two bytes off
  addi a0, a0, 1
  la   s0, resume5
  li   s1, -1
  la   t1, scratch
  addi t1, t1, 2
lw_at:
  lw   t2, 0(t1)
resume5:
  CHECK_TRAP CAUSE_LOAD_MISALIGNED, lw_at

  // 6. Misaligned store
  addi a0, a0, 1
  la   s0, resume6
  li   s1, -1
  la   t1, scratch
  addi t1, t1, 1
sw_at:
  sw   t2, 0(t1)
resume6:
  CHECK_TRAP CAUSE_STORE_MISALIGNED, sw_at

  // 7. Load access fault: nothing is mapped at 0x4000_0000 for either side
  addi a0, a0, 1
  la   s0, resume7
  li   s1, -1
  li   t1, 0x40000000
lw_fault_at:
  lw   t2, 0(t1)
resume7:
  CHECK_TRAP CAUSE_LOAD_ACCESS_FAULT, lw_fault_at

  // 8. Store access fault
  addi a0, a0, 1
  la   s0, resume8
  li   s1, -1
  li   t1, 0x40000000
sw_fault_at:
  sw   t2, 0(t1)
resume8:
  CHECK_TRAP CAUSE_STORE_ACCESS_FAULT, sw_fault_at

  // 9. Misaligned jump: JALR clears bit 0, so bit 1 is what makes a target misaligned
  addi a0, a0, 1
  la   s0, resume9
  li   s1, -1
  la   t1, main
  addi t1, t1, 2
jalr_at:
  jalr x0, 0(t1)
resume9:
  CHECK_TRAP CAUSE_INSTR_MISALIGNED, jalr_at

  // 10. Fetch fault: jumping outside the memory. mepc is the bad target, not the jump
  addi a0, a0, 1
  la   s0, resume10
  li   s1, -1
  li   t1, 0x40000000
jump_fault_at:
  jalr x0, 0(t1)
resume10:
  li   t0, CAUSE_INSTR_ACCESS_FAULT
  bne  s1, t0, fail
  li   t0, 0x40000000
  bne  s2, t0, fail

  // 11. A trap clears mstatus.MIE and keeps the old value in MPIE; MRET puts it back
  addi a0, a0, 1
  csrsi mstatus, 8               // MIE = 1
  la   s0, resume11
  li   s4, -1
mie_trap_at:
  ecall
resume11:
  andi t0, s4, 8                 // MIE as the handler saw it: cleared
  bne  t0, zero, fail
  andi t0, s4, 0x80              // MPIE as the handler saw it: the old MIE, set
  beq  t0, zero, fail
  csrr t0, mstatus               // and MRET restored MIE
  andi t0, t0, 8
  beq  t0, zero, fail
  csrci mstatus, 8

  // 12. Back-to-back traps: the second one must not see any state from the first
  addi a0, a0, 1
  la   s0, resume12a
  li   s1, -1
ecall_again_at:
  ecall
resume12a:
  CHECK_TRAP CAUSE_ECALL_M, ecall_again_at
  la   s0, resume12b
  li   s1, -1
ebreak_again_at:
  ebreak
resume12b:
  CHECK_TRAP CAUSE_BREAKPOINT, ebreak_again_at

  // 13. The pipeline is still healthy after all of that
  addi a0, a0, 1
  li   t0, 5
  addi t1, t0, 3
  li   t2, 8
  bne  t1, t2, fail
  la   t1, scratch
  li   t2, 0x1234
  sw   t2, 0(t1)
  lw   t3, 0(t1)
  bne  t3, t2, fail

  // Leave mtvec as it was
  csrw mtvec, zero
  li   a0, 0
fail:
  addi sp, sp, 16
  ret

// ---- Trap handler: records the cause, returns to the address in s0 --------------------------
  .align 2
handler:
  csrr s1, mcause
  csrr s2, mepc
  csrr s3, mtval                 // exercised, never compared
  csrr s4, mstatus               // for check 11
  csrw mepc, s0
  mret

  .section .data
  .align 2
scratch:
  .word 0
  .word 0
