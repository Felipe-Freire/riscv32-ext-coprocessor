# Scripts

Tool wrappers and helper utilities. Day-to-day use goes through the top-level
[`Makefile`](../Makefile), which calls into this directory.

## Contents

| Path | Contents |
|---|---|
| [`setup.sh`](setup.sh) | Environment setup: `source scripts/setup.sh` exports `PROJ_ROOT`, activates `.venv` and appends the EDA tools of `.venv/eda` to `PATH` |
| [`venv.mk`](venv.mk) | `make venv`: the environment of the project in `.venv` (git-ignored): the Python packages of [`requirements.txt`](../requirements.txt), and in `.venv/eda` the conda tools of [`eda-tools.yml`](../eda-tools.yml) (ngspice, KLayout), installed by a micromamba of fixed version and checksum |
| [`sim/xrun/`](sim/xrun/) | Xcelium flow: `sim.mk` (`make sim`, `gls`, `sim-list`, `regress`) and `waves.tcl` |
| [`sim/verilator/`](sim/verilator/) | Verilator (`SIM=verilator`, directed testbenches only): `sim.mk`, and `run_act_elf.sh` for the [architectural tests](../verif/arch-test/README.md) |
| [`sim/check_sim.py`](sim/check_sim.py) | PASS/FAIL of one run: exit status and `*E`/`*F` messages (`$error`, `$fatal`, assertions), then the end marker (`PASS` line or UVM summary) |
| [`sim/regress.py`](sim/regress.py) | Runs the lines of a [regression list](../verif/regress/) and prints a PASS/FAIL table |
| [`utils/openram_macro.py`](utils/openram_macro.py) | `make openram` and `make openram-char`: OpenRAM runs of an SRAM macro, one per corner and in parallel, then the checks of its views (DRC, LVS, `VERBOSE = 0`, equal areas) and their copy to `syn/tech/openram45/views/`, the one in git |
| [`utils/`](utils/) | Helpers: ELF→hex conversion, generators, log and coverage report parsers |

Synthesis and STA scripts live with their constraints in [`syn/`](../syn/README.md).

Every Python tool of the flows runs on the interpreter of `.venv` once `make venv` has built it, and
on the `python3` of `PATH` before that. The simulation scripts need only the standard library, so
they run either way; the tools of the venv (OpenRAM, ngspice and KLayout, for `make openram`) need
it, and their targets build it first. Edit `requirements.txt` (pip) or `eda-tools.yml` (conda) to
add a package: the next run rebuilds that part. Nothing is installed outside `.venv`, and nothing
needs root.

## Simulation

```bash
make sim-list                                         # testbenches, UVM tests, regression lists
make sim TB=tb_rv32_core                              # directed: verif/unit/<block>/<TB>.sv
make sim UVM=coproc TEST=coproc_matmul_rand_test SEED=random WAVES=1
make sim TB=tb_mem_l2_bank MEM_TECH=openram45         # on the OpenRAM macro models
make sim SW=sort                                      # program on the core and on Spike, compared
make gls TB=tb_rv32_core SDF=1                        # gate level, after make syn BLOCK=core
make regress LIST=verif/regress/smoke.list JOBS=4
make regress LIST=verif/regress/cosim.list JOBS=8     # every program against Spike
make sim TB=tb_rv32_alu SIM=verilator                 # any of the above on Verilator, directed only
```

`SIM` picks the simulator (`xrun` by default); the variables and the result are the same for all,
and `make regress SIM=verilator` passes it on to every run. Each run compiles and simulates in
`build/sim/<sim>/<run>/` (`xrun.log` or `sim.log`, `waves.shm`) and ends with a `[sim] PASS` or
`[sim] FAIL` line and the matching exit status. Verilator builds the model of a testbench once, in
`build/verilator/<TB>/`, and supports neither UVM, gate level, coverage, waves nor the GUI. The block of a testbench is its
directory under `verif/unit/`, or the first word of the UVM environment (`core_pc` → `core`); its
RTL file lists come from the block table in the [`Makefile`](../Makefile), vendor IP included.
The memory primitives are the generic models unless `MEM_TECH=openram45` asks for the OpenRAM
macros, whose Verilog models then come in as a library (`-v`); a run with `MEM_TECH` set gets its
own directory, `build/sim/<run>_<mem_tech>/` ([`rtl/prim`](../rtl/prim/README.md#memory-technology-mem_tech)). At
gate level the RTL is replaced by the netlist of `make syn`, the block's packages and interfaces
(`*_pkg.sv`, `*_intf.sv`) and the models of the cells of the technology (`TECH`) and of the memory
macros of the synthesis, the cells compiled with their
`CELL_MODEL_DEFINES` (`TETRAMAX` for the NanGate cells of FreePDK45: without it their models drive
the reset pin of the flops back and hold it at X; see [`syn/tech/tech.mk`](../syn/tech/tech.mk)).
With `SDF=1`, synthesize at `CORNER=slow`: no hold is fixed before place and route, and at
`typical` a flop that drives another one directly (synchronizer stages, reset release) breaks its
hold or removal time ([`gls.list`](../verif/regress/gls.list)). A block can also have testbench-only file lists,
`SIM_FLIST_<block>` in the same table (verification IP such as `vendor/axi_sim.f`, or the RTL of
another block a testbench runs against). They are compiled after the design and before the
testbench, at RTL and gate level, and synthesis never reads them. `make help` lists every variable.

## Conventions

- Scripts must work from any directory: resolve paths from `$PROJ_ROOT`, never from the current directory.
- Scripts write output to `build/` only.
- Start every script with a shebang and a short usage comment.
- Use Python for anything with real logic; keep shell scripts to simple glue.
- Keep everything tool-specific in `sim/<tool>/` so other directories stay simulator-agnostic. A new
  simulator is a `sim/<tool>/sim.mk` that defines `sim` with the helpers of `sim/sim.mk`.

---
[← Back to project root](../README.md)
