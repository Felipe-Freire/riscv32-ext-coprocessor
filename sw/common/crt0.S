// Startup for the bare-metal test programs: stack, .bss, main, exit.
//
// Exit goes through HTIF, the protocol Spike already understands: tohost = (code << 1) | 1 stops
// Spike with that exit code, and the testbench stops on the same store. main's return value is the
// code, so 0 means pass.
  .section .text.init, "ax"
  .globl _start
_start:
  // Every register to zero, as Spike starts them. The register file has no reset, so on a 4-state
  // simulator a callee-saved register that main saves and restores would otherwise be X on the
  // core and 0 on Spike (Verilator, which is 2-state, hides it).
  .irp r, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
  li   x\r, 0
  .endr

  la   sp, _stack_top

  // .bss = 0
  la   t0, __bss_start
  la   t1, __bss_end
1:
  bgeu t0, t1, 2f
  sw   zero, 0(t0)
  addi t0, t0, 4
  j    1b
2:
  call main

  // tohost = (main() << 1) | 1
  slli a0, a0, 1
  ori  a0, a0, 1
  la   t0, tohost
  sw   a0, 0(t0)
3:
  j    3b          // Spike polls tohost every few hundred instructions

  .section .htif, "aw", @progbits
  .align 6
  .globl tohost
tohost:
  .dword 0
  .globl fromhost
fromhost:
  .dword 0
