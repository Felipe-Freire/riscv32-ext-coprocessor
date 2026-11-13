# Synthesis

ASIC synthesis with Cadence Genus. The PDK is not chosen yet: without `LIBS`, the flow maps to the
tutorial library shipped with Genus, whose area and timing only compare RTL versions with each other.

## Running

```bash
source scripts/setup.sh
make syn-list                                   # blocks and the modules each one can synthesize
make syn                                        # core: rv32_core
make syn BLOCK=coproc                           # coprocessor: coproc_pe_array
make syn BLOCK=core TOP=rv32_alu CLK_PERIOD=5   # any module of the block's file list
```

| Variable | Default | Meaning |
|---|---|---|
| `BLOCK` | `core` | `core` or `coproc`: selects the file list and the default top |
| `TOP` | Block top | Any module of the block's file list |
| `CLK_PERIOD` | `10` | Clock period in ns |
| `LIBS` | Genus tutorial library | Liberty files, space-separated |
| `EFFORT` | `medium` | `low`, `medium` or `high` |

Each run writes to `build/syn/<top>/`: `genus.log`, `reports/` (`summary.rpt` with slack, area and
cell counts, then area per instance, timing, gates, power, `check_design`) and `outputs/` (netlist
and SDC).

## Contents

| Path | Contents |
|---|---|
| [`syn.mk`](syn.mk) | Make targets and the block table: file list and default top of each block |
| [`genus/syn.tcl`](genus/syn.tcl) | Genus flow: read, elaborate, `syn_generic`, `syn_map`, `syn_opt`, reports |
| [`constraints/`](constraints/) | `default.sdc` for any top (clock on `clk_i`, I/O at 30% of the period, resets untimed); a `<top>.sdc` replaces it for that top |

## Conventions

- Each block is read through its own file list (`rtl/<block>/<block>.f`): only the files listed
  there are synthesized. The SoC top will read [`rtl/rtl.f`](../rtl/rtl.f), with the technology
  primitive list in place of `rtl/prim/prim.f`.
- To add a block, add it to `SYN_BLOCKS` in [`syn.mk`](syn.mk) with its `SYN_FLIST_<block>` and
  `SYN_TOP_<block>`.
- PDK files and macro views stay outside the repository (they are usually under NDA). Pass them
  through `LIBS`.
- Netlists, reports and logs go to `build/syn/`, never into this directory.
- Use the same tool version and options for every configuration you compare, so differences in
  area and timing come from the RTL.

---
[← Back to project root](../README.md)
