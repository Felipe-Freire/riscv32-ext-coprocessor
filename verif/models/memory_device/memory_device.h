// SPDX-License-Identifier: Apache-2.0
//
// memory_device.h - Memory/peripheral interface shared by the hart cosim and
// a SoC-level reference model. No Spike dependency: a SoC model can include
// this header without pulling in the ISS.
//
//   Core-only TB : SpikeCosim creates a private SparseRam per modeled region.
//   SoC ref model: the SoC model owns SparseRam / peripheral models and maps
//                  the same objects into one or more SpikeCosim instances,
//                  so CPU harts, DMA and accelerators see one memory image.

#ifndef COSIM_MEMORY_DEVICE_H_
#define COSIM_MEMORY_DEVICE_H_

#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>

namespace cosim {

// A target on the reference memory map. Offsets are relative to the base
// address the device is mapped at, so one object can be mapped at different
// addresses in different hart views.
//
// Calls happen from inside SpikeCosim::step(), in program order, which is
// exactly the point at which a SoC model should react to CPU accesses (e.g.
// a store to an accelerator's START register).
class MemoryDevice {
 public:
  virtual ~MemoryDevice() = default;

  virtual uint64_t size() const = 0;

  // Architectural CPU access (may have side effects in peripheral models).
  // Misaligned CPU accesses may arrive split into single bytes.
  virtual bool load(uint64_t offset, size_t len, uint8_t* bytes) = 0;
  virtual bool store(uint64_t offset, size_t len, const uint8_t* bytes) = 0;

  // Side-effect-free read used by the cosim itself (instruction checks,
  // backdoor reads). Peripheral models with read side effects override it.
  virtual bool peek(uint64_t offset, size_t len, uint8_t* bytes) {
    return load(offset, len, bytes);
  }
};

// Sparse byte-addressable RAM. Unwritten bytes read as zero; pages are
// allocated on first write. Not thread-safe (simulators call DPI serially).
class SparseRam final : public MemoryDevice {
 public:
  explicit SparseRam(uint64_t size);

  uint64_t size() const override { return size_; }
  bool load(uint64_t offset, size_t len, uint8_t* bytes) override;
  bool store(uint64_t offset, size_t len, const uint8_t* bytes) override;

  // Byte-strobed write, e.g. one AXI W beat seen by a bus monitor:
  // byte i of `data` is written to offset + i when bit i of `strobe` is set.
  bool write_strobed(uint64_t offset, uint64_t data, uint8_t strobe);

 private:
  static constexpr uint64_t kPageSize = 4096;
  using Page = std::array<uint8_t, kPageSize>;

  bool in_range(uint64_t offset, size_t len) const {
    return len <= size_ && offset <= size_ - len;
  }

  uint64_t size_;
  std::unordered_map<uint64_t, std::unique_ptr<Page>> pages_;
};

// Writes a flat binary image into `device` at `offset`; returns its size.
// Throws std::runtime_error on I/O failure or if it does not fit.
size_t load_binary(MemoryDevice& device, const std::string& path,
                   uint64_t offset);

}  // namespace cosim

#endif  // COSIM_MEMORY_DEVICE_H_
