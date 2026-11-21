// SPDX-License-Identifier: Apache-2.0
//
// spike_cosim.h - Lock-step co-simulation of one RISC-V hart against Spike.
//
// Derived from the lowRISC Ibex co-simulator, reworked to be:
//   * DUT-agnostic : the DUT is described only by retirement records that map
//                    1:1 onto RVFI (riscv-formal) or RVVI-TRACE signals.
//   * Spike-isolated: no Spike header leaks out of spike_cosim.cc (Spike
//                    defines short global macros such as P, STATE and MMU).
//   * SoC-ready    : memory is a list of named regions backed by
//                    cosim::MemoryDevice objects. Stand-alone, each region
//                    gets a private RAM; inside a SoC reference model the
//                    same RAM / peripheral models are shared with DMA,
//                    accelerators and other harts (see memory_device.h).
//
// Typical flow (per retired instruction reported by the DUT):
//
//   cosim::SpikeCosim ref(cfg);
//   ref.add_region("ram",  0x8000'0000, 0x10'0000, cosim::MemKind::kModeled);
//   ref.add_region("mmio", 0x1000'0000, 0x1000,    cosim::MemKind::kDutDriven);
//   ref.load_binary("prog.bin", 0x8000'0000);
//   ...
//   ref.set_irq_lines(mip_from_dut);            // whenever IRQ lines change
//   if (!ref.step(record)) report(ref.errors());
//
// Known limitations (see README.md for details):
//   * Privilege modes M and U only (no S-mode interrupt delegation).
//   * Debug mode, NMI and vector-register *values* are not checked yet.

#ifndef COSIM_SPIKE_COSIM_H_
#define COSIM_SPIKE_COSIM_H_

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "memory_device.h"

namespace cosim {

// ---------------------------------------------------------------------------
// Retirement record: what the DUT reports for one instruction.
// ---------------------------------------------------------------------------

enum class RegFile : uint8_t {
  kGpr = 0,  // x0..x31   (x0 writes are ignored)
  kFpr = 1,  // f0..f31
  kVpr = 2,  // v0..v31   (index-only check for now)
  kCsr = 3,  // 12-bit CSR address
};

struct RegWrite {
  RegFile file = RegFile::kGpr;
  uint32_t index = 0;
  uint64_t value = 0;
};

// One data-memory access, RVFI `rvfi_mem_*` semantics. Byte i of the masks /
// data refers to address `addr + i`, so both RVFI conventions (aligned
// address + shifted mask, or raw address + mask from bit 0) are accepted.
struct MemRecord {
  uint64_t addr = 0;
  uint32_t rmask = 0;
  uint32_t wmask = 0;
  uint64_t rdata = 0;
  uint64_t wdata = 0;
};

struct RetireRecord {
  uint64_t order = 0;               // rvfi_order
  uint64_t pc = 0;                  // rvfi_pc_rdata
  std::optional<uint64_t> next_pc;  // rvfi_pc_wdata (checked when !trap)
  uint32_t insn = 0;                // rvfi_insn (16-bit insns in low half)
  bool trap = false;                // rvfi_trap: sync exception, not retired
  bool intr = false;                // rvfi_intr: first insn of a trap handler
  std::optional<uint8_t> mode;      // rvfi_mode (privilege when executed)

  std::vector<RegWrite> reg_writes;  // RVFI: 0..1 entry; RVVI: x_wb/f_wb/...
  std::optional<MemRecord> mem;      // absent => memory not checked

  // Bus-error responses seen by the DUT for this instruction. Spike is told
  // to raise the matching access fault.
  bool fetch_fault = false;
  bool mem_fault = false;

