# Scripts

Tool wrappers and helper utilities. Day-to-day use goes through the top-level
[`Makefile`](../Makefile), which calls into this directory.

## Contents

| Path | Contents |
|---|---|
| [`setup.sh`](setup.sh) | Environment setup: `source scripts/setup.sh` exports `PROJ_ROOT` |
| [`sim/xrun/`](sim/xrun/) | Xcelium flow: `sim.mk` (`make sim`, `gls`, `sim-list`, `regress`) and `waves.tcl` |
| [`sim/check_sim.py`](sim/check_sim.py) | PASS/FAIL of one run: exit status and `*E`/`*F` messages (`$error`, `$fatal`, assertions), then the end marker (`PASS` line or UVM summary) |
| [`sim/regress.py`](sim/regress.py) | Runs the lines of a [regression list](../verif/regress/) and prints a PASS/FAIL table |
| [`utils/`](utils/) | Helpers: ELF→hex conversion, generators, log and coverage report parsers |

Synthesis and STA scripts live with their constraints in [`syn/`](../syn/README.md).

## Simulation

```bash
make sim-list                                         # testbenches, UVM tests, regression lists
make sim TB=tb_rv32_core                              # directed: verif/unit/<block>/<TB>.sv
make sim UVM=coproc TEST=coproc_matmul_rand_test SEED=random WAVES=1
make gls TB=tb_rv32_core SDF=1                        # gate level, after make syn BLOCK=core
make regress LIST=verif/regress/smoke.list JOBS=4
```

Each run compiles and simulates in `build/sim/<run>/` (`xrun.log`, `waves.shm`) and ends with a
`[sim] PASS` or `[sim] FAIL` line and the matching exit status. The block of a testbench is its
directory under `verif/unit/`, or the first word of the UVM environment (`core_pc` → `core`); its
RTL file lists come from the block table in the [`Makefile`](../Makefile), vendor IP included. At
gate level the RTL is replaced by the netlist of `make syn`, the block's packages and the cell
models. `make help` lists every variable.

## Conventions

- Scripts must work from any directory: resolve paths from `$PROJ_ROOT`, never from the current directory.
- Scripts write output to `build/` only.
- Start every script with a shebang and a short usage comment.
- Use Python for anything with real logic; keep shell scripts to simple glue.
- Keep everything tool-specific in `sim/<tool>/` so other directories stay simulator-agnostic.

---
[← Back to project root](../README.md)
