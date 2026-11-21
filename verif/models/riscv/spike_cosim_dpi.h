// SPDX-License-Identifier: Apache-2.0
//
// spike_cosim_dpi.h - C++ bridge for code that receives chandles created by
// spike_cosim_pkg (e.g. a C++ SoC reference model also called via DPI).
//
//   SV : ram_h = spike_cosim_ram_create(...); h = spike_cosim_create(...);
//        soc_model_init(h, ram_h);            // your own DPI function
//   C++: auto& hart = cosim::cosim_from_handle(h);
//        auto  ram  = cosim::ram_from_handle(ram_h);  // shared ownership

#ifndef COSIM_SPIKE_COSIM_DPI_H_
#define COSIM_SPIKE_COSIM_DPI_H_

#include <memory>

#include "memory_device.h"
#include "spike_cosim.h"

namespace cosim {

// Throw std::invalid_argument on a null handle.
SpikeCosim& cosim_from_handle(void* handle);
std::shared_ptr<SparseRam> ram_from_handle(void* handle);

}  // namespace cosim

#endif  // COSIM_SPIKE_COSIM_DPI_H_