  void clear() { *this = RetireRecord{}; }
};

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

enum class MemKind : uint8_t {
  // The reference provides the data: loads/fetches/stores go to the region's
  // MemoryDevice (a private SparseRam if none is given, or a RAM/peripheral
  // model owned by the SoC reference model). Load data is compared against
  // the DUT.
  kModeled,
  // The DUT provides the data: load data is taken from the DUT record (for
  // regions nobody models yet: MMIO, accelerator results...). Fetches fault.
  // If a device is attached it still receives the CPU's stores, so a SoC
  // model can observe CPU programming without predicting read data.
  kDutDriven,
};

struct CheckOptions {
  bool order = true;    // rvfi_order must be consecutive
  bool insn = true;     // DUT insn bits == bits in Spike memory at pc
  bool next_pc = true;  // rvfi_pc_wdata == Spike pc after the step
  bool mem = true;      // data accesses (address, mask, data)
  bool mode = true;     // privilege level
};

struct SpikeCosimConfig {
  // Spike --isa string. Add "_zicclsm" if the DUT handles misaligned
  // loads/stores in hardware instead of trapping.
  std::string isa = "rv32im_zicsr_zifencei";
  std::string priv = "MU";                    // Spike --priv string
  uint64_t reset_pc = 0x8000'0000;
  std::optional<uint64_t> mtvec;              // initial mtvec, if any
  uint32_t hart_id = 0;
  uint32_t pmp_regions = 0;                   // 0 = no PMP
  uint32_t pmp_granularity = 4;               // bytes, power of two >= 4
  bool wfi_as_nop = false;                    // must match the DUT
  // mip bits driven by the platform (default MSIP | MTIP | MEIP).
  uint64_t irq_mask = (1u << 3) | (1u << 7) | (1u << 11);
  std::string trace_log_path;                 // empty => no Spike trace
  CheckOptions checks;
};

// ---------------------------------------------------------------------------
// SpikeCosim
// ---------------------------------------------------------------------------

class SpikeCosim {
 public:
  // Maps the value Spike wrote to a CSR onto the value the DUT would hold
  // (WARL legalisation differences). Applied after every CSR write.
  using CsrWarlFn = std::function<uint64_t(uint64_t spike_value)>;

  explicit SpikeCosim(const SpikeCosimConfig& config);
  ~SpikeCosim();
  SpikeCosim(SpikeCosim&&) noexcept;
  SpikeCosim& operator=(SpikeCosim&&) noexcept;
  SpikeCosim(const SpikeCosim&) = delete;
  SpikeCosim& operator=(const SpikeCosim&) = delete;

  // --- Memory map ----------------------------------------------------------
  // Maps [base, base + size) to offset 0 of `device`. For kModeled with no
  // device, a private SparseRam is created (core-only TB). Throws
  // std::invalid_argument on overlap, bad size or size > device->size().
  void add_region(const std::string& name, uint64_t base, uint64_t size,
                  MemKind kind,
                  std::shared_ptr<MemoryDevice> device = nullptr);
  // Backdoor access to kModeled regions (reads use MemoryDevice::peek).
  // Return false if unmapped or not modeled.
  bool write_mem(uint64_t addr, const uint8_t* data, size_t len);
  bool read_mem(uint64_t addr, uint8_t* data, size_t len);
  // Loads a flat binary image; returns bytes written. Throws on failure.
  size_t load_binary(const std::string& path, uint64_t base);
  // Spike caches decoded instructions. Call after code memory was changed
  // directly through a shared device (write_mem() already does this).
  void flush_instruction_cache();

  // --- Platform inputs -----------------------------------------------------
  // Current level of the platform interrupt lines in mip layout (masked by
  // config.irq_mask). Call whenever they change, before the next step().
  void set_irq_lines(uint64_t mip);

  // --- CSR control ---------------------------------------------------------
  uint64_t read_csr(int csr);              // throws if not implemented
  void write_csr(int csr, uint64_t value);  // throws if not implemented
  void set_csr_constant(int csr, uint64_t value);  // e.g. marchid, mimpid
  // Reads of a volatile CSR take the DUT's value (cycle/time/hpm counters,
  // mip). A default set is installed by the constructor.
  void add_volatile_csr(int csr);
  void set_csr_warl(int csr, CsrWarlFn fn);

  // --- Lock-step -----------------------------------------------------------
  // Advances Spike by one DUT retirement record and checks it. Returns false
  // if any mismatch was found; details via errors().
  bool step(const RetireRecord& record);

  // --- Results / introspection --------------------------------------------
  const std::vector<std::string>& errors() const;
  void clear_errors();
  uint64_t retired_count() const;  // non-trapping records that matched
  uint64_t pc() const;
  uint64_t read_gpr(unsigned index) const;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace cosim

#endif  // COSIM_SPIKE_COSIM_H_
