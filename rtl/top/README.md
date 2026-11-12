# SoC top

`soc_top` connects the core, the memories, the DMA, the coprocessor and the timer. Diagrams:
[top level](../../docs/figures/soc-top-level.svg) and
[architecture detail](../../docs/figures/soc-architecture.svg).

## Clocks and resets

| Domain | Clock | Reset | Blocks |
|---|---|---|---|
| System | `clk_i` | `rst_ni` | Core, memories, buses, DMA, timer |
| Accelerator | `clk_acc_i` | `rst_acc_ni` | Systolic array and its registers |

Both resets are asynchronous and active-low; `soc_top` synchronizes their release in each domain.
The only clock-domain crossings are inside the coprocessor block.

## Memory map

| Base | Size | Region | Reached by |
|---|---|---|---|
| `0x0000_0000` | 4 KiB | Boot ROM (reset vector) | Core instruction fetch |
| `0x1000_0000` | 32 KiB | I-TCM | Core instruction fetch |
| `0x1001_0000` | 32 KiB | D-TCM | Core loads and stores |
| `0x2000_0000` | 64 KiB | L2 SRAM | Core (AXI4), DMA |
| `0x4000_0000` | 4 KiB | [Timer registers](../periph/README.md#timer) | Core (AXI4-Lite) |
| `0x4000_1000` | 4 KiB | [DMA registers](../dma/README.md#registers) | Core (AXI4-Lite) |
| `0x4000_2000` | 4 KiB | [Coprocessor registers](../coproc/README.md#registers) | Core (AXI4-Lite) |

Any other address returns an access fault. The core cannot load data from the Boot ROM or the
I-TCM, so read-only data is linked into the D-TCM.

### Matrix buffers in L2

The L2 has two 32 KiB banks selected by address bit 15, so the DMA can read A and B while it
writes C. Software places the matrices in these buffers (layout inside each buffer:
[coprocessor](../coproc/README.md#matrix-layout)):

| Base | Size | Bank | Contents |
|---|---|---|---|
| `0x2000_0000` | 16 KiB | 0 | A (M×K, int8) |
| `0x2000_4000` | 16 KiB | 0 | B (K×N, int8) |
| `0x2000_8000` | 32 KiB | 1 | C (M×N, int32) |

## Interrupts

There is no interrupt controller: each source drives one core input.

| Core input | `mip` bit | Source |
|---|---|---|
| `irq_timer_i` | `MTIP` (7) | Timer: `mtime ≥ mtimecmp` |
| `irq_external_i` | `MEIP` (11) | DMA: a channel with `IRQ_EN` set has finished or failed |

## Interfaces between blocks

| Interface | From → to | Protocol | Data bits |
|---|---|---|---|
| Instruction fetch | Core → Boot ROM, I-TCM | OBI subset: always granted, data one cycle later, held while the request is low | 32 |
| Data | Core → D-TCM, bus bridges | OBI | 32 |
| Data bus | Core (OBI → AXI4 bridge), DMA → L2 | AXI4 | 128 |
| Control bus | Core (OBI → AXI4-Lite bridge) → timer, DMA, coprocessor registers | AXI4-Lite | 32 |
| A and B streams | DMA → coprocessor | AXI4-Stream (`TVALID`, `TREADY`, `TDATA`) | 64 |
| C stream | Coprocessor → DMA | AXI4-Stream (`TVALID`, `TREADY`, `TDATA`) | 128 |
| Interrupts | Timer, DMA → core | Level, active-high | 1 each |

Port lists: [core](../core/README.md#ports), [DMA](../dma/README.md#ports),
[coprocessor](../coproc/README.md#ports), [timer](../periph/README.md#timer).

---
[← Back to RTL](../README.md)
