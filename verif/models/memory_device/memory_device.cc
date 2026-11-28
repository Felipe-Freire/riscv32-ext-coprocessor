// SPDX-License-Identifier: Apache-2.0

#include "memory_device.h"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <vector>

namespace cosim {

SparseRam::SparseRam(uint64_t size) : size_(size) {
  if (size == 0) throw std::invalid_argument("SparseRam size must be > 0");
}

bool SparseRam::load(uint64_t offset, size_t len, uint8_t* bytes) {
  if (!in_range(offset, len)) return false;
  while (len > 0) {
    const uint64_t page = offset / kPageSize;
    const uint64_t in_page = offset % kPageSize;
    const size_t chunk = std::min<uint64_t>(len, kPageSize - in_page);
    const auto it = pages_.find(page);
    if (it == pages_.end()) {
      std::memset(bytes, 0, chunk);
    } else {
      std::memcpy(bytes, it->second->data() + in_page, chunk);
    }
    offset += chunk;
    bytes += chunk;
    len -= chunk;
  }
  return true;
}

bool SparseRam::store(uint64_t offset, size_t len, const uint8_t* bytes) {
  if (!in_range(offset, len)) return false;
  while (len > 0) {
    const uint64_t page = offset / kPageSize;
    const uint64_t in_page = offset % kPageSize;
    const size_t chunk = std::min<uint64_t>(len, kPageSize - in_page);
    auto& slot = pages_[page];
    if (!slot) slot = std::make_unique<Page>(Page{});
    std::memcpy(slot->data() + in_page, bytes, chunk);
    offset += chunk;
    bytes += chunk;
    len -= chunk;
  }
  return true;
}

bool SparseRam::write_strobed(uint64_t offset, uint64_t data, uint8_t strobe) {
  for (unsigned i = 0; i < 8; ++i) {
    if (((strobe >> i) & 1u) == 0) continue;
    const auto byte = static_cast<uint8_t>(data >> (8 * i));
    if (!store(offset + i, 1, &byte)) return false;
  }
  return true;
}

size_t load_binary(MemoryDevice& device, const std::string& path,
                   uint64_t offset) {
  std::ifstream file(path, std::ios::binary);
  if (!file) throw std::runtime_error("cannot open " + path);
  const std::vector<uint8_t> image((std::istreambuf_iterator<char>(file)),
                                   std::istreambuf_iterator<char>());
  if (!image.empty() && !device.store(offset, image.size(), image.data())) {
    throw std::runtime_error(path + " does not fit in the target device");
  }
  return image.size();
}

}  // namespace cosim
