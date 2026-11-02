# Vendor IP

Third-party IP, kept unmodified, one directory per project (git submodules). Adapt it through
wrappers in [`rtl/`](../rtl/README.md) (for example `rtl/bus/`) instead of editing it, so it can be
updated by moving the submodule.

| Directory | Source | Version | License | File list | Used for |
|---|---|---|---|---|---|
| `axi/` | [pulp-platform/axi](https://github.com/pulp-platform/axi) | `v0.39.11` | Solderpad 0.51 | [`axi.f`](axi.f) | AXI4 and AXI4-Lite crossbars, bridges, `axi_to_mem`, request/response struct macros (`axi/typedef.svh`) |
| `common_cells/` | [pulp-platform/common_cells](https://github.com/pulp-platform/common_cells) | `v1.39.0` | Solderpad 0.51 | [`common_cells.f`](common_cells.f) | Dependency of `axi/` (FIFOs, arbiters, address decoders) |

The file lists sit next to the submodules, because the submodules stay unmodified. They follow the
`sources` order of each project's `Bender.yml`, without tests and simulation-only files.
`common_cells.f` also leaves out the deprecated cells and `clk_int_div`, `clk_int_div_static` and
`clk_mux_glitch_free`, which need `tech_cells_generic`; clock cells in this project go through `prim_`.

The simulation helpers in `axi/src` (`axi_test.sv`, `axi_sim_mem.sv`, …) are not listed: they
need [pulp-platform/common_verification](https://github.com/pulp-platform/common_verification),
to be added with the verification environment.

After cloning, fetch the submodules:

```bash
git submodule update --init
```

Adding a project:

```bash
git submodule add <url> vendor/<name>
```

Then check out a release tag inside it, add a row to the table above, write its file list
`vendor/<name>.f` and include it from [`rtl/rtl.f`](../rtl/rtl.f), before the blocks that wrap it.

---
[← Back to project root](../README.md)
