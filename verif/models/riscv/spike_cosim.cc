// SPDX-License-Identifier: Apache-2.0
//
// spike_cosim.cc - Spike-backed implementation of cosim::SpikeCosim.
//
// Every Spike API dependency lives in this file. Target: upstream
// riscv-isa-sim master (checked against c20813c, Nov 2026): processor_t(isa,
// priv, cfg, ...), simif_t with mmio_fetch/get_cfg/get_harts. Spike headers
// need C++20.

#include "spike_cosim.h"

#include <cinttypes>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <unordered_map>
#include <unordered_set>
#include <utility>

#include "riscv/cfg.h"
#include "riscv/decode.h"
#include "riscv/disasm.h"
#include "riscv/encoding.h"
#include "riscv/log_file.h"
#include "riscv/mmu.h"
#include "riscv/processor.h"
#include "riscv/simif.h"
#include "riscv/trap.h"

namespace cosim {
namespace {

// Spike commit-log keys are (index << 4) | type.
constexpr unsigned kLogGpr = 0;
constexpr unsigned kLogFpr = 1;
constexpr unsigned kLogVpr = 2;
constexpr unsigned kLogCsr = 4;


using ByteMap = std::map<uint64_t, uint8_t>;  // address -> byte

std::string hex(uint64_t value) {
  char buf[24];
  std::snprintf(buf, sizeof(buf), "0x%" PRIx64, value);
  return buf;
}

std::string describe(const ByteMap& bytes) {
  if (bytes.empty()) return "{}";
  std::ostringstream os;
  os << '{';
  const char* sep = "";
  for (const auto& [addr, data] : bytes) {
    os << sep << hex(addr) << ':' << hex(data);
    sep = " ";
  }
  os << '}';
  return os.str();
}

void add_bytes(ByteMap& out, uint64_t addr, uint32_t mask, uint64_t data) {
  for (unsigned i = 0; i < 8; ++i) {
    if ((mask >> i) & 1u) out[addr + i] = static_cast<uint8_t>(data >> (8 * i));
  }
}

// Zicsr instruction fields; nullopt for anything else.
struct CsrInsn {
  int csr;
  unsigned rd;
};
std::optional<CsrInsn> decode_csr_insn(uint32_t insn) {
  constexpr uint32_t kOpcodeSystem = 0x73;
  const uint32_t funct3 = (insn >> 12) & 0x7;
  if ((insn & 0x7f) != kOpcodeSystem || funct3 == 0 || funct3 == 4) {
    return std::nullopt;
  }
  return CsrInsn{static_cast<int>(insn >> 20), (insn >> 7) & 0x1f};
}

const char* reg_prefix(RegFile file) {
  switch (file) {
    case RegFile::kGpr: return "x";
    case RegFile::kFpr: return "f";
    case RegFile::kVpr: return "v";
    case RegFile::kCsr: return "csr ";
  }
  return "?";
}

struct MemRegion {
  std::string name;
  uint64_t base;
  uint64_t size;
  MemKind kind;
  std::shared_ptr<MemoryDevice> device;  // never null for kModeled
  uint64_t offset(uint64_t addr) const { return addr - base; }
  bool contains(uint64_t addr, size_t len) const {
    return addr >= base && len <= size && addr - base <= size - len;
  }
};

}  // namespace

// ===========================================================================
// SpikeCosim::Impl - the simif_t Spike talks to.
// ===========================================================================
class SpikeCosim::Impl final : public simif_t {
 public:
  explicit Impl(const SpikeCosimConfig& config);

  // --- simif_t --------------------------------------------------------------
  // nullptr everywhere: every access goes through mmio_* so it can be checked.
  char* addr_to_mem(reg_t) override { return nullptr; }
  bool reservable(reg_t paddr) override;
  bool mmio_fetch(reg_t paddr, size_t len, uint8_t* bytes) override;
  bool mmio_load(reg_t paddr, size_t len, uint8_t* bytes) override;
  bool mmio_store(reg_t paddr, size_t len, const uint8_t* bytes) override;
  void proc_reset(unsigned) override {}
  const cfg_t& get_cfg() const override { return cfg_; }
  const std::map<size_t, processor_t*>& get_harts() const override {
    return harts_;
  }
  const char* get_symbol(uint64_t) override { return nullptr; }

