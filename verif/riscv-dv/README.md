# riscv-dv

Target for [riscv-dv](https://github.com/chipsalliance/riscv-dv) ([`vendor/riscv-dv`](../../vendor/riscv-dv)),
the random instruction generator, on `rv32_core`. Its programs go through the same co-simulation as
the hand-written ones: Spike runs the ELF, `tb_rv32_core_cosim` runs its image, and the two
retirement traces are compared instruction by instruction ([verif/README.md](../README.md#comparing-the-core-against-spike)).

| File | Role |
|---|---|
| `riscv_core_setting.sv` | what the core implements: RV32I + Zicsr, M mode only, its CSRs and exceptions |
| `testlist.yaml` | riscv-dv's base tests plus the misaligned-JALR test |

```bash
make sim SW=rdv-riscv_rand_instr_test-7                         # one program: test, seed 7
make sim SW=rdv-riscv_rand_instr_test-7 SIM=verilator           # the core on Verilator
make sim SW=rdv-riscv_loop_test-3 RDV_OPTS=+instr_cnt=2000      # extra generator plusargs
make regress LIST=verif/regress/riscv_dv.list JOBS=8            # every test that applies, 3 seeds
make sim-list                                                   # the test names
```

`SW=rdv-<test>-<seed>` is a program like any other in [`sw/sw.mk`](../../sw/sw.mk): the generator
writes `build/sw/<SW>/<SW>.S` with [`rdv_gen.py`](../../scripts/utils/rdv_gen.py), and it is linked
with riscv-dv's `scripts/link.ld` instead of `sw/common/crt0.S`, since it brings its own startup,
trap handler and HTIF exit (`ecall` to the handler, which writes `tohost`). The same name always
gives the same program, so a failing line of a regression reproduces with `make sim SW=<that name>`.

The generator is the SystemVerilog version, so it needs Xcelium even when the core runs on
Verilator. It is compiled once into `build/riscv-dv/gen` (about 15 s), again when
`riscv_core_setting.sv` changes, and each program then takes a few seconds. Its Python (PyYAML)
is in `build/venv`, made by [`setup.sh`](../../setup.sh).

## What the target leaves out, and why

| Setting | Reason |
|---|---|
| `supported_interrupt_mode = {DIRECT}` | `mtvec` has no MODE field: every trap goes to its base |
| no `MCOUNTEREN`, M mode only | the core has no U or S mode |
| `support_unaligned_load_store = 0` | misaligned loads and stores trap (causes 4 and 6) |
| `unsupported_instr = {FENCE_I, WFI}` | cannot be co-simulated against standalone Spike ([sw/README.md](../../sw/README.md#tests)) |

Tests not in [`riscv_dv.list`](../regress/riscv_dv.list): the interrupt test (no interrupt sources
in the testbench), the debug-mode test, the unaligned load/store test, and `riscv_csr_test`, which
needs a CSR description file.

---
[← Back to verification](../README.md)
