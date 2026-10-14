# Documentation

Index of all project documentation. Add a row here whenever you add a document.

## Specifications

Architecture and micro-architecture of the design, in [`spec/`](spec/).

| Document | Contents | Status |
|---|---|---|
| `spec/architecture.md` | System overview, block partitioning, memory map | Planned |
| `spec/core.md` | RV32 core micro-architecture: pipeline, hazards, CSRs | Planned |
| `spec/coproc.md` | Coprocessor micro-architecture: datapath, buffers, control | Planned |
| `spec/isa-extension.md` | Custom instruction encodings and semantics | Planned |

## Verification

Verification strategy and coverage goals, in [`verif/`](verif/).

| Document | Contents | Status |
|---|---|---|
| `verif/verification-plan.md` | Features to verify, test list, coverage model, sign-off criteria | Planned |

## Guides

How-to documents for working in this repository, in [`guides/`](guides/).

| Document | Contents | Status |
|---|---|---|
| `guides/setup.md` | Installing simulators, Verilator, Verible and the RISC-V toolchain | Planned |
| `guides/running-simulations.md` | Running tests, regressions and viewing waveforms | Planned |

## Figures

All images and diagrams live in [`figures/`](figures/). Nothing image-like goes anywhere else.

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
