# OpenRAM SRAM macros (FreePDK45)

The SRAM macros of the SoC, generated with [OpenRAM](https://github.com/VLSIDA/OpenRAM) in its
`freepdk45` technology, which OpenRAM ships itself (bitcell, SPICE models, layers), so the FreePDK45
kit is not needed. They use the same layers as the NanGate cells of
[`lib/freepdk45`](../freepdk45/), so synthesis reads their Liberty and LEF next to the cells.

```bash
make venv                 # once: .venv with OpenRAM 1.2.48 (requirements.txt)
make openram              # every macro here -> lib/openram45/<macro>/ (git-ignored), 20 to 25 min each
make openram MACROS=sram_sp_2048x32_m8
```

Each `<macro>.py` here is an OpenRAM configuration, and its file name is the macro name.
[`openram45.mk`](openram45.mk) runs it with the OpenRAM of the venv. Logs and intermediate files
go to `build/openram/<macro>/`, and the target stops if a view is missing.

| File in `lib/openram45/<macro>/` | Use |
|---|---|
| `<macro>_TT_1p1V_25C.lib` | Timing and area for synthesis and STA |
| `<macro>.lef` | Abstract for the placement estimate (PLE) |
| `<macro>.v` | Behavioral model for simulation and gate level, written with `VERBOSE = 0` (the generated model prints every access otherwise) |
| `<macro>.gds`, `<macro>.sp`, `<macro>.html` | Layout, netlist, datasheet |

`syn/tech/tech.mk` lists the macros (`OPENRAM45_MACROS`, one per configuration) and gives their
views at `CORNER` as `MEM_LIBS`, `MEM_LEFS` and `MEM_MODELS`.

## Macros

| Macro | Words × bits | Ports | Area | Size | Used for |
|---|---|---|---|---|---|
| [`sram_sp_2048x32_m8`](sram_sp_2048x32_m8.py) | 2048 × 32 (8 KiB) | 1 read/write, byte write mask | 89 532 µm² | 232.4 × 385.2 µm | Tile of every SRAM: 4 deep per TCM, 4 wide per L2 bank (16 in the SoC) |

Ports of `sram_sp_2048x32_m8`, all sampled on the rising edge of `clk0`:

| Port | Bits | Description |
|---|---|---|
| `clk0` | 1 | Clock |
| `csb0` | 1 | Chip select, active low |
| `web0` | 1 | Write enable, active low (1: read) |
| `wmask0` | 4 | Byte write mask, active high |
| `addr0` | 11 | Word address |
| `din0`, `dout0` | 32 | Write data, read data |

The model writes and reads on the falling edge of the cycle that sampled the access. `dout0` is
valid 3 ns (`DELAY`) after that falling edge and turns X 1 ns (`T_HOLD`) after the next rising
edge. A clock period under 6 ns therefore needs a smaller `DELAY` in simulation, and a block that
needs the data for longer than one cycle registers it ([`prim_ram_1p`](../../../rtl/prim/README.md)).

## Timing: an analytical estimate

The configurations need no tool the machine lacks: no conda, no DRC/LVS (Magic, Netgen), and
OpenRAM's analytical model instead of a SPICE characterization. That model gives usable numbers
only at the typical corner:

| `sram_sp_2048x32_m8`, TT 1.1 V 25 °C | Value |
|---|---|
| `clk0` falling edge → `dout0` | 0.362 to 0.364 ns: the data is ready half a period plus 0.36 ns after the rising edge that sampled the read |
| Setup / hold of the inputs to the rising edge | 0.009 / 0.001 ns |
| Input capacitance | 0.21 fF per pin |
| Leakage | 0.067 mW |

At SS 0.95 V 125 °C the same model gives a negative `clk0` → `dout0` delay (−0.246 ns), and setup
and hold are the same at every corner. So only the TT Liberty file is generated, and the default
`CORNER` of FreePDK45 is `typical`, so the cells and the macros share their PVT. With
`CORNER=slow` or `fast` the cells change corner and the macros keep the TT file. Area, timing and
power of a design with these macros are estimates until the macros are characterized or the lab
libraries replace them.

## Pending

- **SPICE characterization** of `sram_sp_2048x32_m8` at TT, SS and FF (`analytical_delay = False`).
  ngspice would come from the conda that OpenRAM installs inside the project venv, with no system
  package. It runs once, in the background, since one macro tiles every SRAM. The `clk0` → `dout0`
  of the I-TCM is on the path into the ID stage of the core, so the final f_max figures need these
  files. With them, the default `CORNER` can go back to `slow`, with cells and macros at the same
  corner.
- The supplies are not routed and the pins are not on the edge of the macro (`route_supplies`,
  `perimeter_pins`), as in OpenRAM's own FreePDK45 example of this size. A place and route of the
  SoC would need both.

---
[← Back to synthesis](../../README.md)
