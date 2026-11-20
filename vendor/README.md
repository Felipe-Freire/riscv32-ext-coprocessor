# Vendor IP

Third-party IP, kept unmodified, one directory per project (git submodules). Adapt it through
wrappers in [`rtl/`](../rtl/README.md) (for example `rtl/bus/`) instead of editing it, so it can be
updated by moving the submodule.

| Directory | Source | Version | License | File list | Used for |
|---|---|---|---|---|---|
| `axi/` | [pulp-platform/axi](https://github.com/pulp-platform/axi) | `v0.39.11` | Solderpad 0.51 | [`axi.f`](axi.f), [`axi_sim.f`](axi_sim.f) | In [`rtl/bus`](../rtl/bus/README.md): `axi_xbar`, `axi_lite_xbar`, `axi_from_mem`, `axi_lite_from_mem`; request/response struct macros (`axi/typedef.svh`) in `soc_pkg`; `axi_to_mem` for the L2 banks. In simulation: random masters and slaves, memory model and crossbar monitor, and `axi_delayer` and `axi_lite_regs` as testbench models |
| `common_cells/` | [pulp-platform/common_cells](https://github.com/pulp-platform/common_cells) | `v1.39.0` | Solderpad 0.51 | [`common_cells.f`](common_cells.f) | Dependency of `axi/`; `cdc_fifo_gray` and `cdc_2phase` in `coproc_top`; `addr_decode` and `fifo_v3` in `rtl/bus` |
| `common_verification/` | [pulp-platform/common_verification](https://github.com/pulp-platform/common_verification) | `v0.2.5` | Solderpad 0.51 | [`common_verification.f`](common_verification.f) | Simulation only: `rand_id_queue_pkg` and clock/reset generators, needed by `axi_sim.f` |

The file lists sit next to the submodules, because the submodules stay unmodified. They follow the
`sources` order of each project's `Bender.yml`. The RTL lists (`axi.f`, `common_cells.f`) leave out
tests and simulation-only files.
`common_cells.f` also leaves out the deprecated cells and `clk_int_div`, `clk_int_div_static` and
`clk_mux_glitch_free`, which need `tech_cells_generic`; clock cells in this project go through `prim_`.

The simulation helpers of `axi/` (`axi_test.sv`, `axi_sim_mem.sv`, and `tb_axi_xbar_pkg.sv` from
its tests) are in [`axi_sim.f`](axi_sim.f), after [`common_verification.f`](common_verification.f),
which they need. Both lists are simulation only: testbenches get them through `SIM_FLIST_<block>`
in the top-level [`Makefile`](../Makefile), and synthesis never reads them
([`scripts/`](../scripts/README.md#simulation)).

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
