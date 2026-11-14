# Verification

Testbenches, reference models and assertions. Nothing here is synthesizable. Strategy and coverage
goals are in the [verification plan](../docs/README.md#verification).

| Directory | Contents |
|---|---|
| [`unit/`](unit/) | Directed, self-checking testbenches: `unit/<block>/tb_<module>.sv` |
| [`uvm/`](uvm/) | UVM agents (`agents/`) and environments (`core/`, `core_pc/` for `rv32_pc`, [`coproc/`](uvm/coproc/README.md), `top/`) |
| [`models/`](models/) | Reference models: the coprocessor golden model in `models/coproc/` |
| [`assertions/`](assertions/) | SVA properties, attached to the RTL through `bind` files |
| [`regress/`](regress/) | Regression lists |

All outputs (logs, waveforms, coverage) go to `build/`, never into this directory.

## Unit testbenches

Keep them few and directed. Test each stage or complex unit once; a small unit that a stage
instantiates is tested through that stage. Each testbench is a single file and prints a final line
starting with `PASS` or `FAIL`.

Run one with Xcelium from a directory under `build/`:

```bash
export PROJ_ROOT=$(git rev-parse --show-toplevel)
mkdir -p $PROJ_ROOT/build/xrun && cd $PROJ_ROOT/build/xrun
xrun -sv -timescale 1ns/1ps -f $PROJ_ROOT/rtl/core/core.f \
  $PROJ_ROOT/verif/unit/core/tb_rv32_id_stage.sv -top tb_rv32_id_stage
```

## UVM environments

Each `uvm/<block>/` has `tb/`, `env/`, `seq/` and `tests/`. Classes go one per file (`.svh`),
named after the class and included by one package per agent or environment. Tests and the run
command of the coprocessor environment: [`uvm/coproc`](uvm/coproc/README.md).

```bash
export PROJ_ROOT=$(git rev-parse --show-toplevel)
mkdir -p $PROJ_ROOT/build/xrun/core_pc && cd $PROJ_ROOT/build/xrun/core_pc
xrun -uvm -uvmhome CDNS-1.2 -sv -64bit -timescale 1ns/1ps -coverage functional \
  -f $PROJ_ROOT/rtl/core/core.f -f $PROJ_ROOT/verif/uvm/core_pc/core_pc.f \
  -top tb_core_pc +UVM_TESTNAME=core_pc_smoke_test -svseed random
```

---
[← Back to project root](../README.md)
