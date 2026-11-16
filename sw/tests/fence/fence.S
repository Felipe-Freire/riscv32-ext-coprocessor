// FENCE, which the core decodes as a no-op (rtl/core/units/rv32_decoder.sv): the point is that it
// retires, writes no register and does not disturb the instructions around it.
//
// FENCE.I is not here either: this core does not implement Zifencei, and the decoder raises an
// illegal instruction for any MISC_MEM with funct3 != 0. That agreement with the reference is
// checked in sw/tests/trap, where it belongs.
//
// WFI is deliberately not here. The core treats it as a no-op, while standalone Spike waits for an
// interrupt that nothing in this testbench can raise, so the reference never finishes and the run
// hangs. The DPI co-simulation has a wfi_as_nop option for exactly this
// (verif/models/riscv/README.md); until the testbench models the timer, WFI cannot be compared.
//
// main returns 0, or the number of the check that failed.

  .section .text
  .globl main
main:
  addi sp, sp, -16
  li   a0, 0

  // 1. FENCE between a store and the load that reads it back
  addi a0, a0, 1
  la   t0, scratch
  li   t1, 0x12345678
  sw   t1, 0(t0)
  fence
  lw   t2, 0(t0)
  bne  t2, t1, fail

  // 2. Every predecessor/successor combination of the fence operand field
  addi a0, a0, 1
  fence rw, rw
  fence r, r
  fence w, w
  fence iorw, iorw
  fence.tso
  li   t3, 7
  addi t4, t3, 1
  li   t5, 8
  bne  t4, t5, fail

  // 3. A fence does not disturb the instruction stream around it
  addi a0, a0, 1
  fence
  li   t0, 100
  addi t1, t0, 1
  li   t2, 101
  bne  t1, t2, fail

  // 4. A no-op between two dependent instructions does not break the forwarding
  addi a0, a0, 1
  li   t0, 41
  fence
  addi t1, t0, 1
  li   t2, 42
  bne  t1, t2, fail

  // 5. The no-ops write no register: t0 keeps its value across all of them
  addi a0, a0, 1
  li   t0, 0x5A5A5A5A
  fence
  fence w, r
  fence rw, rw
  li   t1, 0x5A5A5A5A
  bne  t0, t1, fail

  // 6. A store, a fence and a load on the same address, repeated in a loop
  addi a0, a0, 1
  la   t0, scratch
  li   t1, 0
  li   t3, 8
loop:
  sw   t1, 0(t0)
  fence
  lw   t2, 0(t0)
  bne  t2, t1, fail
  addi t1, t1, 1
  bne  t1, t3, loop

  li   a0, 0
fail:
  addi sp, sp, 16
  ret

  .section .data
  .align 2
scratch:
  .word 0
