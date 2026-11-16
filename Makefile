# Top-level entry point. Run `make help` for the list of targets.

export PROJ_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

BUILD_DIR    ?= $(PROJ_ROOT)/build

.DEFAULT_GOAL := help
.PHONY: help sim regress clean

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
