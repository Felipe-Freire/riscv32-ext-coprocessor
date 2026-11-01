# Documentation

Index of all project documentation. Add a row here whenever you add a document.

## Specifications

The specification lives in the READMEs next to the RTL, so it changes together with the code:

| Topic | Location |
|---|---|
| Memory map, matrix buffers, interrupts, clocks, interfaces between blocks | [`rtl/top/`](../rtl/top/README.md) |
| Core: instructions, CSRs, traps, ports | [`rtl/core/`](../rtl/core/README.md) |
| DMA: channels, registers, ports | [`rtl/dma/`](../rtl/dma/README.md) |
| Coprocessor: operation, matrix layout, registers, ports | [`rtl/coproc/`](../rtl/coproc/README.md) |
| Timer registers | [`rtl/periph/`](../rtl/periph/README.md) |
| Boot and matrix multiplication sequence from the core | [`sw/`](../sw/README.md) |

Longer micro-architecture documents, if needed later, go in [`spec/`](spec/).

## Verification

Verification strategy and coverage goals, in [`verif/`](verif/).

| Document | Contents | Status |
|---|---|---|
| `verif/verification-plan.md` | Features to verify, test list, coverage model, sign-off criteria | Planned |

## Guides

How-to documents for working in this repository, in [`guides/`](guides/).

| Document | Contents | Status |
|---|---|---|
| `guides/setup.md` | Installing the simulator and the RISC-V toolchain | Planned |
| `guides/running-simulations.md` | Running tests, regressions and viewing waveforms | Planned |

## Figures

All images and diagrams live in [`figures/`](figures/). Nothing image-like goes anywhere else.

| Figure | Contents |
|---|---|
| [`soc-top-level`](figures/soc-top-level.svg) | SoC blocks and how they connect (root README figure) |
| [`soc-architecture`](figures/soc-architecture.svg) | SoC detail: CPU subsystem, buses, DMA, coprocessor, clock domains |
| [`core-datapath`](figures/core-datapath.svg) | Core 5-stage pipeline datapath |

- **Name:** `<area>-<subject>.<ext>`, e.g. `core-pipeline.svg`, `coproc-mac-array.svg`.
- **Format:** prefer SVG. Use PNG only for screenshots (e.g. waveform captures).
- **Keep the source editable:** commit the source next to the export with the same base name
  (`coproc-fsm.drawio` + `coproc-fsm.svg`). Alternatively, save draw.io diagrams as `.drawio.svg`:
  the same file renders on GitHub and opens in draw.io for editing.
- **Timing diagrams:** write them in [WaveDrom](https://wavedrom.com) JSON (`<name>.wavedrom.json`)
  and export to SVG.
- **Background:** use an opaque white background so figures stay readable in GitHub dark mode.
- **Links:** always relative to the file doing the linking, e.g. from `rtl/README.md`:
  `![Pipeline](../docs/figures/core-pipeline.svg)`.

---
[← Back to project root](../README.md)
