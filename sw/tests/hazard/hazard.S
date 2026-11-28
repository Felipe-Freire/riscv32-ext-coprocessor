// Pipeline hazards, in assembly so the instruction sequences are exactly these: the forwarding
// paths (EX/MEM and MEM/WB back into EX), the load-use stall, operands forwarded into a branch or
// a jump target, and the rule that x0 is never written.
//
// A C compiler schedules these apart, which is why this test is hand written. main returns 0, or
// the number of the check that failed: a0 counts the checks and the fail path just returns it.
//
// Frame: 0(sp), 4(sp), 8(sp) scratch, 12(sp) saved ra.

  .section .text
  .globl main
main:
  addi sp, sp, -16
  sw   ra, 12(sp)
  li   a0, 0

  // 1. EX -> EX: the result is used by the very next instruction
  addi a0, a0, 1
  li   t0, 5
  addi t1, t0, 3
  li   t2, 8
  bne  t1, t2, fail

  // 2. Two dependent instructions in a row, both forwarded
  addi a0, a0, 1
  add  t3, t1, t1
  add  t4, t3, t1
  li   t5, 24
  bne  t4, t5, fail

  // 3. Load-use: the load is still in MEM when the next instruction needs it (the stall)
  addi a0, a0, 1
  li   t0, 8
  sw   t0, 0(sp)
  lw   t1, 0(sp)
  addi t2, t1, 1
  li   t3, 9
  bne  t2, t3, fail

  // 4. MEM/WB -> EX: two instructions in between, the value comes from the later stage
  addi a0, a0, 1
  li   t0, 100
  nop
  nop
  addi t1, t0, 1
  li   t2, 101
  bne  t1, t2, fail

  // 5. Store data forwarded from the instruction right before the store
  addi a0, a0, 1
  li   t0, 0x55
  sw   t0, 4(sp)
  lw   t1, 4(sp)
  li   t2, 0x55
  bne  t1, t2, fail

  // 6. Branch operand forwarded from the instruction right before the branch
  addi a0, a0, 1
  li   t0, 3
  addi t1, t0, -3
  bne  t1, zero, fail

  // 7. Load feeding a branch directly: the stall has to hold the branch too
  addi a0, a0, 1
  li   t0, 0x1234
  sw   t0, 0(sp)
  lw   t1, 0(sp)
  bne  t1, t0, fail

  // 8. JALR target forwarded from the instruction right before the jump (la is auipc + addi)
  addi a0, a0, 1
  li   a1, 0
  la   t0, set_a1
  jalr ra, 0(t0)
  li   t1, 42
  bne  a1, t1, fail

  // 9. x0 stays zero even when an instruction names it as the destination
  addi a0, a0, 1
  addi x0, x0, 7
  mv   t0, x0
  bne  t0, zero, fail

  // 10. Byte store then byte load of the same address
  addi a0, a0, 1
  li   t0, 0
  sw   t0, 8(sp)
  li   t0, 0xA5
  sb   t0, 8(sp)
  lbu  t1, 8(sp)
  bne  t1, t0, fail

  // 11. Dependent loads: the second load's address comes from the first load
  addi a0, a0, 1
  la   t0, scratch
  sw   t0, 8(sp)
  lw   t1, 8(sp)
  lw   t2, 0(t1)
  li   t3, 0x5A5A5A5A
  bne  t2, t3, fail

  // 12. Taken backward branch, four times, with the counter forwarded into the branch
  addi a0, a0, 1
  li   t0, 4
  li   t1, 0
loop:
  addi t1, t1, 2
  addi t0, t0, -1
  bne  t0, zero, loop
  li   t2, 8
  bne  t1, t2, fail

  // All checks passed
  li   a0, 0
fail:
  lw   ra, 12(sp)
  addi sp, sp, 16
  ret

// Called through JALR in check 8.
set_a1:
  li   a1, 42
  ret

  .section .data
  .align 2
scratch:
  .word 0x5A5A5A5A
