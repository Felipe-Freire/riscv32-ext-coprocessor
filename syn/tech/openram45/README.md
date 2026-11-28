# OpenRAM SRAM macros (FreePDK45)

The SRAM macros of the SoC, generated with [OpenRAM](https://github.com/VLSIDA/OpenRAM) in its
`freepdk45` technology, which OpenRAM ships itself (bitcell, SPICE models, layers, KLayout rule
decks), so the FreePDK45 kit is not needed. They use the same layers as the NanGate cells of
[`lib/freepdk45`](../freepdk45/), so synthesis reads their Liberty and LEF next to the cells.

**The flows need no OpenRAM run.** The views they read, the Liberty file, LEF and Verilog model of
each macro (about 30 KB), are kept in git in [`views/`](views/), so a clone simulates, synthesizes
and times the SoC as it is. The targets below are only for regenerating a macro or characterizing
it, and they copy their views back to `views/`, to be committed once:

```bash
make venv            # once: .venv with OpenRAM 1.2.48 (requirements.txt), ngspice and KLayout (eda-tools.yml)
make openram         # every macro: layout, DRC/LVS, TT timing -> lib/openram45/<macro>/ (git-ignored), 50 min each
make openram-char    # optional: ngspice timing at every corner -> lib/openram45/<macro>/spice/, hours per corner
make openram MACROS=sram_sp_2048x32_m8
```

Each `<macro>.py` here is an OpenRAM configuration, and its file name is the macro name.
[`openram45.mk`](openram45.mk) runs it with the OpenRAM of the venv, with the ngspice and KLayout
of `.venv/eda` first on `PATH`, through
[`openram_macro.py`](../../../scripts/utils/openram_macro.py), which starts one OpenRAM run per
corner and checks the results. Nothing is installed outside `.venv`, and nothing needs root.

## Flow

`make openram` writes everything the RTL, synthesis, STA and gate-level flows need. It runs
OpenRAM's whole layout flow, as for OpenRAM's own sky130 macros:

1. **Netlist and layout** of the bitcell array, decoders, sense amplifiers, write drivers and
   control logic.
2. **Supply rings** around the macro (`route_supplies = "ring"`) and every signal pin on its edge
   (`perimeter_pins`), so a place and route can reach them.
3. **DRC and LVS** of the final layout with KLayout and the FreePDK45 decks OpenRAM ships (160 DRC
   rules). LVS compares the extracted layout with `<macro>.lvs.sp`. OpenRAM stops on an LVS
   mismatch but only warns on DRC errors, so the target also stops unless the log has 0 DRC errors
   and an LVS match.
4. **Timing and power** from OpenRAM's analytical model at TT, the typical corner of the NanGate
   cells, the only corner where that model is plausible.
5. **Views**: Liberty, LEF, Verilog model, GDS, netlists, datasheet in `lib/openram45/<macro>/`,
   and a copy of the first three in `views/<macro>/`.

`make openram-char` replaces the analytical timing with a SPICE characterization, for the final
timing figures: minimum period, `clk0` to `dout0` delay and slew over 3 input slews × 3 loads,
setup and hold of every input, dynamic and leakage power, at the three corners of
`spice_corners`. OpenRAM simulates a netlist trimmed to the rows and columns of the measured access
(22 501 transistors for this macro, against 409 597 in the full array) and the leakage on the full
array. Each simulation of the trimmed netlist takes 20 to 90 minutes with ngspice, depending on the
load of the machine, and a corner needs about 17 of them, so the corners run in parallel, each in
its own OpenRAM run that lays out the same macro without DRC and LVS. The target checks that
every Liberty file has the area of the TT one in `views/`, so the layouts are the same, and copies
them to `views/<macro>/spice/`. Nothing in the flows waits for it: once its three files are
committed, every machine reads them.

Logs and intermediate files go to `build/openram/<macro>/<corner>/` (`make openram`) and
`build/openram/<macro>/char/<corner>/` (`make openram-char`): `openram.log`, and `tmp/` (kept)
with the SPICE decks and results and, for `make openram`, the DRC and LVS reports.

| File | In git | Use |
|---|---|---|
| `<macro>_TT_1p1V_25C.lib` | `views/<macro>/` | Timing, power and area for synthesis and STA, analytical, at TT |
| `spice/<macro>_TT_1p1V_25C.lib`, `_SS_0p95V_125C.lib`, `_FF_1p25V_0C.lib` | `views/<macro>/spice/`, after `make openram-char` | The same from ngspice at each corner |
| `<macro>.lef` | `views/<macro>/` | Abstract for the placement estimate (PLE) and a place and route: pins on the edge, supply rings |
| `<macro>.v` | `views/<macro>/` | Behavioral model for simulation and gate level, written with `VERBOSE = 0` (the generated model prints every access otherwise) |
| `<macro>.gds` | No, `lib/openram45/<macro>/` (22 MB) | Layout (`klayout <macro>.gds` with `.venv/eda/bin` on `PATH`, see `scripts/setup.sh`) |
| `<macro>.sp`, `<macro>.lvs.sp` | No, `lib/openram45/<macro>/` (4.5 MB each) | Netlist of the characterization, netlist of the LVS |
| `<macro>.html` | No, `lib/openram45/<macro>/` | Datasheet: ports, timing and power |

The views in git have no path of the machine and carry the licenses of OpenRAM (BSD 3-Clause) and
of its FreePDK45 technology (Apache 2.0), with no NDA. `syn/tech/tech.mk` lists the macros
(`OPENRAM45_MACROS`, one per configuration) and gives their views in `OPENRAM45_VIEWS` at `CORNER`
as `MEM_LIBS`, `MEM_LEFS` and `MEM_MODELS`. For each macro, `MEM_LIBS` takes the `spice/` Liberty
file of `CORNER` when it exists and the analytical TT one otherwise, so before
`make openram-char` a `CORNER=slow` or `fast` run pairs those cells with TT macros.

## Macros

| Macro | Words × bits | Ports | Area | Layout | Used for |
|---|---|---|---|---|---|
| [`sram_sp_2048x32_m8`](sram_sp_2048x32_m8.py) | 2048 × 32 (8 KiB) | 1 read/write, byte write mask | 93 399 µm² | 238.6 × 391.5 µm, column mux 8 (256 × 256 bitcells), supply rings, 84 pins on the edge. DRC clean, LVS match | Tile of every SRAM: 4 deep per TCM, 4 wide per L2 bank (16 in the SoC, 1.49 mm²) |

`make openram` takes 50 minutes for it: 17 minutes to build the submodules (array, decoders,
control), 25 to route the signals, rings and pins, 8 for DRC and LVS.

Ports of `sram_sp_2048x32_m8`, all sampled on the rising edge of `clk0`:

| Port | Bits | Description |
|---|---|---|
| `clk0` | 1 | Clock |
| `csb0` | 1 | Chip select, active low |
| `web0` | 1 | Write enable, active low (1: read) |
| `wmask0` | 4 | Byte write mask, active high |
| `addr0` | 11 | Word address |
| `din0`, `dout0` | 32 | Write data, read data |
| `vdd`, `gnd` | | Supply rings |

The model writes and reads on the falling edge of the cycle that sampled the access. `dout0` is
valid 3 ns (`DELAY`) after that falling edge and turns X 1 ns (`T_HOLD`) after the next rising
edge. A clock period under 6 ns therefore needs a smaller `DELAY` in simulation, and a block that
needs the data for longer than one cycle registers it ([`prim_ram_1p`](../../../rtl/prim/README.md)).

## Timing and power

| `sram_sp_2048x32_m8`, TT 1.1 V 25 °C | Analytical model (`make openram`) | ngspice, one simulation |
|---|---|---|
| `clk0` falling edge → `dout0` | 0.362 to 0.363 ns over 3 input slews × 3 loads | 0.670 ns |
| Minimum period | 1.343 ns | |
| Setup / hold of the inputs to the rising edge | 0.009 / 0.001 ns | |
| Input capacitance | 0.21 fF per pin | |
| Leakage | 0.067 mW | |

The data is therefore ready half a clock period plus 0.36 ns after the rising edge that sampled the
read, by the analytical model. The ngspice column is one simulation of the characterization (the
read of a 0 on `dout0[31]` at a 5 ns period, 40 ps input slew, 0.84 fF load): the analytical delay
is almost half of it. Take the analytical numbers as optimistic by about 0.3 ns at TT until
`make openram-char` replaces them.

The analytical model is only plausible at TT: at SS 0.95 V 125 °C it gives a negative `clk0` →
`dout0` delay (−0.246 ns), and its setup and hold are the same at every corner. So
`make openram` writes only the TT Liberty file, and the default `CORNER` of FreePDK45 is
`typical`, where the cells and the macros share their PVT.

## Limits

- The analytical timing is an estimate, and an optimistic one: see the ngspice point above. The
  `clk0` → `dout0` of the I-TCM is on the path into the ID stage of the core, so the final f_max
  figures need `make openram-char`, the slow corner above all. With its files, the default
  `CORNER` can go back to `slow`, with cells and macros at the same corner.
- The SPICE characterization simulates the netlist of the schematic, without the wire parasitics of
  the layout: OpenRAM extracts them with Calibre only (its KLayout interface has no extraction),
  which the machine lacks. Its delays are optimistic too, by the wire RC of the bitlines and
  wordlines.
- FreePDK45 is a research kit that cannot be fabricated, and its transistor models are predictive
  (PTM). The numbers compare designs; they are not silicon.

---
[← Back to synthesis](../../README.md)
