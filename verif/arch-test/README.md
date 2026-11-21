# riscv-arch-test (ACT4)

Target configuration for running the official RISC-V architectural tests
([`vendor/riscv-arch-test`](../../vendor/riscv-arch-test)) on `rv32_core`.

**Status: prepared, not yet run.** The files here are complete and the DUT run command is tested,
but the framework itself cannot be built in this checkout yet: see [Prerequisites](#prerequisites).
Nothing in the co-simulation flow (`make sim SW=`) depends on this directory.

| File | Role |
|---|---|
| `test_config.yaml` | the framework's entry point: compiler, reference model, linker script, UDB config |
| `rvmodel_macros.h` | how a test ends (HTIF `tohost`), what replaces `FENCE.I`, which address faults |
| `link.ld` | the memory map of `tb_rv32_core_cosim`: 4 MiB of RAM at `0x8000_0000` |
| `run_cmd.txt` | the DUT run command, [`run_act_elf.sh`](../../scripts/sim/verilator/run_act_elf.sh) |

## Why bother, given the cosim flow

The two check different things. The co-simulation (`make sim SW=`) compares every retired instruction against Spike,
which is the stronger check but only over the programs in [`sw/tests`](../../sw/README.md) and the
random ones. The architectural tests are the *coverage*: generated from a test plan, one testcase
per coverpoint bin, including the corners nobody writes by hand.

Running them through this flow gives both at once. An ACT ELF halts through the same HTIF `tohost`
word our own programs use, so the testbench needs no changes, and `run_act_elf.sh --trace` dumps
the retirement trace, which `cmp_trace.py` can then compare against Spike. The signature the
framework checks becomes a second opinion rather than the only verdict.

## Prerequisites

None of these are installed by [`setup.sh`](../../setup.sh), and all of them need network access:

1. **`uv`** — the framework is a `uv` workspace (`make tests`, `make <config>` all go through it).
2. **UDB** (`udb-gen`, Ruby + Bundler) — generates `tests/env/rvtest_config.h` from the UDB
   configuration. Without it the test sources do not even assemble, since every `env/` header is
   driven by that file.
3. **A reference model for signatures** — `sail_riscv_sim` in `test_config.yaml`. Spike alone is
   not enough for the framework, which wants an expected signature per test; without one the ELFs
   are not self-checking ("SIGRUN" in the framework's logs).

## What still has to be written

`rv32-coproc.yaml`, the UDB configuration describing this core: XLEN 32, extensions I and Zicsr
only, M-mode only, no Zifencei, no misaligned access support, `mtval` read-only zero. The closest
template in the submodule is `config/cores/cve2/cv32e20.yaml` (RV32, M-mode).

It is deliberately not copied here: a UDB configuration that disagrees with the hardware produces
tests that quietly check the wrong thing, which the submodule's own guidance warns about ("audit
every field copied from another DUT"). It needs writing against the UDB schema and validating with
`udb-gen`.

## Known limits of this core

Things to configure in the UDB file or exclude with `EXCLUDE_EXTENSIONS`, so the suite tests what
the core claims rather than failing on what it never implemented:

| Core behaviour | Effect on the suite |
|---|---|
| No Zifencei: `FENCE.I` raises an illegal instruction | `RVMODEL_FENCEI nop` here handles it; exclude the `Zifencei` suite |
| `mtval` reads as zero (legal, the spec allows it) | any testcase that checks `mtval` after a trap will fail |
| M-mode only | exclude everything needing S or U mode |
| No CLINT, PLIC, UART or timer in the testbench | exclude the interrupt suites; `RVMODEL_SET_*_INT` is undefined on purpose |
| No `M` extension in hardware | the `M` and `Zmmul` suites do not apply |

## Running it, once the prerequisites are in place

```bash
export PROJ_ROOT=$(git rev-parse --show-toplevel)
export PATH="$PROJ_ROOT/scripts/sim/verilator:$PATH"      # run_cmd.txt calls run_act_elf.sh

cd $PROJ_ROOT/vendor/riscv-arch-test
CONFIG_FILES=$PROJ_ROOT/verif/arch-test/test_config.yaml EXTENSIONS=I make
```

A single ELF, without the framework:

```bash
scripts/sim/verilator/run_act_elf.sh --elf <test>.elf --trace build/arch-test/<test>.trace
python3 scripts/utils/cmp_trace.py build/sw/<test>.spike.log build/arch-test/<test>.trace
```

---
[← Back to verification](../README.md)
