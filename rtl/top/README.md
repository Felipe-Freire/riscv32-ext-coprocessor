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
| `0x2000_0000` | 64 KiB | L2 SRAM, two banks of 32 KiB | Core (AXI4), DMA |
| `0x4000_0000` | 4 KiB | [Timer registers](../periph/README.md#timer) | Core (AXI4-Lite) |
| `0x4000_1000` | 4 KiB | [DMA registers](../dma/README.md#registers) | Core (AXI4-Lite) |
| `0x4000_2000` | 4 KiB | [Coprocessor registers](../coproc/README.md#registers) | Core (AXI4-Lite) |

A fetch outside the Boot ROM and the I-TCM, or a load or store anywhere outside the D-TCM, the L2
and the registers, ends in an access fault. The core cannot load data from the Boot ROM or the
I-TCM, so read-only data is linked into the D-TCM. The interconnect answers the bad data accesses
([`bus_top`](../bus/README.md#core-data-port)):

| Access | Error from | Then |
|---|---|---|
| Core, outside the D-TCM, the L2 and the control window `0x4000_0000`–`0x4FFF_FFFF` | The demux of the core data port | Access fault |
| Core, in the control window outside the three peripherals | The control crossbar (`DECERR`) | Access fault |
| Core, a register the peripheral rejects | The peripheral (`SLVERR`) | Access fault |
| DMA, outside the L2 | The data crossbar (`DECERR`) | The channel stops with `ERR` |

In the RTL the map, the address rules of the crossbars and the bus types are in
[`soc_pkg`](../common/soc_pkg.sv); `tb_soc_pkg` checks them against this table. Change both
together.

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
| Data | Core → D-TCM, data bus, control bus (demux by address) | OBI | 32 |
| Data bus | Core (OBI → AXI4 bridge), DMA → L2 bank 0, L2 bank 1 | AXI4, 2×2 crossbar; IDs of 2 bits at the masters, 3 at the banks | 128 |
| Control bus | Core (OBI → AXI4-Lite bridge) → timer, DMA, coprocessor registers | AXI4-Lite, 1×3 crossbar | 32 |
| A and B streams | DMA → coprocessor | AXI4-Stream (`TVALID`, `TREADY`, `TDATA`) | 64 |
| C stream | Coprocessor → DMA | AXI4-Stream (`TVALID`, `TREADY`, `TDATA`) | 128 |
| Interrupts | Timer, DMA → core | Level, active-high | 1 each |

Port lists: [core](../core/README.md#ports), [DMA](../dma/README.md#ports),
[coprocessor](../coproc/README.md#ports), [timer](../periph/README.md#timer),
[interconnect](../bus/README.md#ports-of-bus_top). The demux, the bridges and both crossbars are
`bus_top`, with its latency and timing in [`rtl/bus`](../bus/README.md#timing). The data bus has a
port per L2 bank because the bank boundary (address bit 15) is a crossbar rule: the DMA reads A and
B from bank 0 while it writes C to bank 1.

## Verification

Until `soc_top` exists, the testbenches in `verif/unit/top/` compile the whole RTL (`rtl/rtl.f`)
and build the part of the SoC they test.

| Testbench | Checks |
|---|---|
| `tb_bus_dma_coproc` | [`bus_top`](../bus/README.md), `dma_top` and `coproc_top` connected as in the SoC, without the core and the memories. An OBI driver on the core data port runs the [matrix multiplication sequence](../../sw/README.md#matrix-multiplication) over the control bus and loads C back over the data bus; the L2 banks are `axi_sim_mem` and `clk_acc_i` is asynchronous. Sizes from one tile to full buffers (8×8×2048, 64×128×128) and random ones, each C checked in the bank and as the core loads it; DMA reads outside the L2 (`ERR`, `irq_o`); at elaboration, the widths of `dma_pkg` and `coproc_pkg` against the buses of `soc_pkg` |

`make sim TB=tb_bus_dma_coproc SEED=random PLUSARGS=+RAND=<n>` adds `n` random sizes (2 by default).

---
[← Back to RTL](../README.md)
