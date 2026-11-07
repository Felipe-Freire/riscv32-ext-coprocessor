// SPDX-License-Identifier: Apache-2.0
//
// spike_cosim_dpi.cc - SystemVerilog DPI-C binding for cosim::SpikeCosim.
//
// Design rules:
//   * C types match IEEE 1800 DPI mappings exactly (longint unsigned ->
//     unsigned long long, etc.) so simulator-generated headers agree.
//   * No C++ exception ever crosses the DPI boundary.
//   * A retirement is pushed field by field (begin / add_reg / set_mem /
//     commit). Adding a new field later (vector data, more CSRs, NRET > 1)
//     adds a function instead of breaking an existing signature.

#include <svdpi.h>

#include <cstdio>
#include <exception>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>

#include "spike_cosim_dpi.h"

namespace {

struct DpiHandle {
  explicit DpiHandle(const cosim::SpikeCosimConfig& config) : model(config) {}
  cosim::SpikeCosim model;
  cosim::RetireRecord record;
  bool record_open = false;
};

// A shared RAM handle owns one reference; regions mapped from it hold more,
// so destroying the handle before the cosim instances is safe.
struct RamHandle {
  std::shared_ptr<cosim::SparseRam> ram;
};

constexpr unsigned char kModeUnknown = 0xff;

void log_exception(const char* where) {
  try {
    throw;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "[spike_cosim] %s: %s\n", where, e.what());
  } catch (...) {
    std::fprintf(stderr, "[spike_cosim] %s: unknown exception\n", where);
  }
}

// Runs `body` on a valid handle of type H, converting exceptions into
// `fallback`.
template <typename H = DpiHandle, typename R, typename Fn>
R guarded(const char* where, void* handle, R fallback, Fn&& body) noexcept {
  if (handle == nullptr) {
    std::fprintf(stderr, "[spike_cosim] %s: null handle\n", where);
    return fallback;
  }
  try {
    return std::forward<Fn>(body)(*static_cast<H*>(handle));
  } catch (...) {
    log_exception(where);
    return fallback;
  }
}

template <typename Fn>
void guarded_void(const char* where, void* handle, Fn&& body) noexcept {
  guarded(where, handle, 0, [&](DpiHandle& h) {
    std::forward<Fn>(body)(h);
    return 0;
  });
}

bool parse_bool(const std::string& v) {
  if (v == "1" || v == "true" || v == "on") return true;
  if (v == "0" || v == "false" || v == "off") return false;
  throw std::invalid_argument("bad boolean '" + v + "'");
}

// Options: whitespace/comma separated key=value pairs, e.g.
//   "trace=spike.log pmp_regions=4 mtvec=0x80000000 check_mem=0"
void apply_options(cosim::SpikeCosimConfig& cfg, const std::string& text) {
  std::string normalized = text;
  for (char& c : normalized) {
    if (c == ',') c = ' ';
  }
  std::istringstream in(normalized);
  std::string token;
  while (in >> token) {
    const auto eq = token.find('=');
    if (eq == std::string::npos) {
      throw std::invalid_argument("option '" + token + "' is not key=value");
    }
    const std::string key = token.substr(0, eq);
    const std::string val = token.substr(eq + 1);
    const auto num = [&val] { return std::stoull(val, nullptr, 0); };

    if (key == "trace") cfg.trace_log_path = val;
    else if (key == "hart_id") cfg.hart_id = static_cast<uint32_t>(num());
    else if (key == "pmp_regions") cfg.pmp_regions = static_cast<uint32_t>(num());
    else if (key == "pmp_granularity") cfg.pmp_granularity = static_cast<uint32_t>(num());
    else if (key == "wfi_as_nop") cfg.wfi_as_nop = parse_bool(val);
    else if (key == "mtvec") cfg.mtvec = num();
    else if (key == "irq_mask") cfg.irq_mask = num();
    else if (key == "check_order") cfg.checks.order = parse_bool(val);
    else if (key == "check_insn") cfg.checks.insn = parse_bool(val);
    else if (key == "check_next_pc") cfg.checks.next_pc = parse_bool(val);
    else if (key == "check_mem") cfg.checks.mem = parse_bool(val);
    else if (key == "check_mode") cfg.checks.mode = parse_bool(val);
    else throw std::invalid_argument("unknown option '" + key + "'");
  }
}

cosim::RetireRecord& open_record(DpiHandle& h, const char* where) {
  if (!h.record_open) {
    throw std::logic_error(std::string(where) +
                           " called without spike_cosim_retire_begin");
  }
  return h.record;
}

}  // namespace

// --- C++ bridge (spike_cosim_dpi.h) -----------------------------------------
namespace cosim {

SpikeCosim& cosim_from_handle(void* handle) {
  if (!handle) throw std::invalid_argument("null spike_cosim handle");
  return static_cast<DpiHandle*>(handle)->model;
}

std::shared_ptr<SparseRam> ram_from_handle(void* handle) {
  if (!handle) throw std::invalid_argument("null shared RAM handle");
  return static_cast<RamHandle*>(handle)->ram;
}

}  // namespace cosim

