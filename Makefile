# Top-level entry point. Run `make help` for the list of targets.

export PROJ_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

BUILD_DIR    ?= $(PROJ_ROOT)/build

.DEFAULT_GOAL := help
.PHONY: help sim regress syn clean

help:
	@echo "Usage: make <target> [VAR=value]"
	@echo ""
	@echo "Targets:"
	@echo "  sim             Run one simulation (not configured yet)"
	@echo "  regress         Run a regression (not configured yet)"
	@echo "  syn             Run ASIC synthesis (not configured yet)"
	@echo "  clean           Remove $(BUILD_DIR)"

sim regress:
	@echo "[$@] Simulation flow not configured yet, see scripts/README.md" >&2
	@exit 1

syn:
	@echo "[syn] Synthesis flow not configured yet, see syn/README.md" >&2
	@exit 1

clean:
	rm -rf $(BUILD_DIR)
