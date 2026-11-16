# Scripts

Tool wrappers and helper utilities. Day-to-day use goes through the top-level
[`Makefile`](../Makefile), which calls into this directory.

## Contents

| Path | Contents |
|---|---|
| [`setup.sh`](setup.sh) | Environment setup: `source scripts/setup.sh` exports `PROJ_ROOT` |
| [`sim/`](sim/) | Simulator flows, one subdirectory per tool (`xrun/`, `vsim/`, `vcs/`, `xsim/`, `verilator/`) |
| [`sim/verilator/`](sim/verilator/) | `verilator.mk` (the `cosim` flow), `run_cosim.py` (runs the whole software suite against Spike) and `run_act_elf.sh` (one ELF on the core, for the architectural tests) |
| [`utils/`](utils/) | Helpers: `elf2hex.py` (ELF → `$readmemh` image), `cmp_trace.py` (core trace vs. Spike commit log), `gen_random_test.py` (random RV32I programs) |

Synthesis flow scripts live with their constraints in [`syn/`](../syn/README.md).

## Conventions

- Scripts must work from any directory: resolve paths from `$PROJ_ROOT`, never from the current directory.
- Scripts write output to `build/` only.
- Start every script with a shebang and a short usage comment.
- Use Python for anything with real logic; keep shell scripts to simple glue.
- Keep everything tool-specific in `sim/<tool>/` so other directories stay simulator-agnostic.

---
[← Back to project root](../README.md)
