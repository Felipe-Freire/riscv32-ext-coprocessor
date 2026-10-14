# Top-level entry point. Run `make help` for the list of targets.

export PROJ_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

BUILD_DIR    ?= $(PROJ_ROOT)/build
RTL_FLIST    := $(PROJ_ROOT)/rtl/rtl.f
RTL_SRCS     := $(shell find $(PROJ_ROOT)/rtl -name '*.sv' 2>/dev/null)
RTL_TOP      ?=

VERILATOR    ?= verilator
VERIBLE_LINT ?= verible-verilog-lint

.DEFAULT_GOAL := help
.PHONY: help lint lint-verilator lint-verible sim regress clean

help:
	@echo "Usage: make <target> [VAR=value]"
	@echo ""
	@echo "Targets:"
	@echo "  lint            Lint RTL with Verilator and Verible (if installed)"
	@echo "  lint-verilator  Lint RTL with Verilator only"
	@echo "  lint-verible    Lint RTL with Verible only"
	@echo "  sim             Run one simulation (not configured yet)"
	@echo "  regress         Run a regression (not configured yet)"
	@echo "  clean           Remove $(BUILD_DIR)"
	@echo ""
	@echo "Variables:"
	@echo "  RTL_TOP=<module>  Top module for lint (default: auto-detect)"

lint: lint-verilator lint-verible

lint-verilator:
ifeq ($(strip $(RTL_SRCS)),)
	@echo "[lint] No RTL sources yet, skipping Verilator."
else
	$(VERILATOR) --lint-only -Wall -f $(RTL_FLIST) $(if $(RTL_TOP),--top-module $(RTL_TOP))
endif

lint-verible:
ifeq ($(strip $(RTL_SRCS)),)
	@echo "[lint] No RTL sources yet, skipping Verible."
else ifeq ($(shell command -v $(VERIBLE_LINT) 2>/dev/null),)
	@echo "[lint] $(VERIBLE_LINT) not found, skipping Verible."
else
	$(VERIBLE_LINT) $(RTL_SRCS)
endif

sim regress:
	@echo "[$@] Simulation flow not configured yet, see scripts/README.md" >&2
	@exit 1

clean:
	rm -rf $(BUILD_DIR)
