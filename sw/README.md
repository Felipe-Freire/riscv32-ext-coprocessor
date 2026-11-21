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

## Building a test

```bash
make sw SW=sum                                    # build/sw/sum.{elf,hex,dis,sym,map}
make sim SW=sum                                   # run it on Spike and on the RTL core, compare
make regress LIST=verif/regress/cosim.list JOBS=8 # every test under tests/, as a table
```

`SW` is a directory under `tests/`; every `.c` and `.S` in it is linked together with
`common/crt0.S`, `common/linker.ld` and any shared helper in `common/*.c`. The flow is in
[`sw.mk`](sw.mk), the comparison against Spike in
[verif/README.md](../verif/README.md#comparing-the-core-against-spike).

## Tests

Each test includes [`common/check.h`](common/check.h) and returns the number of the first `CHECK`
that failed, so the exit code says which one broke. Instruction counts are what the core retires.

| Test | What it covers | Instructions |
|---|---|---|
| `sum`, `sub` | ADD, ADDI, SUB, immediate range, unsigned wraparound and borrow | ~105 |
| `mult`, `div` | `__mulsi3`, `__divsi3`, `__modsi3` from libgcc: no M extension | 745, 1191 |
| `logic` | AND, OR, XOR, SLL, SRL, SRA, shift amount in a register and as an immediate | 141 |
| `compare` | SLT, SLTU and the immediate forms at the signed/unsigned boundaries | 106 |
| `branch` | the six conditional branches taken and not taken, loops | 292 |
| `jump` | JAL, JALR, nested calls, calls through a function pointer | 210 |
| `loadstore` | LB/LBU/LH/LHU/LW, SB/SH/SW, byte lanes, sign extension, little endian | 206 |
| `upper` | LUI and AUIPC: 32-bit constants and PC-relative addresses | 115 |
| `hazard` | assembly: the forwarding paths, the load-use stall, x0 never written | 104 |
| `memcpy` | byte and word copy loops, memset, overlapping move, zero length | 4.8k |
| `recursion` | fib, factorial, mutual recursion: stack frames, saved `ra` | 11.6k |
| `crc32` | CRC-32 bit by bit and through a 256-entry table, both agreeing | 22.8k |
| `sort` | insertion sort and bubble sort over the same array, 48 elements | 50k |
| `matmul` | 8x8 integer matrix multiply, the software reference for the coprocessor | 67k |
| `csr` | assembly: CSRRW/S/C and the immediate forms over every implemented CSR | 157 |
| `trap` | assembly: all nine exception causes, `mepc`, `mcause`, MRET, `mstatus.MIE`/`MPIE` | 242 |
| `fence` | FENCE and its operand forms, decoded as a no-op | 109 |
| `bitops` | popcount, CLZ, CTZ, bit reversal, byte swap, rotation, field insert | 640 |
| `predictor` | branch patterns built to mispredict: the static prediction and the EX redirect | 14.4k |
| `fixedpoint` | Q15 multiply-accumulate with rounding and saturation | 6.1k |

Random programs are generated rather than written:

```bash
make sim SW=random7 RANDOM_COUNT=3000    # build/sw/random7/random7.S, seed 7
```

[`gen_random_test.py`](../scripts/utils/gen_random_test.py) emits a straight-line RV32I program
per seed. It needs no expected answer, because the trace comparison against Spike is the answer;
it only has to be deterministic and to terminate.

[riscv-dv](../verif/riscv-dv/README.md) generates far richer ones: branches, loops, calls, memory
streams, CSRs, exceptions and their handler.

```bash
make sim SW=rdv-riscv_rand_instr_test-7                         # test of verif/riscv-dv, seed 7
make sim SW=rdv-riscv_loop_test-3 RDV_OPTS=+instr_cnt=2000      # with extra generator plusargs
make regress LIST=verif/regress/riscv_dv.list JOBS=8
```

Writing a new one: keep the operands of the operation under test in `volatile` variables, or the
compiler folds the operation away and the test checks nothing. There is no libc, so an initialized
local array or struct can fail to link when gcc lowers it to a `memcpy` call; make it `static`, or
put a helper in `common/`. Keep every access naturally aligned unless the test is about traps,
since the core and Spike both trap on a misaligned load or store.

A test that needs other build settings puts them in `tests/<test>/test.mk` (`ARCH`, `SPIKE_ISA`,
`COSIM_TIMEOUT`, ...), which is included before the defaults. `SW_SRC` builds a program from
somewhere else entirely; the generated random programs live in `build/sw/random<seed>/`.

Two instructions cannot be co-simulated against standalone Spike, both for the same kind of
reason, and both are left out of the tests on purpose:

| Instruction | Core | Spike |
|---|---|---|
| `WFI` | no-op | waits for an interrupt nothing can raise, so the reference never finishes |
| `FENCE.I` | illegal instruction: no Zifencei ([decoder](../rtl/core/units/rv32_decoder.sv)) | executes it as a no-op whatever `--isa` says |

The DPI co-simulation in [`verif/models/riscv`](../verif/models/riscv/README.md) has a
`wfi_as_nop` option for the first; the second needs the core to accept `FENCE.I` as a no-op, which
would be legal for an in-order core with no instruction cache.

`crt0.S` sets the stack, zeroes `.bss`, calls `main` and ends the run by writing
`(main() << 1) | 1` to the HTIF `tohost` word: Spike exits with that code and the testbench stops
on the same store, so a program needs no testbench-specific exit path.

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
