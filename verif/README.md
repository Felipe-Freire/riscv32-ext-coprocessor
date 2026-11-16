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

## Comparing the core against Spike

`tb_rv32_core_cosim` runs one program from [`sw/tests/`](../sw/README.md) and writes a line per
retired instruction. Spike runs the same ELF with `--log-commits`, and
[`scripts/utils/cmp_trace.py`](../scripts/utils/cmp_trace.py) compares the two instruction by
instruction, so the first divergence in PC, instruction word or register write is reported with
its context instead of showing up as a wrong result at the end.

```bash
make cosim TEST=sum          # one program: build it, run both, compare
make cosim-all               # every program under sw/tests, as a table

scripts/sim/verilator/run_cosim.py            # what cosim-all calls, with options
scripts/sim/verilator/run_cosim.py sort 'm*'  # a selection, by name or glob
scripts/sim/verilator/run_cosim.py -j 4 -x    # four at a time, stop at the first failure
scripts/sim/verilator/run_cosim.py --wait     # with memory wait states
scripts/sim/verilator/run_cosim.py --random 20 --random-count 3000   # generated programs
scripts/sim/verilator/run_cosim.py --list     # the available tests
```

[`run_cosim.py`](../scripts/sim/verilator/run_cosim.py) runs `make cosim` per test, in parallel,
and prints retired instructions, cycles and IPC per test with the failures collected at the end.
A failure is one of four kinds: `BUILD` (the program did not compile or link), `FAIL` (a `CHECK`
in the program failed, or the testbench timed out), `MISMATCH` (the core and Spike diverged, with
the instruction and its context) and otherwise `PASS`. A `FAIL` reported by Spike means the
program itself is wrong, since Spike is the reference.

Both sides see the same 64 KiB memory at `0x8000_0000`, loaded from the same ELF: Spike directly,
the testbench through the `$readmemh` image from
[`elf2hex.py`](../scripts/utils/elf2hex.py). The program ends the run by writing
`(exit code << 1) | 1` to the HTIF `tohost` word, which stops Spike and the testbench at the same
store ([`sw/common/crt0.S`](../sw/common/crt0.S)).

Everything lands in `build/`: `build/sw/<test>.{elf,hex,dis,sym,spike.log}` and
`build/verilator/tb_rv32_core_cosim/<test>.{trace,log}`.

### Memory wait states

By default the data port is granted at once and answers the next cycle. `--wait`, or
`COSIM_GNT_WAIT` / `COSIM_RSP_WAIT` / `COSIM_WAIT_SEED`, delays the grant and the response, which
exercises the freeze path of the core: EX waiting for a grant, MEM waiting for a response, the
whole pipeline held. The reference cannot see any of it, so the retirement trace has to come out
identical; only the cycle count changes, which is why the report prints IPC. The testbench also
checks the OBI rule that a request stays unchanged until it is granted.

### What is compared, and what cannot be

The retirement stream: PC, instruction word and register write. Not the CSR *state*, not store
data; that needs the RVFI lock-step co-simulation in [`models/riscv/`](models/riscv/README.md).

Three exceptions, all of them genuine differences rather than bugs:

* **Counter CSRs and `mtval`.** A read of `mcycle`, `minstret` or their high halves must differ
  between a pipeline and the reference, and this core reads `mtval` as zero, which the privileged
  spec allows. For those, `cmp_trace.py` compares the PC, the instruction and the destination
  register but not the value, and says how many it skipped. `--volatile-csr` adds more.
* **Traps.** No change was needed: Spike's commit log has no record for an instruction that traps,
  and the core's trapping instruction never reaches WB, so the two streams stay aligned by
  themselves. `sw/tests/trap` checks all nine causes this way.
* **`WFI` and `FENCE.I`.** Cannot be co-simulated at all; see [sw/README.md](../sw/README.md#tests).

Spike runs with `--priv=m`, like the core. Without it, it implements S and U as well and reports
them in `misa` (`0x40140100` instead of `0x40000100`).

### Architectural tests

[`arch-test/`](arch-test/README.md) holds the target configuration for the official RISC-V
architectural test suite in `vendor/riscv-arch-test`. Prepared, not yet run: the framework needs
`uv`, UDB and a Sail reference model, none of which are installed here.

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
