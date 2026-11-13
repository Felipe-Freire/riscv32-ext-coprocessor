# Top-level entry point. Run `make help` for the list of targets.

export PROJ_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

BUILD_DIR    ?= $(PROJ_ROOT)/build

.DEFAULT_GOAL := help
.PHONY: help sim regress clean

help:
	@echo "Usage: make <target> [VAR=value]"
	@echo ""
	@echo "Targets:"
	@echo "  sim             Run one simulation (not configured yet)"
	@echo "  regress         Run a regression (not configured yet)"
	@echo "  syn             ASIC synthesis with Genus (syn/README.md)"
	@echo "  syn-list        List the blocks and the modules each one can synthesize"
	@echo "  clean           Remove $(BUILD_DIR)"
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

include $(PROJ_ROOT)/syn/syn.mk
