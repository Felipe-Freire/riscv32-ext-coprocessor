# Memories

The memories of the SoC, built on the technology primitive
[`prim_ram_1p`](../prim/README.md): the generic flip-flop model in RTL simulation, the OpenRAM
macros of FreePDK45 in synthesis (`MEM_TECH`, [`rtl/prim`](../prim/README.md#memory-technology-mem_tech)).
Their addresses are in the [memory map](../top/README.md#memory-map).

| Module | In the SoC | Size | Port | RAM | Macros (`openram45`) |
|---|---|---|---|---|---|
| [`mem_tcm`](mem_tcm.sv) | I-TCM (`HoldRdata = 1`), D-TCM (`HoldRdata = 0`) | 32 KiB each | OBI (`soc_pkg::obi_req_t`, `obi_rsp_t`) | `prim_ram_1p` 32 × 8192 | 4 each |
| [`mem_l2_bank`](mem_l2_bank.sv) | L2 banks 0 and 1 | 32 KiB each | AXI4 slave of the data crossbar (`soc_pkg::axi_slv_req_t`, `axi_slv_rsp_t`) | `prim_ram_1p` 128 × 2048 | 4 each |

The boot ROM comes with the top (cells, not a macro): it is generated from the boot code.

## `mem_tcm`

| Parameter | Default | Meaning |
|---|---|---|
| `SizeBytes` | `32'h8000` | Size in bytes, a power of 2 of at least 8 |
| `HoldRdata` | `0` | 1: `rdata` keeps the word of the last load (the I-TCM, for the fetch port) |

| Port | Dir | Type | Description |
|---|---|---|---|
| `clk_i`, `rst_ni` | in | `logic` | Clock, asynchronous reset (active low) |
| `obi_req_i` | in | `obi_req_t` | `req`, `addr`, `we`, `be`, `wdata` |
| `obi_rsp_o` | out | `obi_rsp_t` | `gnt`, `rvalid`, `rdata`, `err` |

No wait state, and the timing the fetch port and the data port of the core need
([`rtl/core`](../core/README.md#ports)):

- `gnt` is always 1: every request is taken in its cycle. A new request can come in the cycle of
  the response of the previous one, which is when the core sends it, so back-to-back accesses lose
  no cycle.
- `rvalid` comes exactly one cycle after each request, load or store. `err` is always 0: the
  demuxes in front of the TCMs answer the addresses outside them.
- With the `rvalid` of a load, `rdata` is the word. In any other cycle it is 0, or, with
  `HoldRdata`, the word of the last load (0 after reset). The fetch port reads the instruction one
  cycle after the request and expects it held while the request is low (a stalled pipeline): a
  register keeps it, and a mux picks the RAM in the cycle after a load and the register
  otherwise, so the instruction still arrives one cycle after the request.

```
clk      _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_
req      ‾‾‾‾‾‾‾‾\_______/‾‾‾\___      (fetch: A, B, stall, C)
addr     <A ><B >        <C >
gnt      1 every cycle
rvalid   ____/‾‾‾‾‾‾‾\_______/‾‾‾
rdata        <a ><b ><b ><b ><c >      (HoldRdata = 1: b held while req is low)
```

The word index is `addr[$clog2(SizeBytes)-1:2]`; the bits above select the TCM in the demux and
are ignored here. `be` selects the bytes of a store.

## `mem_l2_bank`

| Parameter | Default | Meaning |
|---|---|---|
| `SizeBytes` | `L2_BANK_SIZE` (32 KiB) | Size in bytes, a power of 2 of at least two words |
| `BufDepth` | `1` | Depth of the response buffer of `axi_to_mem`: the latency of the RAM, enough for one beat per cycle |

| Port | Dir | Type | Description |
|---|---|---|---|
| `clk_i`, `rst_ni` | in | `logic` | Clock, asynchronous reset (active low) |
| `axi_req_i` | in | `axi_slv_req_t` | AXI4 from the data crossbar: `AXI_DATA_W` = 128 data bits, `AXI_ID_SLV_W` ID bits |
| `axi_rsp_o` | out | `axi_slv_rsp_t` | Responses, always `OKAY` |

`axi_to_mem` of [`vendor/axi`](../../vendor/README.md) splits each burst into one access per beat
on the single port of the RAM, which grants every access in its cycle and answers one cycle later,
writes included (`axi_to_mem` waits for an answer to every access). The word index is
`addr[$clog2(SizeBytes)-1:4]`, bits 14:4. Only INCR bursts and no atomics: the core bridge and
the DMA issue nothing else, and simulation flags anything else.

Measured by [`tb_mem_l2_bank`](../../verif/unit/mem/tb_mem_l2_bank.sv) with streams of 16-beat
bursts of full words and no wait on the master side, the same with both `MEM_TECH`:

| Traffic | Beats per cycle | At 100 MHz |
|---|---|---|
| Reads alone | 1.00 | 1.6 GB/s |
| Writes alone | 1.00 | 1.6 GB/s |
| Reads and writes at once | 0.50 + 0.50 | 0.8 + 0.8 GB/s |
| AR to the first R beat | 2 cycles | |

One RAM port per bank caps it at one beat per cycle in total. The two banks are independent
slaves of the crossbar, so two masters working on different banks are not limited by each other.

## Backdoor

Both modules have the simulation-only functions of `prim_ram_1p`: `bd_write(index, data)` and
`bd_read(index)` reach a word by its index (32 bits in a TCM, 128 in an L2 bank) without a cycle,
for testbenches that load programs and matrices or check results. They exist with both
`MEM_TECH`, at time 0 too, and not in a netlist.

## Synthesis

`make syn BLOCK=mem TOP=mem_tcm` and `TOP=mem_l2_bank`, at 10 ns with
[`default.sdc`](../../syn/constraints/default.sdc) (I/O at 30% of the period), on the OpenRAM
macros. `mem_tcm` is the D-TCM (`HoldRdata = 0`), the default. Area in µm²; the `slow` columns
are the same tops synthesized at `CORNER=slow`, whose macros keep their analytical TT timing until
`make openram-char`
([macros](../../syn/tech/openram45/README.md#timing-and-power)):

| Top | Slack | Area | Macros | Logic | Cells | Flip-flops | `slow`: slack, area |
|---|---|---|---|---|---|---|---|
| `mem_tcm` | +0.990 ns | 374 376 | 4, 373 596 | 780 | 281 | 4 | +0.646 ns, 374 376 |
| `mem_l2_bank` | +1.024 ns | 379 176 | 4, 373 596 | 5 580 | 1 451 | 424 | +0.004 ns, 379 258 |

The critical path of `mem_tcm` starts at the falling edge of a macro (`clk0` → `dout0`), through
the mux of the row, to `rdata`. In `mem_l2_bank` it runs, at `slow`, from the AX request through
the arbitration and the fork of `axi_to_mem` to a ready of the response: a combinational path from
input to output that `soc_top` puts behind the crossbar, the point to watch in its timing (an
`axi_cut` in front of the bank breaks it, at one cycle of latency).

## Verification

| Testbench | What it checks |
|---|---|
| [`tb_mem_tcm`](../../verif/unit/mem/tb_mem_tcm.sv) | Both TCMs every cycle against a reference: `gnt` with each request, `rvalid` one cycle later and only then, `err` 0, the loaded word, 0 or the held word in every other cycle. D-TCM: random loads and stores with random byte enables and idle cycles, half of them on 16 hot words. I-TCM: sequential fetch with random jumps and runs of stalled cycles. Then `bd_read` of every word |
| [`tb_mem_l2_bank`](../../verif/unit/mem/tb_mem_l2_bank.sv) | A monitor checks every response against a reference updated by the W beats in order: random INCR bursts of up to 16 beats, any size, 8 in flight (`axi_test::axi_rand_master`), first reads (every byte checked), then writes (random strobes), then both at once, with `bd_read` of the bank after each; then the bandwidth streams above |

Both pass with `MEM_TECH=generic` and `openram45` (the smoke list runs both), and both fail on a
broken index or a missing hold register.

```bash
make sim TB=tb_mem_tcm SEED=random PLUSARGS=+OPS=100000
make sim TB=tb_mem_l2_bank MEM_TECH=openram45 PLUSARGS=+TXNS=10000
```

---
[← Back to RTL](../README.md)
