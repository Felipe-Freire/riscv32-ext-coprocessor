# RV32 core

In-order, single-issue, 5-stage pipeline (fetch, decode, execute, memory, write-back), machine mode
only. Datapath: [`core-datapath.svg`](../../docs/figures/core-datapath.svg).

## Source layout

| Path | Contents |
|---|---|
| `rv32_core.sv` | Top: connects the stages and builds the freeze |
| `rv32_pkg.sv` | ISA encodings and the control types shared by the units |
| `units/` | One module per unit: PC, decoder, immediate generator, register file, branch prediction, hazard and forwarding, ALU, branch condition, redirect logic, store and load alignment, CSRs and trap control |
| `stage/` | One module per pipeline stage, including the pipeline register it feeds: `rv32_if_stage.sv`, `rv32_id_stage.sv`, `rv32_ex_stage.sv`, `rv32_mem_stage.sv` |

In the datapath, `rv32_pc` holds the PC and +4 blocks, `rv32_branch_pred` the target adder, Static
BTFN and `alt_pc` blocks, and `rv32_csr` the CSR file and trap control. WB has no module: MEM writes
the MEM/WB register and the register file write port is in ID.

## Stage interfaces

| Signals | Naming | Example (`rv32_if_stage`) |
|---|---|---|
| Pipeline register | `<reg>_<field>`: output of the stage that writes the register, input of the next | `ifid_pc_o` → `ifid_pc_i` |
| Memory and bus ports | Same names as the core ports | `instr_req_o`, `instr_rdata_i` |
| Redirects | `<stage>_redirect_i` and `<stage>_target_i`, named after the stage that resolves them | `ex_redirect_i`, `trap_i` |
| Hazard control | Named after its effect on the receiving stage | `stall_i` |

Each stage writes the pipeline register it feeds (IF writes IF/ID). From ID/EX on, a register has
too many fields for separate ports, so it is `<reg>_valid` plus a packed struct (`idex_valid_o`,
`idex_o` of type `idex_t`). A flush clears only `<reg>_valid`, so every side effect downstream is
qualified with it. PCs and targets are `[XLEN-1:2]`. Ports go in this order: clock and reset, memory
or bus, control from later stages, outputs to the next stage.

## Instructions

`RV32I` + `Zicsr`. GCC flags: `-march=rv32i_zicsr -mabi=ilp32`.

| Group | Instructions |
|---|---|
| Arithmetic and logic | `ADD SUB AND OR XOR SLL SRL SRA SLT SLTU`, `ADDI ANDI ORI XORI SLLI SRLI SRAI SLTI SLTIU`, `LUI AUIPC` |
| Jumps and branches | `JAL JALR`, `BEQ BNE BLT BGE BLTU BGEU` |
| Loads and stores | `LB LH LW LBU LHU`, `SB SH SW` |
| CSR access | `CSRRW CSRRS CSRRC CSRRWI CSRRSI CSRRCI` |
| System | `ECALL EBREAK MRET`; `FENCE` and `WFI` execute as no-ops |

Anything else raises an illegal-instruction exception (`M`, `A`, `C`, `F`, `FENCE.I`, user and
supervisor modes). There is no multiply instruction: the compiler calls `__mulsi3` from libgcc for
scalar multiplications, and matrix multiplications go to the coprocessor
([software sequence](../../sw/README.md#matrix-multiplication)).

## CSRs

| Address | Name | Implemented fields |
|---|---|---|
| `0x300` | `mstatus` | `MIE` (3), `MPIE` (7); `MPP` (12:11) reads `11` |
| `0x301` | `misa` | `0x4000_0100` (RV32I); writes ignored |
| `0x304` | `mie` | `MTIE` (7), `MEIE` (11) |
| `0x305` | `mtvec` | `BASE` (31:2); `MODE` reads 0 (direct) |
| `0x340` | `mscratch` | 31:0 |
| `0x341` | `mepc` | 31:2; bits 1:0 read 0 |
| `0x342` | `mcause` | `Interrupt` (31), exception code (3:0) |
| `0x343` | `mtval` | Reads 0; writes ignored |
| `0x344` | `mip` | `MTIP` (7), `MEIP` (11); writes ignored |
| `0xB00` / `0xB80` | `mcycle` / `mcycleh` | 64-bit cycle counter |
| `0xB02` / `0xB82` | `minstret` / `minstreth` | 64-bit retired-instruction counter |
| `0xF11`–`0xF14` | `mvendorid` `marchid` `mimpid` `mhartid` | Read-only 0 |

Unlisted fields read 0. Accessing any other CSR, or writing one in the read-only range
`0xC00`–`0xFFF`, raises an illegal-instruction exception.

## Traps

| `mcause` | Cause |
|---|---|
| `0x8000_000B` | External interrupt (DMA) |
| `0x8000_0007` | Timer interrupt |
| 0 | Jump or taken branch to an address that is not 4-byte aligned |
| 1 | Instruction access fault: fetch outside the Boot ROM and I-TCM |
| 2 | Illegal instruction |
| 3 | `EBREAK` |
| 4 / 6 | Misaligned load / store (no hardware support for misaligned accesses) |
| 5 / 7 | Load / store access fault: unmapped address or bus error |
| 11 | `ECALL` |

Traps are taken in MEM, the commit point. An interrupt is taken when `mstatus.MIE` and its `mie`
bit are set; external has priority over timer, and an exception of the instruction in MEM has
priority over both. The interrupt replaces the instruction in MEM, unless it is a load or store
whose request already left: that one completes and the interrupt waits for the next. On a trap the
core writes `mepc` (the trapping instruction, or the next one not executed for an interrupt) and
`mcause`, copies `MIE` to `MPIE`, clears `MIE` and jumps to `mtvec`. `MRET` copies `MPIE` back to
`MIE`, sets `MPIE` and jumps to `mepc`.

## Ports

| Port | Dir | Bits | Description |
|---|---|---|---|
| `clk_i`, `rst_ni` | in | 1 | Clock, asynchronous active-low reset |
| `instr_req_o` | out | 1 | Fetch; low while the pipeline is stalled |
| `instr_addr_o` | out | 32 | Fetch address (bits 1:0 are 0) |
| `instr_rdata_i` | in | 32 | Instruction, one cycle after the request; held while `instr_req_o` is low |
| `instr_err_i` | in | 1 | Fetch outside the Boot ROM and I-TCM; timed and held like `instr_rdata_i` |
| `data_req_o`, `data_gnt_i` | out, in | 1 | OBI request and grant |
| `data_addr_o` | out | 32 | Byte address |
| `data_we_o`, `data_be_o` | out | 1, 4 | Write enable, byte enables |
| `data_wdata_o` | out | 32 | Store data |
| `data_rvalid_i`, `data_rdata_i` | in | 1, 32 | Response (loads and stores), load data |
| `data_err_i` | in | 1 | Access fault, valid with `data_rvalid_i` |
| `irq_timer_i`, `irq_external_i` | in | 1 | `MTIP`, `MEIP` |

The reset PC is the parameter `BootAddr` (default `0x0000_0000`). Loads and stores send their
request in EX, with the address straight from the ALU adder, and take the response in MEM; at most
one access is outstanding. The D-TCM grants at once and answers in the next cycle, so it never
stalls. A later grant or response freezes the whole pipeline.

---
[← Back to RTL](../README.md)
