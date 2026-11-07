# spike_cosim

Lock-step co-simulation of one RISC-V hart against Spike, driven by the
DUT's **RVFI** or **RVVI-TRACE** retirement stream. Derived from the lowRISC
Ibex cosim, with the generic `Cosim` interface and every Ibex-specific
feature removed.

| File | Role |
|---|---|
| `spike_cosim.h` | Public C++ API (no Spike headers leak out) |
| `spike_cosim.cc` | Spike-backed implementation (the only file that touches Spike) |
| `memory_device.h/.cc` | `MemoryDevice` interface + `SparseRam`; no Spike dependency |
| `spike_cosim_dpi.cc` | DPI-C binding, exception-safe |
| `spike_cosim_dpi.h` | C++ bridge: chandle → `SpikeCosim&` / `SparseRam` |
| `spike_cosim_pkg.sv` | SV package: DPI imports + `step_rvfi()` / `step_rvvi()` helpers |
| `Makefile` | Builds `libspike_cosim.so` |

## Two ways to use it

**1. Core alone** (UVM TB of the RISC-V core). Each region gets a private RAM:

```cpp
cosim::SpikeCosim hart(cfg);
hart.add_region("ram", 0x8000'0000, 1 << 20, cosim::MemKind::kModeled);
hart.add_region("mmio", 0x1000'0000, 0x1'0000, cosim::MemKind::kDutDriven);
hart.load_binary("prog.bin", 0x8000'0000);
```

**2. Inside the SoC reference model.** The SoC model owns the memories and
peripheral models and maps the *same objects* into the hart:

```cpp
auto ram      = std::make_shared<cosim::SparseRam>(1 << 20);   // shared
auto systolic = std::make_shared<SystolicModel>();             // : MemoryDevice
hart.add_region("ram",      0x8000'0000, 1 << 20, cosim::MemKind::kModeled,   ram);
hart.add_region("systolic", 0x2000'0000, 0x1000,  cosim::MemKind::kModeled,   systolic);
hart.add_region("uart",     0x1000'0000, 0x100,   cosim::MemKind::kDutDriven, uart_obs);
// DMA writes observed at the memory slave go into the same RAM:
ram->write_strobed(awaddr - 0x8000'0000, wdata, wstrb);
```

`MemoryDevice::load`/`store` are called from inside `step()` in program
order, so a store to the accelerator's START register reaches the model at
the right point. A `kDutDriven` region with a device attached forwards the
CPU's stores to it but still takes load data from the DUT. Use this while a
peripheral model can't predict read data yet. From SV, the same thing is
available as `spike_cosim_ram_*` and `spike_cosim_add_shared_region`. A C++
SoC model receiving those chandles uses `spike_cosim_dpi.h`.

The `SpikeCosim` API is identical in both setups; only who owns the devices
changes.

## Build

Requires **upstream riscv-isa-sim** (checked against master `c20813c`,
Nov 2026), installed with `make install`, and a C++20 compiler (Spike headers
require it).

```sh
make SPIKE_PREFIX=/opt/spike SVDPI_INCLUDE=$VCS_HOME/include
```

The lowRISC `ibex-cosim` Spike fork is **not** supported. It has a different
`processor_t` constructor and `simif_t`.

## What changed from the Ibex cosim

