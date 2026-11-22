# Technology primitives

Anything that maps to a specific cell or macro is instantiated through a `prim_` module
([technology independence](../README.md#technology-independence)). This directory holds the
generic behavioral version of each primitive, for simulation. A technology version keeps the same
module name, parameters and ports in `rtl/prim/<tech>/`, and replaces the generic one through the
primitive file list.

| Primitive | Function |
|---|---|
| [`prim_ram_1p`](prim_ram_1p.sv) | Single-port RAM: one read or write per cycle, byte enables, read data one cycle later |

## `prim_ram_1p`

| Parameter | Default | Meaning |
|---|---|---|
| `Width` | 32 | Bits per word, a multiple of 8 |
| `Depth` | 1024 | Words; the address is `$clog2(Depth)` bits |

| Port | Dir | Bits | Description |
|---|---|---|---|
| `clk_i` | in | 1 | Clock; the RAM has no reset |
| `req_i` | in | 1 | Access in this cycle |
| `we_i` | in | 1 | 1: write, 0: read |
| `addr_i` | in | `$clog2(Depth)` | Word address |
| `wdata_i`, `be_i` | in | `Width`, `Width/8` | Write data and byte enables: a write changes only the bytes whose bit is set |
| `rdata_o` | out | `Width` | Read data |

The contract every version keeps, and the blocks that use the RAM rely on:

- One access per cycle, sampled on the rising edge of `clk_i`. A read and a write never share a
  cycle.
- `rdata_o` holds the word read in the cycle after the read, and only in that cycle. After a write
  or an idle cycle it is undefined, and the generic version drives X there, as the OpenRAM macros
  do. A block that needs the data for longer registers it itself (the I-TCM, which the core fetch
  port expects to hold its data).
- The contents are unknown until written: there is no reset and no initialization.
- In simulation, `bd_write(index, data)` and `bd_read(index)` write and read a whole word by its
  index without a cycle, so testbenches load programs and matrices and check results. They do not
  exist in the netlist.

The generic version is a flip-flop array: it is for simulation and never synthesized as a
memory. Its assertions flag `req_i` at X, `we_i` or `addr_i` at X during an access, `be_i` at X
during a write, and an address past the last word.

## Verification

[`tb_prim_ram_1p`](../../verif/unit/prim/tb_prim_ram_1p.sv) runs the contract on the two shapes of
the SoC, 32 × 8192 (TCMs) and 128 × 2048 (L2 bank), with whichever version the primitive file list
compiles:

- backdoor fill, then front-door reads;
- random reads, writes with random byte enables and idle cycles, half of them on a few hot words,
  plus the first and the last word;
- the read data one cycle after each read, and X one cycle after any other cycle;
- backdoor read of every word at the end.

`make sim TB=tb_prim_ram_1p SEED=random PLUSARGS=+OPS=<n>` sets the random accesses per shape
(20 000 by default).

---
[← Back to RTL](../README.md)
