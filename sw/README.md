# Software

RISC-V programs that run on the core during simulation: ISA tests, coprocessor tests and matrix
multiplication kernels. Programs are compiled to memory images (`.hex`) that the testbench
loads with `$readmemh`.

## Contents

| Directory | Contents |
|---|---|
| [`common/`](common/) | Startup code (`crt0.S`), linker script (`linker.ld`), helper headers, register definitions of the timer, DMA and coprocessor |
| [`tests/`](tests/) | Assembly and C test programs, one subdirectory or file per test |

## Toolchain

Use the RISC-V GNU toolchain (`riscv64-unknown-elf-gcc` handles RV32 with the flags below). Set
`-march` to the extensions the core implements ([core](../rtl/core/README.md#instructions)):

```bash
riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -nostdlib -T common/linker.ld ... -lgcc
```

`-lgcc` provides `__mulsi3` and the divide routines, since the core has no `M` extension. The DMA
and the coprocessor are memory-mapped: software programs them with ordinary loads and stores
through `volatile` pointers. Keep register addresses and fields in a header in `common/` so tests
never hard-code them. Addresses and register maps: [memory map](../rtl/top/README.md#memory-map),
[DMA](../rtl/dma/README.md#registers), [coprocessor](../rtl/coproc/README.md#registers),
[timer](../rtl/periph/README.md#timer).

## Boot

The testbench loads the I-TCM, the D-TCM and the L2 before it releases reset. The core starts in
the Boot ROM at `0x0000_0000`, which sets the stack pointer to the top of the D-TCM and jumps to
the program at `0x1000_0000` (I-TCM). Code goes in the I-TCM; data, read-only data and the stack
go in the D-TCM, because the core cannot load from the Boot ROM or the I-TCM.

## Matrix multiplication

`C = A·B` with A, B and C in their [L2 buffers](../rtl/top/README.md#matrix-buffers-in-l2), stored
in the [coprocessor layout](../rtl/coproc/README.md#matrix-layout). With `Ti = M/8` and `Tj = N/8`:

1. Coprocessor: write `DIM_M`, `DIM_N`, `DIM_K`, then `CTRL.START`. It waits for data.
2. DMA, one transfer per channel:

   | Channel | `ADDR` | `LEN` | `CNT1` | `STRIDE1` | `CNT2` | `STRIDE2` |
   |---|---|---|---|---|---|---|
   | 2 (C) | `0x2000_8000` | 4·M·N | 1 | 0 | 1 | 0 |
   | 0 (A) | `0x2000_0000` | 8·K | Tj | 0 | Ti | 8·K |
   | 1 (B) | `0x2000_4000` | K·N | Ti | 0 | 1 | 0 |

   Set `CTRL.IRQ_EN` on channel 2 only, then write `CTRL.START` on channels 2, 0 and 1.
3. Wait until channel 2 reports `DONE` or any channel reports `ERR`: poll `STATUS`, or set
   `mie.MEIE` and `mstatus.MIE` and handle it in the trap handler. `WFI` is a no-op, so the wait is
   always a loop.
4. Write 1 to the `DONE` bits to clear them, then read C from L2.

Channel 0 sends panel `i` of A once for each tile in tile row `i` (stride 0), channel 1 sends all
of B once per tile row, and channel 2 writes the tiles in the order the array produces them. To
measure a run, read `mcycle` before step 1 and after step 3.

## Conventions

- Build products (`.o`, `.elf`, `.hex`, disassembly) go to `build/sw/`, never into this directory.
- Each test reports pass/fail the same way (e.g. writing to a fixed "tohost" address) so the
  testbench can check every program with the same logic.

---
[← Back to project root](../README.md)