| Ibex cosim | spike_cosim |
|---|---|
| `Cosim` abstract base + `SpikeCosim` | single `cosim::SpikeCosim` (pimpl) |
| `step(write_reg, data, pc, sync_trap, suppress)` | `step(RetireRecord)`: RVFI/RVVI fields, multiple reg writes, CSR writes, mem |
| `notify_dside_access()` from a bus monitor | `RetireRecord::mem` (`rvfi_mem_*`), compared byte by byte |
| `set_iside_error()` | `RetireRecord::fetch_fault` / `mem_fault` |
| `set_mip(pre, post)` + early interrupt step | `set_irq_lines()` + interrupt taken when the DUT reports `intr` |
| `set_mcycle()` / `set_csr()` for counters | *volatile CSRs*: reads of cycle/time/hpm/mip take the DUT value |
| hard-coded `fixup_csr()` (mstatus, mtvec, …) | `set_csr_warl(csr, fn)` hooks |
| `last_inst_pc == PC_INVALID` (fork only) | trap detected from Spike's commit log (xEPC + xCAUSE written) |
| PC-range heuristic for iside vs dside | `simif_t::mmio_fetch` |
| NMI, debug ebreak, CPUCTRLSTS, icache scramble, integrity suppress, misaligned-PMP fixup | removed (Ibex-specific) |
| `riscv_cosim_*` DPI functions | `spike_cosim_*`: create/destroy, regions, retire builder |

## Integration contract

1. **Create and configure** (see the header of `spike_cosim_pkg.sv`):
   `spike_cosim_create(isa, priv, reset_pc, "trace=spike.log pmp_regions=0 ...")`.
   Add `_zicclsm` to the ISA string if the core handles misaligned accesses
   in hardware.
2. **Memory map**: one `add_region` per address range.
   * `kModeled` (`dut_driven = 0`): the reference provides the data (private
     RAM, shared RAM or a peripheral model). Load the same image into it as
     into the DUT.
   * `kDutDriven` (`dut_driven = 1`): the DUT provides load data
     (`rvfi_mem_rdata`), and stores are only checked. Use it for anything the
     reference doesn't model yet.
   * Memory written by DMA or by an accelerator can be either: `kDutDriven`,
     or `kModeled` on a shared RAM fed by a bus monitor at the memory slave.
     That keeps the real ordering between DMA writes and CPU loads.
3. **Interrupts**: call `spike_cosim_set_irq_lines(mip)` whenever MSIP, MTIP or
   MEIP change on the DUT, before committing the record that has
   `rvfi_intr`. Spike holds pending interrupts back until the DUT reports the
   handler entry, so pipeline latency does not cause false mismatches.
4. **Per retirement**: `step_rvfi(...)` (RVFI, NRET = 1) or `step_rvvi(...)`.
   For other shapes (CSR extension, NRET > 1, FP regs), use the builder
   `retire_begin` → `retire_add_reg`* → `retire_set_mem` →
   `retire_set_faults` → `retire_commit`. Errors carry
   `[order N pc 0x… insn 0x… (disasm)]` context; read them with
   `collect_errors()`.
5. **Core-specific behaviour**: `spike_cosim_set_csr_constant` (marchid,
   mimpid, misa), `spike_cosim_set_csr_warl_mask` (WARL legalisation),
   `spike_cosim_add_volatile_csr` (any extra non-deterministic CSR),
   `wfi_as_nop=1` if the core treats WFI as a NOP.

## Extending

* **Vector extension**: `RegFile::kVpr` records are already accepted, and the
  written register *indices* are compared. Comparing *values* needs a
  `check_vreg_write()` that reads `processor_t::VU` (Spike only logs the
  index).
* **SoC with several harts**: one `SpikeCosim` per hart (`hart_id` option),
  all mapping the same `SparseRam`.
* **Peripheral written in SV**: a `MemoryDevice` that calls exported SV
  functions (needs `context` on `spike_cosim_retire_commit`).
* **NRET > 1**: call the builder once per retire slot, in `order` sequence.
* **S-mode**: extend `interrupt_would_fire()` with `mideleg`/`sstatus.SIE`.

## Limitations

* Privilege modes M and U only for interrupt gating; debug mode and NMI are
  not modelled.
* Data accesses are not compared on trapping instructions.
* LR/SC reservations aren't cleared by another hart's or DMA's store to a
  shared RAM.
* Spike caches fetched instructions: after changing code through a shared
  device without a `fence.i`, call `flush_instruction_cache()`.
* RVVI has no memory fields, so with `step_rvvi` loads and stores are not
  compared and `kDutDriven` loads have no data source.