extern "C" {

// --- Lifetime ---------------------------------------------------------------

void* spike_cosim_create(const char* isa, const char* priv,
                         unsigned long long reset_pc, const char* options) {
  try {
    cosim::SpikeCosimConfig cfg;
    if (isa && *isa) cfg.isa = isa;
    if (priv && *priv) cfg.priv = priv;
    cfg.reset_pc = reset_pc;
    if (options) apply_options(cfg, options);
    return new DpiHandle(cfg);
  } catch (...) {
    log_exception("spike_cosim_create");
    return nullptr;
  }
}

void spike_cosim_destroy(void* handle) {
  delete static_cast<DpiHandle*>(handle);
}

// --- Memory -----------------------------------------------------------------

int spike_cosim_add_region(void* handle, const char* name,
                           unsigned long long base, unsigned long long size,
                           svBit dut_driven) {
  return guarded("spike_cosim_add_region", handle, 0, [&](DpiHandle& h) {
    h.model.add_region(name ? name : "", base, size,
                       dut_driven ? cosim::MemKind::kDutDriven
                                  : cosim::MemKind::kModeled);
    return 1;
  });
}

int spike_cosim_write_mem_byte(void* handle, unsigned long long addr,
                               unsigned char data) {
  return guarded("spike_cosim_write_mem_byte", handle, 0, [&](DpiHandle& h) {
    return h.model.write_mem(addr, &data, 1) ? 1 : 0;
  });
}

// Maps a shared RAM (from spike_cosim_ram_create) into this hart's view.
int spike_cosim_add_shared_region(void* handle, const char* name,
                                  unsigned long long base,
                                  unsigned long long size, void* ram_handle,
                                  svBit dut_driven) {
  return guarded("spike_cosim_add_shared_region", handle, 0,
                 [&](DpiHandle& h) {
                   h.model.add_region(name ? name : "", base, size,
                                      dut_driven ? cosim::MemKind::kDutDriven
                                                 : cosim::MemKind::kModeled,
                                      cosim::ram_from_handle(ram_handle));
                   return 1;
                 });
}

void spike_cosim_flush_icache(void* handle) {
  guarded_void("spike_cosim_flush_icache", handle,
               [](DpiHandle& h) { h.model.flush_instruction_cache(); });
}

long long spike_cosim_load_binary(void* handle, const char* path,
                                  unsigned long long base) {
  return guarded("spike_cosim_load_binary", handle, -1LL, [&](DpiHandle& h) {
    return static_cast<long long>(h.model.load_binary(path ? path : "", base));
  });
}

// --- Shared RAM (SoC reference memory) ---------------------------------------
// Offsets are relative to the RAM, not to any hart's memory map.

void* spike_cosim_ram_create(unsigned long long size) {
  try {
    return new RamHandle{std::make_shared<cosim::SparseRam>(size)};
  } catch (...) {
    log_exception("spike_cosim_ram_create");
    return nullptr;
  }
}

void spike_cosim_ram_destroy(void* ram_handle) {
  delete static_cast<RamHandle*>(ram_handle);
}

// Byte-strobed write of up to 8 bytes, e.g. one AXI W beat from a monitor
// observing DMA / accelerator writes at the memory slave.
int spike_cosim_ram_write(void* ram_handle, unsigned long long offset,
                          unsigned long long data, unsigned char strobe) {
  return guarded<RamHandle>("spike_cosim_ram_write", ram_handle, 0,
                            [&](RamHandle& r) {
                              return r.ram->write_strobed(offset, data, strobe)
                                         ? 1
                                         : 0;
                            });
}

// Reads `len` (1..8) bytes little-endian into *data. Returns 1 on success.
int spike_cosim_ram_read(void* ram_handle, unsigned long long offset, int len,
                         unsigned long long* data) {
  return guarded<RamHandle>(
      "spike_cosim_ram_read", ram_handle, 0, [&](RamHandle& r) {
        if (len < 1 || len > 8) throw std::invalid_argument("len must be 1..8");
        uint8_t bytes[8] = {};
        if (!r.ram->peek(offset, static_cast<size_t>(len), bytes)) return 0;
        unsigned long long value = 0;
        for (int i = 0; i < len; ++i) {
          value |= static_cast<unsigned long long>(bytes[i]) << (8 * i);
        }
        *data = value;
        return 1;
      });
}

long long spike_cosim_ram_load_binary(void* ram_handle, const char* path,
                                      unsigned long long offset) {
  return guarded<RamHandle>(
      "spike_cosim_ram_load_binary", ram_handle, -1LL, [&](RamHandle& r) {
        return static_cast<long long>(
            cosim::load_binary(*r.ram, path ? path : "", offset));
      });
}

// --- Platform / CSRs --------------------------------------------------------

void spike_cosim_set_irq_lines(void* handle, unsigned long long mip) {
  guarded_void("spike_cosim_set_irq_lines", handle,
               [&](DpiHandle& h) { h.model.set_irq_lines(mip); });
}

unsigned long long spike_cosim_read_csr(void* handle, int csr) {
  return guarded("spike_cosim_read_csr", handle, 0ULL, [&](DpiHandle& h) {
    return static_cast<unsigned long long>(h.model.read_csr(csr));
  });
}

void spike_cosim_write_csr(void* handle, int csr, unsigned long long value) {
  guarded_void("spike_cosim_write_csr", handle,
               [&](DpiHandle& h) { h.model.write_csr(csr, value); });
}

void spike_cosim_set_csr_constant(void* handle, int csr,
                                  unsigned long long value) {
  guarded_void("spike_cosim_set_csr_constant", handle,
               [&](DpiHandle& h) { h.model.set_csr_constant(csr, value); });
}

void spike_cosim_add_volatile_csr(void* handle, int csr) {
  guarded_void("spike_cosim_add_volatile_csr", handle,
               [&](DpiHandle& h) { h.model.add_volatile_csr(csr); });
}

// WARL rule expressible from SV: legal = (spike_value & and_mask) | or_mask.
void spike_cosim_set_csr_warl_mask(void* handle, int csr,
                                   unsigned long long and_mask,
                                   unsigned long long or_mask) {
  guarded_void("spike_cosim_set_csr_warl_mask", handle, [&](DpiHandle& h) {
    h.model.set_csr_warl(csr, [and_mask, or_mask](uint64_t v) {
      return (v & and_mask) | or_mask;
    });
  });
}

// --- Retirement record ------------------------------------------------------

void spike_cosim_retire_begin(void* handle, unsigned long long order,
                              unsigned long long pc_rdata,
                              unsigned long long pc_wdata, unsigned int insn,
                              svBit trap, svBit intr, unsigned char mode) {
  guarded_void("spike_cosim_retire_begin", handle, [&](DpiHandle& h) {
    h.record.clear();
    h.record.order = order;
    h.record.pc = pc_rdata;
    h.record.next_pc = pc_wdata;
    h.record.insn = insn;
    h.record.trap = trap != 0;
    h.record.intr = intr != 0;
    if (mode != kModeUnknown) h.record.mode = mode;
    h.record_open = true;
  });
}

// file: 0 = x, 1 = f, 2 = v, 3 = csr (see cosim::RegFile).
void spike_cosim_retire_add_reg(void* handle, int file, int index,
                                unsigned long long value) {
  guarded_void("spike_cosim_retire_add_reg", handle, [&](DpiHandle& h) {
    if (file < 0 || file > 3) throw std::invalid_argument("bad register file");
    open_record(h, "spike_cosim_retire_add_reg")
        .reg_writes.push_back(cosim::RegWrite{static_cast<cosim::RegFile>(file),
                                              static_cast<uint32_t>(index),
                                              value});
  });
}

void spike_cosim_retire_set_mem(void* handle, unsigned long long addr,
                                unsigned int rmask, unsigned int wmask,
                                unsigned long long rdata,
                                unsigned long long wdata) {
  guarded_void("spike_cosim_retire_set_mem", handle, [&](DpiHandle& h) {
    open_record(h, "spike_cosim_retire_set_mem").mem =
        cosim::MemRecord{addr, rmask, wmask, rdata, wdata};
  });
}

void spike_cosim_retire_set_faults(void* handle, svBit fetch_fault,
                                   svBit mem_fault) {
  guarded_void("spike_cosim_retire_set_faults", handle, [&](DpiHandle& h) {
    auto& r = open_record(h, "spike_cosim_retire_set_faults");
    r.fetch_fault = fetch_fault != 0;
    r.mem_fault = mem_fault != 0;
  });
}

// Returns 1 if the record matched Spike, 0 otherwise (see get_error).
int spike_cosim_retire_commit(void* handle) {
  return guarded("spike_cosim_retire_commit", handle, 0, [&](DpiHandle& h) {
    const auto& r = open_record(h, "spike_cosim_retire_commit");
    h.record_open = false;
    return h.model.step(r) ? 1 : 0;
  });
}

// --- Results ----------------------------------------------------------------

int spike_cosim_num_errors(void* handle) {
  return guarded("spike_cosim_num_errors", handle, 0, [&](DpiHandle& h) {
    return static_cast<int>(h.model.errors().size());
  });
}

// Pointer stays valid until the next clear_errors/step call.
const char* spike_cosim_get_error(void* handle, int index) {
  return guarded("spike_cosim_get_error", handle,
                 static_cast<const char*>(""), [&](DpiHandle& h) {
                   const auto& errors = h.model.errors();
                   return (index >= 0 &&
                           static_cast<size_t>(index) < errors.size())
                              ? errors[index].c_str()
                              : "";
                 });
}

void spike_cosim_clear_errors(void* handle) {
  guarded_void("spike_cosim_clear_errors", handle,
               [](DpiHandle& h) { h.model.clear_errors(); });
}

unsigned long long spike_cosim_retired_count(void* handle) {
  return guarded("spike_cosim_retired_count", handle, 0ULL, [](DpiHandle& h) {
    return static_cast<unsigned long long>(h.model.retired_count());
  });
}

}  // extern "C"
