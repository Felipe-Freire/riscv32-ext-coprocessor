# SPDX-License-Identifier: Apache-2.0
#
# Builds libspike_cosim.so for loading into a simulator (-sv_lib / -sv_root).
#
#   make SPIKE_PREFIX=/opt/spike SVDPI_INCLUDE=$VCS_HOME/include
#
# SVDPI_INCLUDE: directory containing svdpi.h for your simulator
#   VCS:       $VCS_HOME/include
#   Xcelium:   $(xmroot)/tools/include
#   Questa:    $MTI_HOME/include
#   Verilator: $VERILATOR_ROOT/include/vltstd

SPIKE_PREFIX  ?= /opt/spike
SVDPI_INCLUDE ?= $(VCS_HOME)/include

export PKG_CONFIG_PATH := $(SPIKE_PREFIX)/lib/pkgconfig:$(PKG_CONFIG_PATH)

CXX      ?= g++
CXXFLAGS ?= -O2 -g
CXXFLAGS += -std=c++20 -fPIC -Wall -Wextra \
            $(shell pkg-config --cflags riscv-riscv) -I$(SVDPI_INCLUDE)
LDFLAGS  += -shared -Wl,-rpath,$(SPIKE_PREFIX)/lib
LDLIBS   += $(shell pkg-config --libs riscv-riscv riscv-disasm riscv-fdt)

SRCS := memory_device.cc spike_cosim.cc spike_cosim_dpi.cc
OBJS := $(SRCS:.cc=.o)
LIB  := libspike_cosim.so

all: $(LIB)

$(LIB): $(OBJS)
	$(CXX) $(LDFLAGS) -o $@ $^ $(LDLIBS)

%.o: %.cc spike_cosim.h memory_device.h spike_cosim_dpi.h
	$(CXX) $(CXXFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) $(LIB)

.PHONY: all clean
