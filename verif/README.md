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
## Comparing the core against Spike

`tb_rv32_core_cosim` runs one program from [`sw/tests/`](../sw/README.md) and writes a line per
retired instruction. Spike runs the same ELF with `--log-commits`, and
[`scripts/utils/cmp_trace.py`](../scripts/utils/cmp_trace.py) compares the two instruction by
instruction, so the first divergence in PC, instruction word or register write is reported with
its context instead of showing up as a wrong result at the end.

```bash
make sim SW=sum                                    # one program: build it, run both, compare
make sim SW=sum SIM=verilator                      # the same on Verilator
make sim SW=random7 RANDOM_COUNT=3000              # a generated program, seed 7
make regress LIST=verif/regress/cosim.list JOBS=8  # every program, with and without wait states
make sim SW=rdv-riscv_rand_instr_test-7            # a riscv-dv program, seed 7 (riscv-dv/)
make regress LIST=verif/regress/riscv_dv.list JOBS=8
```

`SW=` is part of `make sim`, so it works on every simulator and in any regression list. It builds
the program, runs Spike on it, runs `tb_rv32_core_cosim` (or `TB=`) on its image, and
[`check_sim.py`](../scripts/sim/check_sim.py) compares the two traces once the simulation itself
passed. The `[sim]` line says why a run failed: the build, a `CHECK` that failed on Spike (the
program itself is wrong, since Spike is the reference), a `$fatal` of the testbench (timeout,
nonzero exit code, OBI error), or `MISMATCH` with the first divergent instruction and its context
above it in the log.

Both sides see the same 64 KiB memory at `0x8000_0000`, loaded from the same ELF: Spike directly,
the testbench through the `$readmemh` image from
[`elf2hex.py`](../scripts/utils/elf2hex.py). The program ends the run by writing
`(exit code << 1) | 1` to the HTIF `tohost` word, which stops Spike and the testbench at the same
store ([`sw/common/crt0.S`](../sw/common/crt0.S)).

Everything lands in `build/`: `build/sw/<program>.{elf,hex,dis,sym,spike.log}` and
`build/sim/<sim>/cosim_<program>/` with the simulator log and `trace.txt`.

### Memory wait states

By default the data port is granted at once and answers the next cycle.
`COSIM_GNT_WAIT` / `COSIM_RSP_WAIT` / `COSIM_WAIT_SEED` (e.g. `3 3 1`) delay the grant and the response, which
exercises the freeze path of the core: EX waiting for a grant, MEM waiting for a response, the
whole pipeline held. The reference cannot see any of it, so the retirement trace has to come out
identical; only the cycle count changes, which the `PASS` line of the testbench reports. The testbench also
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

Run a test with `make sim UVM=core_pc TEST=core_pc_smoke_test SEED=random COV=1`. Each environment
has `<env>.f` and the top `tb_<env>`, and its name starts with its block (`core_pc` → `core`).
UVM ends with exit status 0 even after `UVM_ERROR` or `UVM_FATAL`, so every top has the `final`
block `exit_status` of [`tb_coproc.sv`](uvm/coproc/tb/tb_coproc.sv), which turns them into `$error`.
Regression lists, one `make sim` argument line per run, are in [`regress/`](regress/):
`make regress LIST=verif/regress/nightly.list JOBS=4`.

---
[← Back to project root](../README.md)
