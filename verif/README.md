# Verification

Everything non-synthesizable: UVM environments, reference models, assertions and regression
lists. The verification strategy and coverage goals are defined in the
[verification plan](../docs/README.md#verification).

## Contents

| Directory | Contents |
|---|---|
| [`uvm/agents/`](uvm/agents/) | Reusable UVCs, one directory per interface (e.g. `coproc_if_agent/`, `mem_agent/`) |
| [`uvm/core/`](uvm/core/) | Block-level environment for the RV32 core |
| [`uvm/coproc/`](uvm/coproc/) | Block-level environment for the matrix multiplication coprocessor |
| [`uvm/top/`](uvm/top/) | System-level environment (core + coprocessor) |
| [`models/`](models/) | Golden reference models (Python/NumPy, C via DPI, ISS integration) |
| [`assertions/`](assertions/) | SVA properties attached to RTL through `bind` files |
| [`regress/`](regress/) | Regression lists: test × seed × configuration |

Each environment under `uvm/<block>/` has the same layout:

| Directory | Contents |
|---|---|
| `tb/` | `tb_<block>.sv` top module: clock/reset, DUT instance, interfaces, `run_test()` |
| `env/` | Environment, configuration, scoreboard, coverage collector, virtual sequencer |
| `seq/` | Sequences and virtual sequences |
| `tests/` | `<block>_base_test` and the tests derived from it |

## Conventions

- One class per file, file name = class name, `.svh` extension.
- Class files are `` `include ``d by a package (`<name>_pkg.sv`): one package per agent, one per environment.
- Interfaces are `.sv` files named `<name>_if.sv`, placed with the agent that drives them.
- Assertions: `<module>_sva.sv` holds the properties, `<module>_bind.sv` binds them to the RTL.

| Component | File name |
|---|---|
| Sequence item | `<agent>_seq_item.svh` |
| Driver / monitor / sequencer | `<agent>_driver.svh`, `<agent>_monitor.svh`, `<agent>_sequencer.svh` |
| Agent / agent config | `<agent>_agent.svh`, `<agent>_agent_cfg.svh` |
| Environment / scoreboard / coverage | `<block>_env.svh`, `<block>_scoreboard.svh`, `<block>_coverage.svh` |
| Tests | `<block>_base_test.svh`, `<block>_<scenario>_test.svh` |

## Running

The simulator flow is not configured yet. Once it is, simulations run from the repository root:

```bash
make sim TEST=coproc_smoke_test SEED=1
make regress LIST=coproc
```

All outputs (logs, waveforms, coverage) go to `build/`, never into this directory.

---
[← Back to project root](../README.md)
