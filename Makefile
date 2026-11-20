# Top-level entry point. Run `make help` for the targets and their variables.

export PROJ_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

BUILD_DIR ?= $(PROJ_ROOT)/build

# Blocks: RTL file lists in compile order (vendor IP first) and the top module. Synthesis, STA and
# gate-level simulation pick one with BLOCK=<name>; simulation finds it from the testbench.
BLOCKS           := core coproc
RTL_FLIST_core   := $(PROJ_ROOT)/rtl/core/core.f
RTL_TOP_core     := rv32_core
RTL_FLIST_coproc := $(PROJ_ROOT)/vendor/common_cells.f $(PROJ_ROOT)/rtl/coproc/coproc.f
RTL_TOP_coproc   := coproc_top

.DEFAULT_GOAL := help
.PHONY: help clean

include $(PROJ_ROOT)/syn/tech/tech.mk
include $(PROJ_ROOT)/syn/syn.mk
include $(PROJ_ROOT)/syn/sta.mk
include $(PROJ_ROOT)/scripts/sim/xrun/sim.mk

define HELP_TEXT
Usage: make <target> [VAR=value ...]

Synthesis and timing (Genus), see syn/README.md
  syn             Synthesize BLOCK (or TOP)                  -> build/syn/<top>/
  syn-list        List the blocks and the modules each one can synthesize
  sta             Static timing of the synthesized TOP at CORNER -> build/sta/<top>/<corner>/

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
  VT                    GPDK045 threshold flavour: svt, lvt, hvt (default: svt)
  CORNER                slow_vdd1v0, slow_vdd1v2, fast_vdd1v0, fast_vdd1v2 (default: slow_vdd1v0)
  RC_CORNER             Wire estimation rules: rcworst, typical, rcbest (default: rcworst)
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
  make sta BLOCK=core CORNER=slow_vdd1v2
  make sim TB=tb_rv32_core
  make sim UVM=coproc TEST=coproc_matmul_rand_test SEED=random PLUSARGS=+JOBS=10
  make gls TB=tb_rv32_core SDF=1
  make regress LIST=verif/regress/smoke.list JOBS=4
endef
export HELP_TEXT

help:
	@echo "Usage: make <target> [VAR=value]"
	@echo ""
	@echo "Targets:"
	@echo "  sw              Build a software test into build/sw (sw/README.md)"
	@echo "  cosim           Run a software test on Spike and on the RTL core and compare"
	@echo "  cosim-all       Run every test under sw/tests the same way"
	@echo "                  (run_cosim.py also takes --wait, --random N, -j, --list)"
	@echo "  vsim-unit       Run one unit testbench with Verilator"
	@echo "  sim             Run one simulation (not configured yet)"
	@echo "  regress         Run a regression (not configured yet)"
	@echo "  syn             ASIC synthesis with Genus (syn/README.md)"
	@echo "  syn-list        List the blocks and the modules each one can synthesize"
	@echo "  clean           Remove $(BUILD_DIR)"
	@echo ""
	@echo "Software and simulation variables:"
	@echo "  TEST            Program under sw/tests (default: sum)"
	@echo "  TB              Unit testbench for vsim-unit (default: tb_rv32_core)"
	@echo "  RISCV           Spike install prefix (default: $(BUILD_DIR)/riscv)"
	@echo "  COSIM_GNT_WAIT  Cycles a data request waits for its grant (default: 0)"
	@echo "  COSIM_RSP_WAIT  Cycles from grant to response (default: 0)"
	@echo "  COSIM_WAIT_SEED Nonzero: random waits up to those maxima (default: 0)"
	@echo ""
	@echo "Synthesis variables:"
	@echo "  BLOCK           $(SYN_BLOCKS) (default: core)"
	@echo "  TOP             Any module of the block, see syn-list (default: the block's top)"
	@echo "  CLK_PERIOD      Clock period in ns (default: 10)"
	@echo "  LIBS            Liberty files (default: Genus tutorial library)"
	@echo "  EFFORT          low, medium or high (default: medium)"

sim regress:
	@echo "[$@] Simulation flow not configured yet, see scripts/README.md" >&2
	@exit 1

clean:
	rm -rf $(BUILD_DIR)

include $(PROJ_ROOT)/sw/sw.mk
include $(PROJ_ROOT)/scripts/sim/verilator/verilator.mk
include $(PROJ_ROOT)/syn/syn.mk
