# Technology primitives

Anything that maps to a specific cell or macro is instantiated through a `prim_` module
([technology independence](../README.md#technology-independence)). This directory holds the
generic behavioral version of each primitive, for simulation. A technology version keeps the same
module name, parameters and ports in `rtl/prim/<tech>/`, and replaces the generic one through the
primitive file list.

| Primitive | Function | Versions |
|---|---|---|
| [`prim_ram_1p`](prim_ram_1p.sv) | Single-port RAM: one read or write per cycle, byte enables, read data one cycle later | generic, [`openram45`](openram45/prim_ram_1p.sv) |

## Memory technology (`MEM_TECH`)

| `MEM_TECH` | File list | What `prim_ram_1p` is | Default of |
|---|---|---|---|
| `generic` | [`prim.f`](prim.f) | A flip-flop array, never synthesized as a memory | RTL simulation |
| `openram45` | [`openram45/prim.f`](openram45/prim.f) | Tiles of the OpenRAM macro `sram_sp_2048x32_m8` of FreePDK45 ([`syn/tech/openram45`](../../syn/tech/openram45/README.md)) | Synthesis, STA and gate level with `TECH=freepdk45` |

The Makefile hands the file list of `MEM_TECH` to every flow as `PRIM_FLIST`, which
[`rtl/rtl.f`](../rtl.f) and the block lists read, and adds what the macros need: their Liberty and
LEF files to synthesis and STA, their Verilog models (`-v`) to simulation and gate level. Any flow
takes `MEM_TECH=` to override its default:

```bash
make sim TB=tb_mem_tcm                       # generic
make sim TB=tb_mem_tcm MEM_TECH=openram45    # the same testbench on the macro models
make syn BLOCK=mem TOP=mem_l2_bank           # openram45: 4 macros
```

The netlist records the memory technology with its cells (`outputs/cells`), so `make sta` and
`make gls` stop on a netlist synthesized with other memories.

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

Both versions flag, from the second clock edge on, `req_i` at X, `we_i` or `addr_i` at X during an
access, `be_i` at X during a write, and an address past the last word. (A clock that starts at 1
has an edge at time 0, before the logic in front of the RAM drives anything.)

### `openram45`

The OpenRAM version tiles `sram_sp_2048x32_m8` (2048 × 32, byte write mask): `ceil(Depth / 2048)`
rows in depth by `ceil(Width / 32)` columns in width. The upper address bits select the row, every
tile of that row takes the access, each column holds 32 bits of the word under its 4 byte enables,
and a register of the row of the last access selects the row that drives `rdata_o`. The SoC uses:

| User | Shape | Tiles | Macros |
|---|---|---|---|
| I-TCM, D-TCM (`mem_tcm`, 32 KiB) | 32 × 8192 | 4 rows × 1 column | 4 each |
| L2 bank (`mem_l2_bank`, 32 KiB) | 128 × 2048 | 1 row × 4 columns | 4 each, 8 for the two banks |

A shape that is not a multiple of the macro leaves part of a tile unused (the default 32 × 1024
uses half of one). The macro keeps the contract with no logic around it: it registers the access
on the rising edge, reads on the falling edge and drives its output X from 1 ns after every rising
edge, so `rdata_o` is valid in the cycle after a read and X otherwise. Its read data is ready half a
period plus about 0.4 ns after the rising edge (analytical TT timing, see the
[macro](../../syn/tech/openram45/README.md#timing-and-power)), and its model needs a clock period of
6 ns or more in simulation.

The backdoor reaches the `mem` array of the model of each tile. A hierarchical name cannot index
generate blocks with a variable, so each tile registers an accessor object, before time 0, in an
array that `bd_write` and `bd_read` index: testbenches call them at time 0 as with the generic
version.

## Porting to another memory technology

The lab libraries of a commercial kit (GPDK045 has no memories) would come in as one more
`MEM_TECH`, with nothing above `prim/` changing:

1. Copy the views to `lib/<tech>/` (they cannot be committed under an NDA) and, if the cells
   change too, select `TECH` (`gpdk045`, or a new one in `syn/tech/tech.mk`).
2. Write `rtl/prim/<tech>/prim_ram_1p.sv` on the macro of the kit, keeping the contract above:
   polarities of chip select and write enable, write mask from `be_i`, tiling, a backdoor into the
   array of its simulation model. Then `rtl/prim/<tech>/prim.f`.
3. Add `<tech>` to `MEM_TECHS` in `syn/tech/tech.mk`, with its Liberty, LEF and Verilog model
   files in place of `MEM_LIBS`, `MEM_LEFS`, `MEM_MODELS`, and make it the `MEM_TECH_IMPL` of
   its `TECH`.
4. Run `tb_prim_ram_1p`, `tb_mem_tcm` and `tb_mem_l2_bank` with `MEM_TECH=<tech>`, then
   `make syn BLOCK=mem`.

## Verification

[`tb_prim_ram_1p`](../../verif/unit/prim/tb_prim_ram_1p.sv) runs the contract on the two shapes of
the SoC, 32 × 8192 (TCMs) and 128 × 2048 (L2 bank), with whichever version `MEM_TECH` compiles
(the smoke list runs both):

- backdoor fill, then front-door reads;
- random reads, writes with random byte enables and idle cycles, half of them on a few hot words,
  plus the first and the last word;
- the read data one cycle after each read, and X one cycle after any other cycle;
- backdoor read of every word at the end.

`make sim TB=tb_prim_ram_1p SEED=random PLUSARGS=+OPS=<n>` sets the random accesses per shape
(20 000 by default).

---
[← Back to RTL](../README.md)
