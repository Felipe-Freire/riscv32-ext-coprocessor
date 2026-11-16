/* DUT macros for the riscv-arch-test (ACT4) framework, for rv32_core on tb_rv32_core_cosim.
 *
 * The framework needs a handful of target-specific definitions: how a test ends, how it prints,
 * which address faults, and what to do instead of FENCE.I. Everything interrupt or peripheral
 * related is deliberately absent, because the testbench has no CLINT, no PLIC and no UART; the
 * suites that need them have to be excluded (see README.md).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef _RVMODEL_MACROS_H
#define _RVMODEL_MACROS_H

/* HTIF tohost / fromhost, the same pair sw/common/crt0.S uses, so the testbench stops on the
 * store without knowing anything about this framework. */
#define RVMODEL_DATA_SECTION \
        .pushsection .tohost,"aw",@progbits;                \
        .balign 8; .global tohost; tohost: .dword 0;        \
        .balign 8; .global fromhost; fromhost: .dword 0;    \
        .popsection

/* The core implements the standard M-mode CSRs, so the framework's own boot code works. */
#define STANDARD_SM_SUPPORTED

/* Nothing to set up: the testbench releases reset with the whole image already in memory. */
/* #define RVMODEL_BOOT */

/* tohost = 1 passes, tohost = 3 fails, which is what crt0 encodes as (code << 1) | 1. */
#define RVMODEL_HALT_PASS   \
  li x1, 1                 ;\
  la t0, tohost            ;\
  write_tohost_pass:       ;\
    sw x1, 0(t0)           ;\
    sw x0, 4(t0)           ;\
    j write_tohost_pass    ;\

#define RVMODEL_HALT_FAIL   \
  li x1, 3                 ;\
  la t0, tohost            ;\
  write_tohost_fail:       ;\
    sw x1, 0(t0)           ;\
    sw x0, 4(t0)           ;\
    j write_tohost_fail    ;\

/* No UART in the testbench. The framework only uses these for diagnostics, and the real verdict
 * is the tohost code plus the trace comparison against Spike. */
#define RVMODEL_IO_INIT(_R1, _R2, _R3)
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR)

/* The core is in order, its bus accesses are non-posted and there is no instruction cache, so
 * instruction fetch is already coherent with stores. Defining this keeps the framework from
 * emitting FENCE.I, which this core raises an illegal instruction for (it has no Zifencei). */
#define RVMODEL_FENCEI nop

/* Nothing is mapped outside the 4 MiB RAM at 0x8000_0000, so this address faults on both the core
 * and the reference (sw/tests/trap/trap.S uses it for the same purpose). */
#define RVMODEL_ACCESS_FAULT_ADDRESS 0x40000000

#endif /* _RVMODEL_MACROS_H */
