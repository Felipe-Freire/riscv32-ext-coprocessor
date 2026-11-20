# Synthesis and timing

ASIC synthesis and static timing analysis with Cadence Genus, on the GPDK045 standard cells
(gsclib045). The kit is looked up in `/apps/cds/installs/STRATUS2501/share/stratus/techlibs/GPDK045`,
then in `lib/GPDK045` or `lib/` of the project (git-ignored), or given with `GPDK045=<dir>`. Without
it, or with `LIBS=`, both use the Genus tutorial library, whose area and timing only compare RTL
versions with each other. `make help` shows the technology in use.

## Running

```bash
source scripts/setup.sh
make syn-list                                   # blocks and the modules each one can synthesize
make syn                                        # core: rv32_core
make syn BLOCK=coproc ACC_CLK_PERIOD=5          # coprocessor: coproc_top, array clock at 5 ns
make syn BLOCK=core TOP=rv32_alu CLK_PERIOD=5   # any module of the block's file lists
make sta BLOCK=coproc CORNER=slow_vdd1v2        # time the coproc_top netlist at another corner
```

`make help` lists every variable. The main ones:

| Variable | Default | Meaning |
|---|---|---|
| `BLOCK` | `core` | `core` or `coproc`: selects the file lists and the default top |
| `TOP` | Block top | Any module of the block's file lists |
| `CLK_PERIOD`, `ACC_CLK_PERIOD` | `10`, `CLK_PERIOD` | `clk_i` and `clk_acc_i` periods in ns |
| `VT`, `CORNER`, `RC_CORNER` | `svt`, `slow_vdd1v0`, `rcworst` | GPDK045 flavour, Liberty corner and wire estimation rules |
| `LIBS`, `LEFS` | GPDK045 | Liberty and LEF files; empty selects the tutorial library |
| `CLOCK_GATING` | `1` | Clock-gating cells where the library has them |
| `EFFORT` | `medium` | `low`, `medium` or `high` |

`make syn` writes to `build/syn/<top>/`: `genus.log`, `reports/` (`summary.rpt` with slack, area
and cell counts, then area per instance, timing, gates, power, `check_design`) and `outputs/`
(netlist, SDC and SDF). `make sta` reads that netlist and SDC and writes to
`build/sta/<top>/<corner>/`: `reports/` (`summary.rpt`, worst paths, endpoints, design-rule
violations) and `outputs/<top>.sdf`. Genus has no hold analysis, so STA checks setup and design
rules only; hold waits for Tempus.

## Contents

| Path | Contents |
|---|---|
| [`tech/tech.mk`](tech/tech.mk) | Technology: GPDK045 paths, corners, cell models; tutorial library fallback |
| [`tech/tutorial_cells.v`](tech/tutorial_cells.v) | Simulation models of the tutorial library, for gate-level simulation without the kit |
| [`syn.mk`](syn.mk), [`genus/syn.tcl`](genus/syn.tcl) | `make syn`: read, elaborate, `syn_generic`, `syn_map`, `syn_opt`, reports |
| [`sta.mk`](sta.mk), [`genus/sta.tcl`](genus/sta.tcl) | `make sta`: timing of the netlist at one corner, SDF |
| [`genus/sdf.tcl`](genus/sdf.tcl) | SDF with an ideal clock (clock-gating cells at zero delay), as the timing assumes before CTS |
| [`constraints/`](constraints/) | `default.sdc` for any top (clock on `clk_i`, I/O at 30% of the period, resets untimed); `<top>.sdc` replaces it, as `coproc_top.sdc` does to add `clk_acc_i` |

## Conventions

- The blocks are in the top-level [`Makefile`](../Makefile): file lists in compile order (vendor
  IP first) and default top. To add one, add it to `BLOCKS` with its `RTL_FLIST_<block>` and
  `RTL_TOP_<block>`. The SoC top will read [`rtl/rtl.f`](../rtl/rtl.f), with the technology
  primitive list in place of `rtl/prim/prim.f`.
- PDK files and macro views are never committed: a local copy goes in `lib/`, which git ignores.
- `make syn` writes the cell set of the netlist to `outputs/cells`; `sta` and `gls` stop when the
  technology in use has other cells, so run `make syn` again after changing `VT` or `LIBS`.
- Netlists, reports and logs go to `build/`, never into this directory.
- Use the same tool version and options for every configuration you compare, so differences in
  area and timing come from the RTL.

---
[← Back to project root](../README.md)
