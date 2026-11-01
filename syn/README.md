# Synthesis

Inputs for the ASIC implementation flow: timing constraints and synthesis scripts. The PDK and the
synthesis tool are not chosen yet, so this directory is filled in once they are.

## Contents

| Path | Contents |
|---|---|
| [`constraints/`](constraints/) | SDC files, one per synthesis top: `soc_top` and out-of-context blocks such as the core |
| `<tool>/` | Flow scripts for one synthesis tool, added when the tool is chosen |

## Conventions

- Read the RTL through [`rtl/rtl.f`](../rtl/rtl.f), with the technology primitive list in place of
  `rtl/prim/prim.f`.
- PDK files and macro views stay outside the repository (they are usually under NDA). Scripts
  find them through an environment variable such as `PDK_ROOT`.
- Netlists, reports and logs go to `build/syn/`, never into this directory.
- Use the same tool version and options for every configuration you compare, so differences in
  area and timing come from the RTL.

---
[← Back to project root](../README.md)
