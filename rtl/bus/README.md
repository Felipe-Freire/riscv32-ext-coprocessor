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
  `tb_bus_axi_xbar` a 16-beat read and a 16-beat write take 19 cycles together and 37 in turn.
- Towards a bank the crossbar prepends the master index to the ID (2 → 3 bits) and strips it from
  the B and R beats it returns. Two masters on the same bank are served round robin, per channel.
- An address outside the L2 gets `DECERR` from the crossbar, without reaching a bank. Only the DMA
  can issue one, and its channel stops with `ERR` ([DMA](../dma/README.md#registers)).
- Spill registers on AW and AR at the masters' side of the crossbar (`DATA_XBAR_LATENCY` =
  `CUT_SLV_AX`, chosen in [Timing](#timing)). No atomic operations.

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

## Timing

`make syn BLOCK=bus`: GPDK045 `slow_vdd1v0`, [`default.sdc`](../../syn/constraints/default.sdc)
(inputs arrive and outputs are due at 30% of the period). Genus sizes the logic until the
constraint is met, so the slack ends near zero at both periods; 5 ns costs 4% more area.

| Clock | Slack | Area | Flip-flops | Worst path |
|---|---|---|---|---|
| 10 ns | +0.025 ns | 17 135 | 900 | `core_req_i.addr` → `core_rsp_o.gnt`: the address decode of the demux, then the grant of the core bridge |
| 5 ns | 0.000 ns | 17 892 | 900 | `l2_rsp_i.r.id` → `dma_rsp_o.r`: an R beat of a bank, routed to its master by the ID prefix, through the crossbar |

`make sta BLOCK=bus` gives the same slack. Area at 10 ns: data crossbar 10 535, control crossbar
3 606, core bridge 605, demux 395, OBI → AXI4-Lite bridge 167. No latches. On FreePDK45, the
default technology now, 10 ns closes with +0.278 ns, 14 768 of area and the same 900 flip-flops
([`syn/`](../../syn/README.md#results)).

### Latency mode of the data crossbar

`DATA_XBAR_LATENCY` comes from synthesizing `bus_top` with each `LatencyMode` of `axi_xbar` and
running the bus testbenches on each one (core L2 latency from `tb_bus_dma_coproc`, cycles from the
request to the response; the multiplication is 64×128×128, from the DMA start to its end):

| `LatencyMode` | Area at 10 ns | Flip-flops | 5 ns | Core L2 load / store | Multiplication |
|---|---|---|---|---|---|
| `NO_LATENCY` | 14 713 | 558 | −0.58 ns | 1 / 2 | 24 551 |
| **`CUT_SLV_AX`** | **17 123** | **900** | **met** | **2 / 3** | **24 927** |
| `CUT_MST_AX` | 19 748 | 1 110 | −0.60 ns | 2 / 3 | 24 927 |
| `CUT_ALL_AX` | 22 200 | 1 452 | met | 3 / 4 | 25 375 |
| `CUT_SLV_PORTS` | 25 663 | 1 840 | met | 3 / 4 | 25 375 |
| `CUT_MST_PORTS` | 30 268 | 2 270 | −0.53 ns | 3 / 4 | 25 375 |
| `CUT_ALL_PORTS` | 41 164 | 3 552 | met | 5 / 6 | 26 051 |

- Every mode closes 10 ns. At 5 ns the ones without spill registers at the masters' side fail: the
  AW and AR of a master reach the arbitration combinationally, so the grant to the core depends on
  what the DMA sends in the same cycle (the worst path of `NO_LATENCY` runs from the DMA's AW
  address to the core's `gnt`).
- `CUT_SLV_AX` is the smallest mode that closes 5 ns. The registers at the banks' side
  (`CUT_ALL_AX`, the vendor's general recommendation) add 30% of area and a cycle to every core
  access and move no limit; registering W, B and R as well (`*_PORTS`) adds more of both.
- Throughput does not depend on the mode: a spill register moves one beat per cycle, and the
  multiplication is bound by the array (the slowest mode takes 6% longer). Each register stage
  costs the core a cycle per L2 access.
- If the L2 banks of `soc_top` need their inputs registered, `CUT_ALL_AX` adds those registers by
  changing that parameter alone.

### Core access latency

Measured by `tb_bus_dma_coproc` on an idle interconnect, in cycles from the request to the response
(1: granted at once and answered in the next cycle). The D-TCM answers in the cycles of the D-TCM
itself: the demux adds none.

| Access | Cycles |
|---|---|
| L2 load | 2 |
| L2 store | 3 |
| Register load | 3 |
| Register store | 4 |
| Control window outside the peripherals (`DECERR`) | 4 |
| Outside every window (err from the demux) | 1 |

### In `soc_top`

The path from the core's address to `gnt` is combinational through the demux decode and the grant
of the bridge. In the SoC it starts at the EX adder of the core (`data_addr_o`) and ends in its
stall logic (`data_gnt_i`, which holds the pipeline), so it is the path to watch in the timing of
the top.

## Verification

| Testbench | Checks |
|---|---|
| `tb_soc_pkg` | The address maps and configurations of `soc_pkg` against the memory map |
| `tb_bus_axi_xbar` | `bus_axi_xbar` under random traffic from both masters (vendor `axi_rand_master`, `axi_rand_slave` and the upstream crossbar monitor), and directed: data across masters and banks, `DECERR`, read and write on the two banks at the same time |
| `tb_bus_top` | `bus_top` with an OBI driver as the core, a random AXI4 master as the DMA in its own area of both banks, `axi_sim_mem` banks, a D-TCM model and `axi_lite_regs` peripherals with an ID register. Each response against a model of the memories and registers and the error its address must get, and the target each access reaches. Directed: the edges of every window, a different target on every back-to-back access. Then random accesses over every window and unmapped space |
| `bus_obi_sva` | Bound to `bus_obi_demux` ([`verif/assertions`](../../verif/assertions/bus_obi_sva.sv)): the OBI rules at the core port and the D-TCM port, `req` and payload held until `gnt`, no response without an access, one outstanding |
| `tb_bus_obi2axi` | `bus_obi2axi` against `axi_sim_mem`, with every AXI channel stalled 0 to 15 cycles (vendor `axi_delayer`). Each AW, W and AR is checked against its OBI request and each response against a byte model of the memory. Directed: stores and loads of every size at every position of a beat, `SLVERR` and `DECERR`, two accesses outstanding. Then random accesses |

`SEED=random` with `PLUSARGS=+TXNS=<n>` (`tb_bus_axi_xbar`) or `PLUSARGS=+OPS=<n>`
(`tb_bus_obi2axi`, `tb_bus_top`) runs more random traffic. `make syn BLOCK=bus TOP=bus_axi_xbar`
then `make gls TB=tb_bus_axi_xbar TOP=bus_axi_xbar` runs the crossbar test on the netlist.

---
[← Back to RTL](../README.md)
