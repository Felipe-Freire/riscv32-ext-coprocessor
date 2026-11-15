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

Run one with `make sim TB=tb_rv32_id_stage`; the options and the gate-level run are in
[`scripts/`](../scripts/README.md#simulation).

## UVM environments

Each `uvm/<block>/` has `tb/`, `env/`, `seq/` and `tests/`. Classes go one per file (`.svh`),
named after the class and included by one package per agent or environment. Tests and the run
command of the coprocessor environment: [`uvm/coproc`](uvm/coproc/README.md).

Run a test with `make sim UVM=core_pc TEST=core_pc_smoke_test SEED=random COV=1`. Each environment
has `<env>.f` and the top `tb_<env>`, and its name starts with its block (`core_pc` → `core`).
Regression lists, one `make sim` argument line per run, are in [`regress/`](regress/):
`make regress LIST=verif/regress/nightly.list JOBS=4`.

---
[← Back to project root](../README.md)
