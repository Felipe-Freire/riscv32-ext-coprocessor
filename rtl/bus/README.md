# Interconnect

The buses between the core, the DMA, the memories and the peripheral registers. The modules wrap
the crossbars and protocol adapters of [`vendor/axi`](../../vendor/README.md) and take their
configuration, address map and types from [`soc_pkg`](../common/soc_pkg.sv). The SoC view (memory
map, interfaces between blocks) is in [`top/`](../top/README.md).

## Modules

| Module | Function | Vendor IP |
|---|---|---|
| `bus_top` | The interconnect: the modules below, the OBI → AXI4-Lite bridge and the control crossbar | `axi_lite_from_mem`, `axi_lite_xbar` |
| `bus_obi_demux` | Core data port: each access to its target by address, the response back, err for unmapped addresses | `addr_decode` (common_cells) |
| `bus_axi_xbar` | Data bus: AXI4 128-bit crossbar from the masters (core bridge, DMA) to the L2 banks | `axi_xbar` |
| `bus_obi2axi` | Core bridge: one access of the core data port (OBI) becomes one AXI4 single-beat transaction on the data bus | `axi_from_mem` |

## Ports of `bus_top`

```
 core data port (OBI) -> bus_obi_demux -+-> D-TCM (OBI)
                                        +-> bus_obi2axi -------> bus_axi_xbar -> L2 banks (AXI4)
                                        |   DMA (AXI4) ------->  (2 x 2)
                                        +-> axi_lite_from_mem -> axi_lite_xbar -> peripherals
                                            (AXI4-Lite)          (1 x 3)          (AXI4-Lite)
```

| Port | Direction | Type | To or from |
|---|---|---|---|
| `core_req_i`, `core_rsp_o` | in, out | `obi_req_t`, `obi_rsp_t` | Core data port |
| `dtcm_req_o`, `dtcm_rsp_i` | out, in | `obi_req_t`, `obi_rsp_t` | D-TCM |
| `dma_req_i`, `dma_rsp_o` | in, out | `axi_mst_req_t`, `axi_mst_rsp_t` | DMA master port |
| `l2_req_o`, `l2_rsp_i` | out, in | `axi_slv_req_t`, `axi_slv_rsp_t` × `DATA_NUM_SLV` | L2 banks, indexed by `DATA_SLV_*` |
| `periph_req_o`, `periph_rsp_i` | out, in | `axil_req_t`, `axil_rsp_t` × `CTRL_NUM_SLV` | Peripheral registers, indexed by `CTRL_SLV_*` |

All in `clk_i`, reset by `rst_ni`. The types and indices come from `soc_pkg`.

## Core data port

`bus_obi_demux` decodes each address with `CORE_ADDR_MAP`:

| Window | Target | Index |
|---|---|---|
| `0x1001_0000`–`0x1001_7FFF` | D-TCM | `CORE_TGT_DTCM` |
| `0x2000_0000`–`0x2000_FFFF` | L2, through `bus_obi2axi` and the data crossbar | `CORE_TGT_DATA` |
| `0x4000_0000`–`0x4FFF_FFFF` | Peripheral registers, through the control bus | `CORE_TGT_CTRL` |

- An address in no window, the Boot ROM and the I-TCM included, reaches no target: the demux grants
  it at once and answers with `err` in the next cycle.
- One access is outstanding at a time. The demux accepts the next one in the cycle the previous one
  answers, which is when the core sends it, so back-to-back accesses lose no cycle. The responses
  come in order, each from the target its access went to.
- `err` reaches the core with the response and becomes an access fault:

| Access | Answered by |
|---|---|
| Outside every window | The demux |
| Control window, no peripheral there | `DECERR` from the control crossbar |
| Register the peripheral rejects | `SLVERR` from the peripheral |
| L2 | Never an error: the core sends only L2 addresses to the data bus |

## Control bus

`axi_lite_from_mem` turns the core's access into AXI4-Lite, 32 bits, and `axi_lite_xbar` sends it
to a peripheral by `CTRL_ADDR_MAP`: 4 KiB of registers each, timer at `0x4000_0000`, DMA at
`0x4000_1000`, coprocessor at `0x4000_2000`. The address and byte enables go unchanged: the
peripherals take the register from `addr[11:2]` and the byte enables as strobes. Spill registers on
every channel at the core side of the crossbar (`CTRL_XBAR_LATENCY`) keep the grant to the core from
depending on a peripheral.

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

## Core bridge

`bus_obi2axi` turns each load or store of the core into one AXI4 transaction of one full 16-byte
beat (len 0, ID 0). `axi_from_mem` handles the protocol; the bridge moves the word to its 32-bit
lane, `addr[3:2]`, and back:

| Field | From the OBI request | `sb` to `0x2000_0016` |
|---|---|---|
| AW/AR address | `addr` with bits 3:0 cleared | `0x2000_0010` |
| W data | `wdata` on all four lanes | the byte, 16 times |
| W strobe | `be` shifted to the lane | `be` = `0100`, lane 1: `0x0040` |
| `rdata` to the core | The lane of the R beat: the word that holds the access | lane 1 |

- The core already places a byte or halfword on its bytes of the word and sets `be` from
  `addr[1:0]` ([core](../core/README.md#ports)), so the strobe enables exactly the bytes of the
  access, and the core extracts a loaded byte or halfword from the word itself.
- One response per access, in order. `SLVERR` and `DECERR` both set `err`, which the core takes as
  an access fault.
- The bridge grants up to two accesses before their responses. The core has one outstanding, but
  it raises the next request in the cycle the previous response arrives, and gets the grant in that
  cycle. The lane of each access waits in a FIFO that moves with the response FIFO of
  `axi_from_mem`.

## Verification

| Testbench | Checks |
|---|---|
| `tb_soc_pkg` | The address maps and configurations of `soc_pkg` against the memory map |
| `tb_bus_axi_xbar` | `bus_axi_xbar` under random traffic from both masters (vendor `axi_rand_master`, `axi_rand_slave` and the upstream crossbar monitor), and directed: data across masters and banks, `DECERR`, read and write on the two banks at the same time |
| `tb_bus_top` | `bus_top` with an OBI driver as the core, a random AXI4 master as the DMA in its own area of both banks, `axi_sim_mem` banks, a D-TCM model and `axi_lite_regs` peripherals with an ID register. Each response against a model of the memories and registers and the error its address must get, and the target each access reaches. Directed: the edges of every window, a different target on every back-to-back access. Then random accesses over every window and unmapped space |
| `bus_obi_sva` | Bound to `bus_obi_demux` ([`verif/assertions`](../../verif/assertions/bus_obi_sva.sv)): the OBI rules at the core port and the D-TCM port, `req` and payload held until `gnt`, no response without an access, one outstanding |
| `tb_bus_obi2axi` | `bus_obi2axi` against `axi_sim_mem`, with every AXI channel stalled 0 to 15 cycles (vendor `axi_delayer`). Each AW, W and AR is checked against its OBI request and each response against a byte model of the memory. Directed: stores and loads of every size at every position of a beat, `SLVERR` and `DECERR`, two accesses outstanding. Then random accesses |

`SEED=random` with `PLUSARGS=+TXNS=<n>` (`tb_bus_axi_xbar`) or `PLUSARGS=+OPS=<n>`
(`tb_bus_obi2axi`, `tb_bus_top`) runs more random traffic.

---
[← Back to RTL](../README.md)