  // --- API backing SpikeCosim ----------------------------------------------
  void add_region(const std::string& name, uint64_t base, uint64_t size,
                  MemKind kind, std::shared_ptr<MemoryDevice> device);
  bool write_mem(uint64_t addr, const uint8_t* data, size_t len);
  bool read_mem(uint64_t addr, uint8_t* data, size_t len);
  void flush_instruction_cache() { processor_->get_mmu()->flush_icache(); }
  void set_irq_lines(uint64_t mip) { irq_lines_ = mip & config_.irq_mask; }
  uint64_t read_csr(int csr);
  void write_csr(int csr, uint64_t value);
  void set_csr_constant(int csr, uint64_t value);
  void add_volatile_csr(int csr) { volatile_csrs_.insert(csr); }
  void set_csr_warl(int csr, CsrWarlFn fn) { csr_warl_[csr] = std::move(fn); }
  bool step(const RetireRecord& record);

  std::vector<std::string> errors_;
  uint64_t retired_count_ = 0;

  state_t& state() const { return *processor_->get_state(); }
  uint64_t xlen_mask() const { return xlen_mask_; }

 private:
  // Binds the record being checked for the duration of step().
  class RecordScope {
   public:
    RecordScope(Impl& impl, const RetireRecord& record);
    ~RecordScope();
    RecordScope(const RecordScope&) = delete;
    RecordScope& operator=(const RecordScope&) = delete;

   private:
    Impl& impl_;
  };

  template <typename... Args>
  void fail(const Args&... args);
  std::string context() const;

  const MemRegion* find_region(uint64_t addr, size_t len) const;
  void install_default_volatile_csrs();

  void execute_one(bool inject_fetch_fault);
  bool reference_took_trap() const;
  bool interrupt_would_fire(uint64_t mip) const;
  void expose_irq_lines();
  bool take_interrupt();

  void check_order(const RetireRecord& r);
  void check_insn(const RetireRecord& r);
  void patch_volatile_csr_read(const RetireRecord& r);
  void apply_csr_warl();
  void check_reg_writes(const RetireRecord& r);
  void check_mem();

  // Construction order matters: processor_ (last) references the others.
  const SpikeCosimConfig config_;
  cfg_t cfg_;
  log_file_t log_;
  std::vector<MemRegion> regions_;
  std::map<size_t, processor_t*> harts_;
  std::unique_ptr<processor_t> processor_;
  uint64_t xlen_mask_ = ~uint64_t{0};

  std::unordered_set<int> volatile_csrs_;
  std::unordered_map<int, CsrWarlFn> csr_warl_;
  uint64_t irq_lines_ = 0;

