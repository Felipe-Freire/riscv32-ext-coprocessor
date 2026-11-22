# SRAM macros of FreePDK45, generated with OpenRAM. Included by the top-level Makefile.
#
#   make openram                     every macro of syn/tech/openram45/<macro>.py -> lib/openram45/<macro>/
#   make openram MACROS=<macro>      only that one
#   make openram OPENRAM45=<dir>     to another directory
#
# OpenRAM comes from the project venv (requirements.txt), which this target builds first. Each
# <macro>.py is an OpenRAM configuration; OpenRAM places the macro and writes, named after it:
#   <macro>_TT_1p1V_25C.lib  Liberty at the typical corner of the NanGate cells (the only one, see
#                            the configuration)
#   <macro>.lef              abstract for placement (metal1-metal4, the layers of the tech LEF)
#   <macro>.v                behavioral Verilog model, for simulation. The model prints every read
#                            and write while its VERBOSE parameter is 1, and a netlist cannot
#                            override it, so this target writes it with VERBOSE = 0
#   <macro>.gds, <macro>.sp, <macro>.html   layout, netlist, datasheet
# The configurations need no tool the machine lacks: no conda, no DRC/LVS (Magic, Netgen) and
# analytical timing instead of SPICE characterization. Logs and intermediate files go to
# build/openram/<macro>/. OpenRAM empties its temporary directory (OPENRAM_TMP) at the end, so that
# directory is always one of its own.

OPENRAM45_CFG_DIR := $(PROJ_ROOT)/syn/tech/openram45
MACROS            ?= $(OPENRAM45_MACROS)
OPENRAM_RUN_DIR    = $(BUILD_DIR)/openram

.PHONY: openram

openram: $(VENV_STAMP)
	@for m in $(MACROS); do \
	  test -r $(OPENRAM45_CFG_DIR)/$$m.py || \
	    { echo "[openram] No configuration $(OPENRAM45_CFG_DIR)/$$m.py" >&2; exit 1; }; \
	done
	@pkg=$$($(VENV)/bin/python3 -c 'import os, openram; print(os.path.dirname(openram.__file__))') && \
	for m in $(MACROS); do \
	  run=$(OPENRAM_RUN_DIR)/$$m; mkdir -p $$run/tmp $(OPENRAM45)/$$m; \
	  echo "[openram] $$m -> $(OPENRAM45)/$$m (log in $$run/openram.log)"; \
	  start=$$(date +%s); \
	  ( cd $$run && OPENRAM_TMP=$$run/tmp $(VENV)/bin/python3 $$pkg/sram_compiler.py -v \
	      -o $$m -p $(OPENRAM45)/$$m $(OPENRAM45_CFG_DIR)/$$m.py > openram.log 2>&1 ) || \
	    { echo "[openram] $$m failed, see $$run/openram.log" >&2; exit 1; }; \
	  for f in $(foreach c,$(OPENRAM45_CORNERS),$${m}_$(c).lib) $$m.lef $$m.v; do \
	    test -r $(OPENRAM45)/$$m/$$f || \
	      { echo "[openram] $$m: OpenRAM wrote no $$f, see $$run/openram.log" >&2; exit 1; }; \
	  done; \
	  sed -i 's/^\(\s*parameter VERBOSE = \)1\b/\10/' $(OPENRAM45)/$$m/$$m.v; \
	  grep -q 'parameter VERBOSE = 0' $(OPENRAM45)/$$m/$$m.v || \
	    { echo "[openram] $$m: no VERBOSE parameter to turn off in $$m.v" >&2; exit 1; }; \
	  echo "[openram] $$m done in $$(( $$(date +%s) - start )) s"; \
	done
