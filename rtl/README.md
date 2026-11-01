# RTL

Synthesizable SystemVerilog for the ASIC: the RV32 core, the matrix multiplication coprocessor,
the DMA, the interconnect and the SoC top. **Only synthesizable code lives here.** Testbenches,
models and assertion bind files belong in [`verif/`](../verif/README.md). Third-party IP lives
unmodified in [`vendor/`](../vendor/README.md).

The specification lives with the RTL: each block README below describes its function, registers
and ports, and [`top/`](top/README.md) holds the memory map and the interfaces between blocks.

## Contents

| Directory | Contents | Module prefix | Specification |
|---|---|---|---|
| [`common/`](common/) | Project-wide packages: memory map, shared types | `<name>_pkg` | — |
| [`prim/`](prim/) | Technology primitives (SRAM and ROM macros, clock gating, synchronizers, async FIFOs) | `prim_` | — |
| [`core/`](core/README.md) | RV32 core: fetch, decode, ALU, LSU, register file, CSRs | `core_` | Instructions, CSRs, traps, ports |
| [`coproc/`](coproc/README.md) | Systolic-array coprocessor: PE array, skew and drain, tile sequencer, registers, CDC | `coproc_` | Operation, matrix layout, registers, ports |
| [`dma/`](dma/README.md) | DMA: registers, 3D address generators, AXI4 burst engine, stream ports | `dma_` | Channels, registers, ports |
| [`bus/`](bus/) | Interconnect: OBI→AXI4 and OBI→AXI4-Lite bridges, AXI4 interconnect, AXI4-Lite address decoder | `bus_` | In [`top/`](top/README.md#interfaces-between-blocks) |
| [`mem/`](mem/) | Memories built from `prim_` macros: TCMs, L2 banks, boot ROM | `mem_` | In [`top/`](top/README.md#memory-map) |
| [`periph/`](periph/README.md) | Timer | `periph_` | Registers |
| [`top/`](top/README.md) | SoC top: block integration, reset synchronizers | `soc_` | Memory map, interrupts, clocks, interfaces |

Each directory has a file list `<dir>/<dir>.f`. [`rtl.f`](rtl.f) is the master file list: it
includes the block lists in compile order (`common` and `prim` first, because the other blocks
use them). Paths inside file lists are written as `${PROJ_ROOT}/rtl/...`.

## Technology independence

The target is an ASIC and the PDK is not chosen yet, so `rtl/` stays technology-independent:

- Anything that maps to a specific cell or macro (SRAM, ROM, clock-gating cell, clock mux,
  synchronizer, pad) is instantiated only through a `prim_` module. `prim/` holds a generic
  behavioral version of each one, used for simulation. The technology version keeps the
  same module name and ports, and replaces it through the synthesis file list (see
  [`syn/`](../syn/README.md)).
- SRAMs and ROMs are never inferred from arrays: instantiate the `prim_` macro wrapper. Small
  storage built from flip-flops (register file, FIFOs) is written as plain arrays.
- No FPGA primitives, vendor attributes or memory-initialization idioms.

## Conventions

Based on the [lowRISC SystemVerilog style guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md).

| Item | Convention | Example |
|---|---|---|
| File | One module or package per file, file name = module name | `core_alu.sv` |
| Modules, packages, signals, instances | `lower_snake_case`, module prefix from the table above | `coproc_pe_array` |
| Packages | `_pkg` suffix | `core_pkg` |
| Inputs / outputs / bidirectionals | `_i` / `_o` / `_io` suffix | `valid_i`, `ready_o` |
| Active-low | `_n`, joined with the direction suffix | `rst_ni` |
| Registers | `_d` (next state) / `_q` (current state); `_q2`, `_q3` for extra pipeline delays | `state_q` |
| Tunable parameters | `UpperCamelCase` | `NumBanks` |
| Constants (`localparam`) | `ALL_CAPS` or `UpperCamelCase` | `XLEN`, `ResetAddr` |
| Enum types / other typedefs | `_e` / `_t` suffix | `alu_op_e`, `obi_req_t` |
| Enum values | `UpperCamelCase` | `AluAdd`, `StIdle` |
| Macros | `ALL_CAPS` | `` `ASSERT_KNOWN `` |
| Clocks | `clk_i` for the module's main clock, `clk_<domain>_i` for others | `clk_acc_i` |
| Resets | Asynchronous, active-low: `rst_ni`, `rst_<domain>_ni` for other domains | `rst_acc_ni` |

Rules:

- Use `always_ff` and `always_comb`, never `always @(*)`. Latches only inside `prim_` cells.
- No `initial` blocks, `#` delays, `$display`, classes or interfaces. Group related signals in
  packed structs (`_t`) instead of interfaces.
- Reset control state (valid bits, FSM states, counters, CSRs). Datapath registers have no reset:
  the flops are smaller and the reset tree is lighter.
- Write enables as `if (en) q <= d;` and let synthesis insert clock gating. Never gate or generate
  a clock in logic outside `prim_`.
- Signals cross clock domains only through `prim_` synchronizers or vendor CDC IP.
- When you add a file, add it to its block's `.f` file in dependency order (packages first).
- Changing a port list, the memory map or a register map requires updating the block README in the same PR.

---
[← Back to project root](../README.md)
