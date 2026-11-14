# UVM environment: coprocessor

DUT: `coproc_top`, with the register port, the stream FIFOs and the clock-domain crossing.

| Part | Contents |
|---|---|
| Agents | [`axil_agent`](../agents/axil_agent/) (AXI4-Lite master, register adapter), [`axis_agent`](../agents/axis_agent/) (A and B masters, C slave with random `TREADY`) |
| Register model | `env/coproc_reg_block.svh`: CTRL, STATUS, DIM_M/N/K |
| Golden model | [`verif/models/coproc`](../../models/coproc/coproc_model.h), C++ through DPI-C. Untimed model of the block: registers, A and B in, C out, and the L2 layouts |
| Scoreboard | Feeds the model with what the monitors saw and checks every C word, register response and read value. Allows for the clock-domain crossing at the end of a job (see the header of `env/coproc_scoreboard.svh`) |
| Coverage | `cg_cop_cfg` and `cg_cop_flow` of the verification plan |

Protocol assertions (valid held until ready with a stable payload) live in the agent interfaces.

## Tests

| Test | Plan | What it does |
|---|---|---|
| `coproc_regs_test` | T13: COP-01, COP-02 | Reset values, DIM_* with partial WSTRB, SLVERR outside the map, accesses while BUSY, DONE W1C and cleared by START |
| `coproc_matmul_directed_test` | T14: COP-03 to COP-05 | Chosen shapes and values, 64x64x64, extremes; `+BIG_K` adds K = 65535 |
| `coproc_matmul_rand_test` | T15: COP-03, COP-06, COP-07 | `+JOBS=<n>` random jobs (default 40) with gaps in A and B and back-pressure on C |
| `coproc_cdc_test` | T16: COP-08 | Random jobs with `clk_acc_i` from 4x faster to 4x slower than `clk_i` |
| `coproc_reset_test` | T17: COP-09 | Jobs cut by a reset at a random point, each followed by a clean job |

Not covered yet: COP-10 (dimensions outside the spec, waiting for point P1; the model follows the
current RTL) and COP-11 (cycles per tile).

## Run

```bash
export PROJ_ROOT=$(git rev-parse --show-toplevel)
mkdir -p $PROJ_ROOT/build/xrun/coproc && cd $PROJ_ROOT/build/xrun/coproc
xrun -uvm -uvmhome CDNS-1.2 -sv -64bit -timescale 1ns/1ps -coverage functional \
  -f $PROJ_ROOT/vendor/common_cells.f -f $PROJ_ROOT/rtl/coproc/coproc.f \
  -f $PROJ_ROOT/verif/uvm/coproc/coproc.f \
  -top tb_coproc +UVM_TESTNAME=coproc_matmul_rand_test -svseed random
```

`coproc.f` lists the golden model source (`coproc_model.cc`); xrun compiles it with g++. The
model also has its own test: `verif/models/coproc/coproc_model_test.cc`.

---
[← Back to verification](../../README.md)
