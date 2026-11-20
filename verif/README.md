# Verification

Testbenches, reference models and assertions. Nothing here is synthesizable. Strategy and coverage
goals are in the [verification plan](../docs/README.md#verification).

| Directory | Contents |
|---|---|
| [`unit/`](unit/) | Directed, self-checking testbenches: `unit/<block>/tb_<module>.sv` |
| [`uvm/`](uvm/) | UVM agents (`agents/`) and environments (`core/`, `core_pc/` for `rv32_pc`, [`coproc/`](uvm/coproc/README.md), `top/`) |
| [`models/`](models/) | Reference models: the coprocessor golden model in `models/coproc/` |
| [`assertions/`](assertions/) | SVA properties, attached to the RTL through `bind` files; `<block>.f` lists those of a block, compiled through `SIM_FLIST_<block>` |
| [`regress/`](regress/) | Regression lists |

All outputs (logs, waveforms, coverage) go to `build/`, never into this directory.

## Unit testbenches

Keep them few and directed. Test each stage or complex unit once; a small unit that a stage
instantiates is tested through that stage. Each testbench is a single file and reports through the
simulator, so a failure ends with a nonzero exit status:

- a failed check is `$error("...")`, and the testbench goes on;
- a reason to stop (timeout, missing file) is `$fatal(1, "...")`;
- at the end, `$display("PASS: ...")` when every check passed, `$fatal(1, "<summary>")` otherwise.

`$display("FAIL")` and `$finish(1)` both leave the exit status at 0. The `PASS` line is still
required: it proves that the testbench reached its end.

Run one with `make sim TB=tb_rv32_id_stage`; the options and the gate-level run are in
[`scripts/`](../scripts/README.md#simulation).

The testbenches of the interconnect, `unit/bus/`, drive and check it with the verification IP of
`vendor/axi` (random masters and slaves, the crossbar monitor, `axi_sim_mem`), which they get
through `SIM_FLIST_bus`; their list is in [`rtl/bus`](../rtl/bus/README.md#verification).
`unit/top/` holds the integration testbenches: until `soc_top` exists they compile the whole RTL and
build the part of the SoC they test ([`rtl/top`](../rtl/top/README.md#verification)).

## UVM environments

Each `uvm/<block>/` has `tb/`, `env/`, `seq/` and `tests/`. Classes go one per file (`.svh`),
named after the class and included by one package per agent or environment. Tests and the run
command of the coprocessor environment: [`uvm/coproc`](uvm/coproc/README.md).

Run a test with `make sim UVM=core_pc TEST=core_pc_smoke_test SEED=random COV=1`. Each environment
has `<env>.f` and the top `tb_<env>`, and its name starts with its block (`core_pc` → `core`).
UVM ends with exit status 0 even after `UVM_ERROR` or `UVM_FATAL`, so every top has the `final`
block `exit_status` of [`tb_coproc.sv`](uvm/coproc/tb/tb_coproc.sv), which turns them into `$error`.
Regression lists, one `make sim` argument line per run, are in [`regress/`](regress/):
`make regress LIST=verif/regress/nightly.list JOBS=4`.

---
[← Back to project root](../README.md)
