# RTL

Synthesizable SystemVerilog for the RV32 core, the matrix multiplication coprocessor and the
integration top. **Only synthesizable code lives here.** Testbenches, models and assertion bind
files belong in [`verif/`](../verif/README.md).

Architecture and micro-architecture are described in [`docs/spec/`](../docs/README.md#specifications).

## Contents

| Directory | Contents | Module prefix | File list |
|---|---|---|---|
| [`common/`](common/) | Project-wide packages (ISA definitions, opcodes, parameters, types) and reusable primitives (FIFOs, registers, RAM wrappers) | `prim_` (primitives), `<name>_pkg` (packages) | `common/common.f` |
| [`core/`](core/) | RV32 core: fetch, decode, ALU, LSU, register file, CSRs | `core_` | `core/core.f` |
| [`coproc/`](coproc/) | Matrix multiplication coprocessor: control, MAC array, buffers | `coproc_` | `coproc/coproc.f` |
| [`top/`](top/) | Integration of core, coprocessor and memories | `soc_` | `top/top.f` |

[`rtl.f`](rtl.f) is the master file list. It includes the block lists in compile order
(`common` first, because the other blocks import its packages). Paths inside file lists are
written as `${PROJ_ROOT}/rtl/...`.

## Conventions

Based on the [lowRISC SystemVerilog style guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md).

| Item | Convention | Example |
|---|---|---|
| File | One module per file, file name = module name | `core_alu.sv` |
| Module | Prefix from the table above, `lower_snake_case` | `coproc_mac_array` |
| Package / interface | `_pkg` / `_if` suffix | `rv32_pkg`, `coproc_if` |
| Inputs / outputs | `_i` / `_o` suffix | `valid_i`, `ready_o` |
| Active-low | `_n` before the direction suffix | `rst_ni` |
| Registers | `_q` (current state) / `_d` (next state) | `state_q`, `state_d` |
| Parameters | `UpperCamelCase` | `DataWidth`, `NumLanes` |
| Types / enums | `_t` / `_e` suffix | `instr_t`, `alu_op_e` |
| Clock / reset | `clk_i`, asynchronous active-low `rst_ni` | |

Rules:

- Use `always_ff` and `always_comb` only, never `always @(*)`.
- No `initial` blocks, `#` delays, `$display` or classes.
- When you add a file, add it to its block's `.f` file in dependency order (packages first).
- Changing a port list, register map or instruction encoding requires updating `docs/spec/` in the same PR.

## Lint

From the repository root:

```bash
make lint                        # Verilator + Verible (if installed)
make lint RTL_TOP=soc_top        # select the top module explicitly
```

---
[← Back to project root](../README.md)
