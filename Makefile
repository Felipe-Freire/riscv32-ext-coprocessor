# Top-level entry point. Run `make help` for the targets and their variables.

export PROJ_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

BUILD_DIR ?= $(PROJ_ROOT)/build

# Blocks: RTL file lists in compile order (vendor IP first) and the top module. Synthesis, STA and
# gate-level simulation pick one with BLOCK=<name>; simulation finds it from the testbench.
# SIM_FLIST_<block>: file lists only the testbenches of the block compile, after its RTL (verification
# IP, or the RTL of another block a testbench runs against). Synthesis never reads them.
BLOCKS           := prim core coproc dma bus
# Technology primitives (SRAM wrappers): the generic versions, for simulation.
RTL_FLIST_prim   := $(PROJ_ROOT)/rtl/prim/prim.f
RTL_TOP_prim     := prim_ram_1p
RTL_FLIST_core   := $(PROJ_ROOT)/rtl/core/core.f
RTL_TOP_core     := rv32_core
RTL_FLIST_coproc := $(PROJ_ROOT)/vendor/common_cells.f $(PROJ_ROOT)/rtl/coproc/coproc.f
RTL_TOP_coproc   := coproc_top
RTL_FLIST_dma    := $(PROJ_ROOT)/rtl/dma/dma.f
RTL_TOP_dma      := dma_top
# tb_dma_coproc runs the DMA against coproc_top.
SIM_FLIST_dma    := $(PROJ_ROOT)/vendor/common_cells.f $(PROJ_ROOT)/rtl/coproc/coproc.f
RTL_FLIST_bus    := $(PROJ_ROOT)/vendor/common_cells.f $(PROJ_ROOT)/vendor/axi.f \
                    $(PROJ_ROOT)/rtl/common/common.f $(PROJ_ROOT)/rtl/bus/bus.f
RTL_TOP_bus      := bus_top
SIM_FLIST_bus    := $(PROJ_ROOT)/vendor/common_verification.f $(PROJ_ROOT)/vendor/axi_sim.f \
                    $(PROJ_ROOT)/verif/assertions/bus.f
# top joins BLOCKS when its top, soc_top, exists; until then its testbenches compile the whole RTL.
RTL_FLIST_top    := $(PROJ_ROOT)/rtl/rtl.f
SIM_FLIST_top    := $(SIM_FLIST_bus)

.DEFAULT_GOAL := help
.PHONY: help clean

include $(PROJ_ROOT)/syn/tech/tech.mk
include $(PROJ_ROOT)/syn/tech/freepdk45/freepdk45.mk
include $(PROJ_ROOT)/syn/syn.mk
include $(PROJ_ROOT)/syn/sta.mk
include $(PROJ_ROOT)/scripts/sim/xrun/sim.mk

define HELP_TEXT
Usage: make <target> [VAR=value ...]

Synthesis and timing (Genus), see syn/README.md
  syn             Synthesize BLOCK (or TOP)                  -> build/syn/<top>/
  syn-list        List the blocks and the modules each one can synthesize
  sta             Static timing of the synthesized TOP at CORNER -> build/sta/<top>/<corner>/
  freepdk45       Download the FreePDK45/NanGate views       -> lib/freepdk45/

Simulation (Xcelium), see scripts/README.md
  sim             Run a directed testbench (TB=) or a UVM test (UVM= TEST=)
                                                             -> build/sim/<run>/
  gls             Same as sim, on the synthesized netlist of TOP (run syn first)
  sim-list        List the testbenches, the UVM environments and their tests
  regress         Run every line of a regression list, then a PASS/FAIL table

  clean           Remove $(BUILD_DIR)

Design and technology (syn, sta, gls)
  BLOCK                 $(BLOCKS) (default: core)
  TOP                   Top module (default: the block's top, see syn-list)
  CLK_PERIOD            clk_i period in ns (default: 10)
  ACC_CLK_PERIOD        clk_acc_i period of coproc_top in ns (default: CLK_PERIOD)
  EFFORT                Synthesis effort: low, medium, high (default: medium)
  CLOCK_GATING          1 inserts clock-gating cells, 0 keeps enable muxes (default: 1)
  TECH                  freepdk45 (FreePDK45 + NanGate cells) or gpdk045 (standby) (default: freepdk45)
  CORNER                freepdk45: typical, slow, fast (default: slow)
                        gpdk045: slow_vdd1v0, slow_vdd1v2, fast_vdd1v0, fast_vdd1v2 (default: slow_vdd1v0)
  VT                    gpdk045 threshold flavour: svt, lvt, hvt (default: svt)
  RC_CORNER             gpdk045 wire estimation rules: rcworst, typical, rcbest (default: rcworst)
  FREEPDK45, GPDK045    Kit directory (default: lib/freepdk45; the GPDK045 search of syn/tech/tech.mk)
  LIBS= LEFS=           Empty: Genus tutorial library, no physical data
  In use here: $(strip $(TECH_NAME))

Simulation
  TB                    Directed testbench verif/unit/<block>/<TB>.sv
  UVM, TEST             UVM environment verif/uvm/<UVM>/ and its test class
  SEED                  Random seed, or random (default: 1)
  VERBOSITY             UVM verbosity (default: UVM_MEDIUM)
  PLUSARGS              Extra plusargs, e.g. PLUSARGS="+JOBS=10 +BIG_K"
  WAVES=1               Record every signal to waves.shm (open with simvision)
  GUI=1                 Run inside SimVision
  COV=1                 Collect code and functional coverage
  XRUN_OPTS             Extra xrun options
  GLS=1                 Gate level, what gls does; with SDF=1, the delays of SDF_FILE
  SDF_FILE              SDF to annotate (default: the one make syn wrote for TOP)
  CELL_MODELS           Verilog models of the cells (default: found in the kit)
  LIST, JOBS            Regression lists and runs at a time (default: smoke.list, 1)

Examples
  make syn BLOCK=coproc CLK_PERIOD=5 ACC_CLK_PERIOD=2.5
  make syn BLOCK=core TOP=rv32_alu
  make sta BLOCK=core CORNER=typical
  make syn BLOCK=core TECH=gpdk045
  make sim TB=tb_rv32_core
  make sim UVM=coproc TEST=coproc_matmul_rand_test SEED=random PLUSARGS=+JOBS=10
  make gls TB=tb_rv32_core SDF=1
  make regress LIST=verif/regress/smoke.list JOBS=4
endef
export HELP_TEXT

help:
	@echo "$$HELP_TEXT"

clean:
	rm -rf $(BUILD_DIR)
