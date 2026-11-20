# Interconnect

The buses between the core, the DMA, the memories and the peripheral registers. The modules wrap
the crossbars and protocol adapters of [`vendor/axi`](../../vendor/README.md) and take their
configuration, address map and types from [`soc_pkg`](../common/soc_pkg.sv). The SoC view (memory
map, interfaces between blocks) is in [`top/`](../top/README.md).

## Modules

| Module | Function | Vendor IP |
|---|---|---|
| `bus_axi_xbar` | Data bus: AXI4 128-bit crossbar from the masters (core bridge, DMA) to the L2 banks | `axi_xbar` |

## Data bus

| Master | Index | ID bits | Issues |
|---|---|---|---|
| Core, through the OBI → AXI4 bridge | `DATA_MST_CORE` = 0 | 2 (always 0) | Single beats |
| DMA | `DATA_MST_DMA` = 1 | 2 | INCR bursts of up to 16 beats, reads on IDs 0 (A) and 1 (B), writes on ID 0 |

| Slave | Index | Addresses | Holds |
|---|---|---|---|
| L2 bank 0 | `DATA_SLV_L2_BANK0` = 0 | `0x2000_0000`–`0x2000_7FFF` | A and B |
| L2 bank 1 | `DATA_SLV_L2_BANK1` = 1 | `0x2000_8000`–`0x2000_FFFF` | C |

- A transaction goes to the bank of its first address. Bursts never cross 4 KiB and the bank
  boundary is 4 KiB aligned, so a burst stays in one bank.
- AR and AW are routed independently, so a read of one bank and a write of the other move a beat
  each on the same cycle: the DMA reads A and B from bank 0 while it writes C to bank 1. In
  `tb_bus_axi_xbar` a 16-beat read and a 16-beat write take 20 cycles together and 39 in turn.
- Towards a bank the crossbar prepends the master index to the ID (2 → 3 bits) and strips it from
  the B and R beats it returns. Two masters on the same bank are served round robin, per channel.
- An address outside the L2 gets `DECERR` from the crossbar, without reaching a bank. Only the DMA
  can issue one, and its channel stops with `ERR` ([DMA](../dma/README.md#registers)).
- Spill registers on AW and AR on both sides of the crossbar (`DATA_XBAR_LATENCY`). No atomic
  operations.

## Verification

| Testbench | Checks |
|---|---|
| `tb_soc_pkg` | The address maps and configurations of `soc_pkg` against the memory map |
| `tb_bus_axi_xbar` | `bus_axi_xbar` under random traffic from both masters (vendor `axi_rand_master`, `axi_rand_slave` and the upstream crossbar monitor), and directed: data across masters and banks, `DECERR`, read and write on the two banks at the same time |

`make sim TB=tb_bus_axi_xbar SEED=random PLUSARGS=+TXNS=2000` runs more random transactions.

---
[← Back to RTL](../README.md)