  // Per-record state.
  const RetireRecord* current_ = nullptr;
  bool inject_fetch_fault_ = false;
  ByteMap dut_reads_, dut_writes_;  // from the DUT record
  ByteMap ref_reads_, ref_writes_;  // observed from Spike during the step
  bool prev_was_trap_ = false;
  std::optional<uint64_t> expected_order_;
};

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------
SpikeCosim::Impl::Impl(const SpikeCosimConfig& config)
    : config_(config),
      // Commit logging must be on (it is how register writes and traps are
      // observed) and Spike then needs a real FILE*.
      log_(config.trace_log_path.empty() ? "/dev/null"
                                         : config.trace_log_path.c_str()) {
  const uint32_t g = config_.pmp_granularity;
  if (g < 4 || (g & (g - 1)) != 0) {
    throw std::invalid_argument("pmp_granularity must be a power of two >= 4");
  }

  cfg_.isa = config_.isa.c_str();
  cfg_.priv = config_.priv.c_str();
  cfg_.wfi_as_nop = config_.wfi_as_nop;
  cfg_.pmpregions = config_.pmp_regions;
  cfg_.pmpgranularity = g;
  cfg_.hartids = {config_.hart_id};
  cfg_.explicit_hartids = true;

  // Only Spike-version-specific call in the file.
  processor_ = std::make_unique<processor_t>(
      cfg_.isa, cfg_.priv, &cfg_, this, config_.hart_id,
      /*halt_on_reset=*/false, log_.get(), std::cerr);
  harts_[config_.hart_id] = processor_.get();
  processor_->enable_log_commits();

  xlen_mask_ = processor_->get_xlen() == 32 ? 0xffff'ffffull : ~uint64_t{0};
  state().pc = config_.reset_pc;
  if (config_.mtvec) state().mtvec->write(*config_.mtvec);

  install_default_volatile_csrs();
}

void SpikeCosim::Impl::install_default_volatile_csrs() {
  for (int csr : {CSR_MCYCLE, CSR_MCYCLEH, CSR_CYCLE, CSR_CYCLEH, CSR_TIME,
                  CSR_TIMEH, CSR_MIP}) {
    volatile_csrs_.insert(csr);
  }
  for (int i = 0; i < 29; ++i) {  // hpm counters 3..31
    for (int base : {CSR_MHPMCOUNTER3, CSR_MHPMCOUNTER3H, CSR_HPMCOUNTER3,
                     CSR_HPMCOUNTER3H}) {
      volatile_csrs_.insert(base + i);
    }
  }
}

// ---------------------------------------------------------------------------
// Error reporting
// ---------------------------------------------------------------------------
template <typename... Args>
void SpikeCosim::Impl::fail(const Args&... args) {
  std::ostringstream os;
  os << context();
  (os << ... << args);
  errors_.push_back(os.str());
}

std::string SpikeCosim::Impl::context() const {
  if (!current_) return "";
  std::ostringstream os;
  os << "[order " << current_->order << " pc " << hex(current_->pc);
  if (!current_->fetch_fault) {
    os << " insn " << hex(current_->insn) << " ("
       << processor_->get_disassembler()->disassemble(insn_t(current_->insn))
       << ")";
  }
  os << "] ";
  return os.str();
}

// ---------------------------------------------------------------------------
// Memory
// ---------------------------------------------------------------------------
void SpikeCosim::Impl::add_region(const std::string& name, uint64_t base,
                                  uint64_t size, MemKind kind,
                                  std::shared_ptr<MemoryDevice> device) {
  if (size == 0 || base + (size - 1) < base) {
    throw std::invalid_argument("region '" + name + "': bad size");
  }
  for (const MemRegion& r : regions_) {
    if (base < r.base + r.size && r.base < base + size) {
      throw std::invalid_argument("region '" + name + "' overlaps '" +
                                  r.name + "'");
    }
  }
  if (kind == MemKind::kModeled && !device) {
    device = std::make_shared<SparseRam>(size);  // core-only TB
  }
  if (device && size > device->size()) {
    throw std::invalid_argument("region '" + name +
                                "' is larger than its device");
  }
  regions_.push_back(MemRegion{name, base, size, kind, std::move(device)});
}

const MemRegion* SpikeCosim::Impl::find_region(uint64_t addr,
                                               size_t len) const {
  for (const MemRegion& r : regions_) {
    if (r.contains(addr, len)) return &r;
  }
  return nullptr;
}

bool SpikeCosim::Impl::write_mem(uint64_t addr, const uint8_t* data,
                                 size_t len) {
  const MemRegion* r = find_region(addr, len);
  if (!r || r->kind != MemKind::kModeled) return false;
  if (!r->device->store(r->offset(addr), len, data)) return false;
  flush_instruction_cache();  // code may have changed
  return true;
}

bool SpikeCosim::Impl::read_mem(uint64_t addr, uint8_t* data, size_t len) {
  const MemRegion* r = find_region(addr, len);
  return r && r->kind == MemKind::kModeled &&
         r->device->peek(r->offset(addr), len, data);
}

bool SpikeCosim::Impl::reservable(reg_t paddr) {
  const MemRegion* r = find_region(paddr, 1);
  return r && r->kind == MemKind::kModeled;
}

bool SpikeCosim::Impl::mmio_fetch(reg_t paddr, size_t len, uint8_t* bytes) {
  if (inject_fetch_fault_) return false;
  const MemRegion* r = find_region(paddr, len);
  return r && r->kind == MemKind::kModeled &&
         r->device->load(r->offset(paddr), len, bytes);
}

bool SpikeCosim::Impl::mmio_load(reg_t paddr, size_t len, uint8_t* bytes) {
  if (current_ && current_->mem_fault) return false;
  const MemRegion* r = find_region(paddr, len);
  if (!r) return false;  // unmapped => access fault

  if (r->kind == MemKind::kModeled) {
    if (!r->device->load(r->offset(paddr), len, bytes)) return false;
  } else {
    for (size_t i = 0; i < len; ++i) {
      const auto it = dut_reads_.find(paddr + i);
      if (it == dut_reads_.end()) {
        fail("Spike loaded ", hex(paddr + i), " in DUT-driven region '",
             r->name, "' but the DUT record carries no read data for it");
        bytes[i] = 0;
      } else {
        bytes[i] = it->second;
      }
    }
  }
  for (size_t i = 0; i < len; ++i) ref_reads_[paddr + i] = bytes[i];
  return true;
}

bool SpikeCosim::Impl::mmio_store(reg_t paddr, size_t len,
                                  const uint8_t* bytes) {
  if (current_ && current_->mem_fault) return false;
  const MemRegion* r = find_region(paddr, len);
  if (!r) return false;
  // kDutDriven regions forward stores to an attached device (observer).
  if (r->device && !r->device->store(r->offset(paddr), len, bytes)) {
    return false;
  }
  for (size_t i = 0; i < len; ++i) ref_writes_[paddr + i] = bytes[i];
  return true;
}

// ---------------------------------------------------------------------------
// CSRs
// ---------------------------------------------------------------------------
uint64_t SpikeCosim::Impl::read_csr(int csr) {
  try {
    return processor_->get_csr(csr) & xlen_mask_;
  } catch (const trap_t&) {
    throw std::invalid_argument("CSR " + hex(csr) + " not implemented");
  }
}

void SpikeCosim::Impl::write_csr(int csr, uint64_t value) {
  try {
    processor_->put_csr(csr, value);
  } catch (const trap_t&) {
    throw std::invalid_argument("CSR " + hex(csr) + " not implemented");
  }
}

void SpikeCosim::Impl::set_csr_constant(int csr, uint64_t value) {
  state().csrmap[csr] =
      std::make_shared<const_csr_t>(processor_.get(), csr, value);
}

// ---------------------------------------------------------------------------
// Stepping primitives
// ---------------------------------------------------------------------------
SpikeCosim::Impl::RecordScope::RecordScope(Impl& impl,
                                           const RetireRecord& record)
    : impl_(impl) {
  impl_.current_ = &record;
  impl_.dut_reads_.clear();
  impl_.dut_writes_.clear();
  if (record.mem) {
    add_bytes(impl_.dut_reads_, record.mem->addr, record.mem->rmask,
              record.mem->rdata);
    add_bytes(impl_.dut_writes_, record.mem->addr, record.mem->wmask,
              record.mem->wdata);
  }
}

SpikeCosim::Impl::RecordScope::~RecordScope() {
  impl_.current_ = nullptr;
  impl_.inject_fetch_fault_ = false;
}

void SpikeCosim::Impl::execute_one(bool inject_fetch_fault) {
  state().log_reg_write.clear();
  ref_reads_.clear();
  ref_writes_.clear();
  if (inject_fetch_fault) processor_->get_mmu()->flush_icache();
  inject_fetch_fault_ = inject_fetch_fault;
  processor_->step(1);
  inject_fetch_fault_ = false;
}

// Spike's step(1) either retires one instruction or takes one trap. A trap is
// the only event that writes both xEPC and xCAUSE in the same step.
bool SpikeCosim::Impl::reference_took_trap() const {
  const auto& log = state().log_reg_write;
  auto logged = [&log](int csr) {
    return log.count((static_cast<reg_t>(csr) << 4) | kLogCsr) != 0;
  };
  return (logged(CSR_MEPC) && logged(CSR_MCAUSE)) ||
         (logged(CSR_SEPC) && logged(CSR_SCAUSE));
}

bool SpikeCosim::Impl::interrupt_would_fire(uint64_t mip) const {
  const state_t& s = state();
  if (s.debug_mode) return false;
  if ((mip & s.mie->read() & config_.irq_mask) == 0) return false;
  if (s.prv < PRV_M) return true;  // M-level IRQs always enabled below M
  return (s.mstatus->read() & MSTATUS_MIE) != 0;
}

// Spike takes an enabled interrupt at the very next step, whereas a pipelined
// DUT may retire a few more instructions first. Pending-and-enabled lines are
// therefore hidden from Spike until the DUT reports the handler entry.
// Software reads of mip are unaffected because mip is a volatile CSR.
void SpikeCosim::Impl::expose_irq_lines() {
  uint64_t visible = irq_lines_;
  if (interrupt_would_fire(visible)) visible &= ~state().mie->read();
  state().mip->backdoor_write_with_mask(config_.irq_mask, visible);
}

bool SpikeCosim::Impl::take_interrupt() {
  state_t& s = state();
  const uint64_t mie = s.mie->read();
  const uint64_t mstatus = s.mstatus->read();
  s.mip->backdoor_write_with_mask(config_.irq_mask, irq_lines_);
  execute_one(/*inject_fetch_fault=*/false);

  if (!reference_took_trap()) {
    fail("DUT entered an interrupt handler but Spike had no pending enabled "
         "interrupt (irq lines ", hex(irq_lines_), ", mie ", hex(mie),
         ", mstatus ", hex(mstatus), "); was set_irq_lines() called?");
    return false;
  }
  const uint64_t mcause = s.mcause->read();
  const unsigned xlen = processor_->get_xlen();
  if (((mcause >> (xlen - 1)) & 1) == 0) {
    fail("DUT took an interrupt but Spike took exception mcause ", hex(mcause));
    return false;
  }
  apply_csr_warl();
  return true;
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------
void SpikeCosim::Impl::check_order(const RetireRecord& r) {
  if (config_.checks.order && expected_order_ && r.order != *expected_order_) {
    fail("retirement order gap: expected ", *expected_order_, ", got ",
         r.order);
  }
  expected_order_ = r.order + 1;
}

void SpikeCosim::Impl::check_insn(const RetireRecord& r) {
  uint8_t buf[4] = {};
  if (!read_mem(r.pc, buf, 2)) return;  // not in modeled memory
  const size_t len = insn_length(buf[0]);  // Spike macro
  if (len > 4) return;                     // 48/64-bit encodings: not used
  if (len == 4 && !read_mem(r.pc + 2, buf + 2, 2)) return;
  uint32_t mem_insn = 0;
  for (size_t i = 0; i < len; ++i) mem_insn |= uint32_t{buf[i]} << (8 * i);
  const uint32_t mask = len == 4 ? 0xffff'ffffu : 0xffffu;
  if ((r.insn & mask) != mem_insn) {
    fail("instruction bits differ: DUT ", hex(r.insn & mask),
         ", Spike memory ", hex(mem_insn));
  }
}

// The DUT's value wins for reads of volatile CSRs (counters, mip).
void SpikeCosim::Impl::patch_volatile_csr_read(const RetireRecord& r) {
  const auto csr_insn = decode_csr_insn(r.insn);
  if (!csr_insn || csr_insn->rd == 0 || !volatile_csrs_.count(csr_insn->csr)) {
    return;
  }
  for (const RegWrite& w : r.reg_writes) {
    if (w.file == RegFile::kGpr && w.index == csr_insn->rd) {
      state().XPR.write(csr_insn->rd, w.value);
      auto it = state().log_reg_write.find(reg_t{csr_insn->rd} << 4);
      if (it != state().log_reg_write.end()) it->second.v[0] = w.value;
      return;
    }
  }
  // Missing DUT write is reported by check_reg_writes().
}

void SpikeCosim::Impl::apply_csr_warl() {
  if (csr_warl_.empty()) return;
  std::vector<std::pair<int, uint64_t>> writes;
  for (const auto& [key, value] : state().log_reg_write) {
    if ((key & 0xf) == kLogCsr) {
      writes.emplace_back(static_cast<int>(key >> 4), value.v[0]);
    }
  }
  for (const auto& [csr, spike_value] : writes) {
    const auto fn = csr_warl_.find(csr);
    if (fn == csr_warl_.end()) continue;
    const uint64_t legal = fn->second(spike_value);
    processor_->put_csr(csr, legal);
    state().log_reg_write[(static_cast<reg_t>(csr) << 4) | kLogCsr].v[0] =
        legal;
  }
}

void SpikeCosim::Impl::check_reg_writes(const RetireRecord& r) {
  std::map<uint32_t, uint64_t> ref[4], dut[4];  // indexed by RegFile
  for (const auto& [key, value] : state().log_reg_write) {
    const auto index = static_cast<uint32_t>(key >> 4);
    switch (key & 0xf) {
      case kLogGpr:
        if (index != 0) ref[0][index] = value.v[0] & xlen_mask_;
        break;
      case kLogFpr: ref[1][index] = value.v[0]; break;
      case kLogVpr: ref[2][index] = 0; break;  // values not logged by Spike
      case kLogCsr: ref[3][index] = value.v[0] & xlen_mask_; break;
      default: break;
    }
  }
  for (const RegWrite& w : r.reg_writes) {
    const auto file = static_cast<size_t>(w.file);
    if (w.file == RegFile::kGpr && w.index == 0) continue;
    uint64_t value = w.value;
    if (w.file == RegFile::kGpr || w.file == RegFile::kCsr) value &= xlen_mask_;
    if (w.file == RegFile::kVpr) value = 0;
    dut[file][w.index] = value;
  }

  // x/f/v: the DUT must report exactly what Spike wrote.
  for (RegFile file : {RegFile::kGpr, RegFile::kFpr, RegFile::kVpr}) {
    const auto f = static_cast<size_t>(file);
    for (const auto& [index, value] : ref[f]) {
      const auto it = dut[f].find(index);
      if (it == dut[f].end()) {
        fail("Spike wrote ", reg_prefix(file), index, " = ", hex(value),
             " but the DUT reported no write");
      } else if (it->second != value) {
        fail(reg_prefix(file), index, " mismatch: DUT ", hex(it->second),
             ", Spike ", hex(value));
      }
    }
    for (const auto& [index, value] : dut[f]) {
      if (!ref[f].count(index)) {
        fail("DUT wrote ", reg_prefix(file), index, " = ", hex(value),
             " but Spike did not");
      }
    }
  }

  // CSRs: only what the DUT chose to report is checked (RVFI CSR extension /
  // RVVI csr_wb), since Spike logs many implicit side-effect writes.
  for (const auto& [csr, value] : dut[3]) {
    if (volatile_csrs_.count(static_cast<int>(csr))) continue;
    const auto it = ref[3].find(csr);
    if (it == ref[3].end()) {
      fail("DUT wrote CSR ", hex(csr), " = ", hex(value), " but Spike did not");
    } else if (it->second != value) {
      fail("CSR ", hex(csr), " mismatch: DUT ", hex(value), ", Spike ",
           hex(it->second));
    }
  }
}

void SpikeCosim::Impl::check_mem() {
  if (ref_reads_ != dut_reads_) {
    fail("load mismatch: DUT ", describe(dut_reads_), ", Spike ",
         describe(ref_reads_));
  }
  if (ref_writes_ != dut_writes_) {
    fail("store mismatch: DUT ", describe(dut_writes_), ", Spike ",
         describe(ref_writes_));
  }
}

// ---------------------------------------------------------------------------
// step()
// ---------------------------------------------------------------------------
bool SpikeCosim::Impl::step(const RetireRecord& r) {
  const size_t errors_before = errors_.size();
  const auto ok = [&] { return errors_.size() == errors_before; };
  RecordScope scope(*this, r);

  check_order(r);

  // RVFI sets rvfi_intr on the first handler instruction for *any* trap.
  // If the previous record was not a trap, the handler was entered by an
  // asynchronous interrupt that Spike has not taken yet.
  const bool async_entry = r.intr && !prev_was_trap_;
  prev_was_trap_ = r.trap;
  if (async_entry && !take_interrupt()) return false;
  expose_irq_lines();

  const uint64_t ref_pc = state().pc & xlen_mask_;
  if (ref_pc != (r.pc & xlen_mask_)) {
    fail("PC mismatch: Spike is at ", hex(ref_pc));
    return false;  // further checks would only add noise
  }
  if (config_.checks.mode && r.mode && *r.mode != state().prv) {
    fail("privilege mismatch: DUT ", unsigned{*r.mode}, ", Spike ",
         unsigned(state().prv));
  }
  if (config_.checks.insn && !r.fetch_fault) check_insn(r);

  const bool was_in_wfi = processor_->is_waiting_for_interrupt();
  execute_one(r.fetch_fault);

  const bool ref_trap = reference_took_trap();
  if (!ref_trap && was_in_wfi && processor_->is_waiting_for_interrupt()) {
    fail("Spike is still waiting in WFI but the DUT retired an instruction "
         "(irq lines ", hex(irq_lines_), "; missing set_irq_lines() or "
         "DUT treats WFI as a NOP => set wfi_as_nop)");
    return false;
  }
  if (ref_trap != r.trap) {
    if (ref_trap) {
      fail("Spike trapped (mcause ", hex(state().mcause->read()),
           ") but the DUT retired the instruction");
    } else {
      fail("DUT trapped but Spike retired the instruction");
    }
    return false;
  }

  if (!r.trap) {
    patch_volatile_csr_read(r);
    if (config_.checks.next_pc && r.next_pc &&
        (*r.next_pc & xlen_mask_) != (state().pc & xlen_mask_)) {
      fail("next PC mismatch: DUT ", hex(*r.next_pc), ", Spike ",
           hex(state().pc & xlen_mask_));
    }
  }
  apply_csr_warl();
  check_reg_writes(r);
  if (!r.trap && config_.checks.mem && r.mem) check_mem();

  if (!ok()) return false;
  if (!r.trap) ++retired_count_;
  return true;
}

// ===========================================================================
// SpikeCosim - thin forwarding layer
// ===========================================================================
SpikeCosim::SpikeCosim(const SpikeCosimConfig& config)
    : impl_(std::make_unique<Impl>(config)) {}
SpikeCosim::~SpikeCosim() = default;
SpikeCosim::SpikeCosim(SpikeCosim&&) noexcept = default;
SpikeCosim& SpikeCosim::operator=(SpikeCosim&&) noexcept = default;

void SpikeCosim::add_region(const std::string& name, uint64_t base,
                            uint64_t size, MemKind kind,
                            std::shared_ptr<MemoryDevice> device) {
  impl_->add_region(name, base, size, kind, std::move(device));
}
bool SpikeCosim::write_mem(uint64_t addr, const uint8_t* data, size_t len) {
  return impl_->write_mem(addr, data, len);
}
bool SpikeCosim::read_mem(uint64_t addr, uint8_t* data, size_t len) {
  return impl_->read_mem(addr, data, len);
}

size_t SpikeCosim::load_binary(const std::string& path, uint64_t base) {
  std::ifstream file(path, std::ios::binary);
  if (!file) throw std::runtime_error("cannot open " + path);
  const std::vector<uint8_t> image((std::istreambuf_iterator<char>(file)),
                                   std::istreambuf_iterator<char>());
  if (!image.empty() && !write_mem(base, image.data(), image.size())) {
    throw std::runtime_error(path + " does not fit in a modeled region at " +
                             hex(base));
  }
  return image.size();
}

void SpikeCosim::flush_instruction_cache() {
  impl_->flush_instruction_cache();
}

void SpikeCosim::set_irq_lines(uint64_t mip) { impl_->set_irq_lines(mip); }
uint64_t SpikeCosim::read_csr(int csr) { return impl_->read_csr(csr); }
void SpikeCosim::write_csr(int csr, uint64_t value) {
  impl_->write_csr(csr, value);
}
void SpikeCosim::set_csr_constant(int csr, uint64_t value) {
  impl_->set_csr_constant(csr, value);
}
void SpikeCosim::add_volatile_csr(int csr) { impl_->add_volatile_csr(csr); }
void SpikeCosim::set_csr_warl(int csr, CsrWarlFn fn) {
  impl_->set_csr_warl(csr, std::move(fn));
}
bool SpikeCosim::step(const RetireRecord& record) {
  return impl_->step(record);
}
const std::vector<std::string>& SpikeCosim::errors() const {
  return impl_->errors_;
}
void SpikeCosim::clear_errors() { impl_->errors_.clear(); }
uint64_t SpikeCosim::retired_count() const { return impl_->retired_count_; }
uint64_t SpikeCosim::pc() const {
  return impl_->state().pc & impl_->xlen_mask();
}
uint64_t SpikeCosim::read_gpr(unsigned index) const {
  return index < 32 ? impl_->state().XPR[index] & impl_->xlen_mask() : 0;
}

}  // namespace cosim
