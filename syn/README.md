# Synthesis and timing

ASIC synthesis and static timing analysis with Cadence Genus. `TECH` picks the technology:

| `TECH` | Cells | Kit | Use |
|---|---|---|---|
| `freepdk45` (default) | NanGate Open Cell Library | `lib/freepdk45`, downloaded by `make freepdk45` from [mflowgen/freepdk-45nm](https://github.com/mflowgen/freepdk-45nm) at a fixed commit, with checksums ([`tech/freepdk45/`](tech/freepdk45/)) | Open 45 nm PDK. Its SRAM macros come from OpenRAM (`make openram`, [`tech/openram45/`](tech/openram45/README.md)), on the same layers. It cannot be fabricated: area and timing are estimates |
| `gpdk045` (standby) | gsclib045 | `/apps/cds/installs/STRATUS2501/share/stratus/techlibs/GPDK045`, then `lib/GPDK045` or `lib/` | Cadence generic 45 nm kit, which has no memories; kept for when the lab libraries are checked |

Both estimate the wires from the placement Genus predicts (PLE): from the LEF and the capacitance
table of the kit in FreePDK45, which has no QRC rules, and from the QRC rules in GPDK045.
`FREEPDK45=<dir>` or `GPDK045=<dir>` points at another copy of the kit. Without the kit of the
chosen `TECH`, or with `LIBS=`, the flows use the Genus tutorial library, whose area and timing only
compare RTL versions with each other. `make help` shows the technology in use.

## Running

```bash
source scripts/setup.sh
make freepdk45                                  # once: FreePDK45/NanGate views to lib/freepdk45
make openram                                    # once: SRAM macros to lib/openram45 (builds .venv)
make syn-list                                   # blocks and the modules each one can synthesize
make syn                                        # core: rv32_core
make syn BLOCK=coproc ACC_CLK_PERIOD=5          # coprocessor: coproc_top, array clock at 5 ns
make syn BLOCK=core TOP=rv32_alu CLK_PERIOD=5   # any module of the block's file lists
make sta BLOCK=coproc CORNER=slow               # time the coproc_top netlist at another corner
make syn BLOCK=core TECH=gpdk045                # the same block on the GPDK045 cells
```

`make help` lists every variable. The main ones:

| Variable | Default | Meaning |
|---|---|---|
| `BLOCK` | `core` | `prim`, `core`, `coproc`, `dma` or `bus`: selects the file lists and the default top |
| `TOP` | Block top | Any module of the block's file lists |
| `CLK_PERIOD`, `ACC_CLK_PERIOD` | `10`, `CLK_PERIOD` | `clk_i` and `clk_acc_i` periods in ns |
| `TECH` | `freepdk45` | `freepdk45` or `gpdk045` |
| `CORNER` | `typical` | Liberty corner. FreePDK45: `typical` (1.1 V, 25 °C, the only corner of the OpenRAM macros so far), `slow` (0.95 V, 125 °C), `fast` (1.25 V, 0 °C). GPDK045: `slow_vdd1v0` (default there), `slow_vdd1v2`, `fast_vdd1v0`, `fast_vdd1v2` |
| `VT`, `RC_CORNER` | `svt`, `rcworst` | GPDK045 only: threshold flavour and wire estimation rules |
| `LIBS`, `LEFS` | The kit's | Liberty and LEF files; empty selects the tutorial library |
| `CLOCK_GATING` | `1` | Clock-gating cells where the library has them |
| `EFFORT` | `medium` | `low`, `medium` or `high` |

`make syn` writes to `build/syn/<top>/`: `genus.log`, `reports/` (`summary.rpt` with slack, area
and cell counts, then area per instance, timing, gates, power, `check_design`) and `outputs/`
(netlist, SDC and SDF). `make sta` reads that netlist and SDC and writes to
`build/sta/<top>/<corner>/`: `reports/` (`summary.rpt`, worst paths, endpoints, design-rule
violations) and `outputs/<top>.sdf`. Genus has no hold analysis, so STA checks setup and design
rules only; hold waits for Tempus.

## Results

The tops of the blocks at 10 ns (`coproc_top` with `clk_acc_i` at 10 ns too), `EFFORT=medium`,
clock gating on, [`default.sdc`](constraints/default.sdc) and the PLE wires of each kit. Area in
µm² from the Liberty files. FreePDK45 at the default `typical` (1.1 V, 25 °C); the last columns are
the same tops synthesized at FreePDK45 `slow` (0.95 V, 125 °C) and at GPDK045 `slow_vdd1v0`
(0.9 V, 125 °C):

| Top | Slack | Area | Cells | Flip-flops | Clock gates | `slow`: slack, area | GPDK045: slack, area |
|---|---|---|---|---|---|---|---|
| `rv32_core` | +2.786 ns | 21 042 | 5 424 | 1 639 | 45 | +0.430 ns, 21 540 | +0.010 ns, 26 951 |
| `coproc_top` | +3.381 ns | 97 839 | 24 885 | 6 316 | 52 | +1.929 ns, 109 938 | +1.144 ns, 130 439 |
| `bus_top` | +2.569 ns | 14 814 | 4 283 | 900 | 59 | +0.278 ns, 14 768 | +0.025 ns, 17 135 |

`make sta` gives the same slack as the synthesis. `check_design` has no unresolved references,
undriven or multidriven ports, and every cell has its LEF. The gate-level regression
([`gls.list`](../verif/regress/gls.list)) runs on the `slow` netlists, with and without SDF: no hold
is fixed before place and route, so at `typical` the flops that drive other flops directly
(synchronizers, reset release) break the hold time of the next one.

The SRAM macro, from [OpenRAM](tech/openram45/README.md). Its timing is **an analytical
estimate**: OpenRAM's model gives a negative delay at SS and the same setup and hold at every
corner, so only its TT Liberty file exists, and every `CORNER` reads it.

| Macro | Area | `clk0` → `dout0` (TT) | Setup / hold (TT) |
|---|---|---|---|
| `sram_sp_2048x32_m8`, 2048 × 32 | 89 532 (232.4 × 385.2 µm) | Half a period + 0.36 ns: the falling edge, then 0.362 ns | 0.009 / 0.001 ns |

## Contents

| Path | Contents |
|---|---|
| [`tech/tech.mk`](tech/tech.mk) | Technology: `TECH` selection, kit paths, corners, cell models; tutorial library fallback |
| [`tech/freepdk45/`](tech/freepdk45/) | `make freepdk45`: download of the FreePDK45/NanGate views, the commit they come from and their checksums |
| [`tech/openram45/`](tech/openram45/README.md) | `make openram`: OpenRAM configurations of the SRAM macros, their ports, size and timing |
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
- Genus reads the file lists with the defines Bender passes to a Genus synthesis (`SYNTHESIS`,
  `TARGET_SYNTHESIS`, `TARGET_GENUS`): the vendor IP leaves out its assertions and the interface
  wrappers Genus cannot parse under them, and RTL puts simulation-only code in `` `ifndef SYNTHESIS``.
  Genus keeps the include directories of a file list to that list, so a list repeats the
  `+incdir+` of every header its files include (`vendor/axi.f` repeats the `common_cells` one).
- A packed struct port (the bus types of `soc_pkg`) is one vector port in the netlist
  (`hdl_flatten_complex_port`), not one port per field, so `make gls` plugs the netlist into the
  testbench of the RTL: `make gls TB=tb_bus_axi_xbar TOP=bus_axi_xbar`.
- PDK files and macro views are never committed: a local copy goes in `lib/`, which git ignores
  (`make freepdk45` writes `lib/freepdk45`, `make openram` writes `lib/openram45`).
- `make syn` writes the cell set of the netlist to `outputs/cells`; `sta` and `gls` stop when the
  technology in use has other cells, so run `make syn` again after changing `TECH`, `VT` or `LIBS`.
- Netlists, reports and logs go to `build/`, never into this directory.
- Use the same tool version and options for every configuration you compare, so differences in
  area and timing come from the RTL.

---
[← Back to project root](../README.md)
