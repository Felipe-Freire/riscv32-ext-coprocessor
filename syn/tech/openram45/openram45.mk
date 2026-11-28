# SRAM macros of FreePDK45, generated with OpenRAM. Included by the top-level Makefile.
#
#   make openram                     every macro of syn/tech/openram45/<macro>.py -> lib/openram45/<macro>/
#   make openram-char                their SPICE characterization -> lib/openram45/<macro>/spice/
#   make openram[-char] MACROS=<m>   only that one
#   make openram[-char] OPENRAM45=<dir>   to another directory
#
# The flows do not need these targets: they read the views kept in git, syn/tech/openram45/views/
# (OPENRAM45_VIEWS). Both targets copy their views there at the end (Liberty, plus LEF and Verilog
# model for make openram), so a regenerated or characterized macro shows up in git diff and is
# committed once, instead of every machine running OpenRAM for an hour or for hours.
#
# OpenRAM, ngspice and KLayout come from the project venv (requirements.txt, eda-tools.yml), which
# these targets build first; they reach OpenRAM through PATH, with $(EDA)/bin first. OpenRAM wraps
# each SPICE run in its own conda's activate script, so CONDA_HOME points at the stand-in of
# conda/bin/activate, which leaves PATH as it is. scripts/utils/openram_macro.py runs OpenRAM, one
# run per corner, and checks the results.
#
# make openram (about an hour per macro): layout with supply rings and pins on the edge, DRC and
# LVS with KLayout, and timing from OpenRAM's analytical model at TT. In lib/openram45/<macro>/:
#   <macro>_TT_1p1V_25C.lib  Liberty, analytical, at the typical corner of the NanGate cells
#   <macro>.lef              abstract for placement: pins on the edge, supply rings (metal1-metal4,
#                            the layers of the tech LEF)
#   <macro>.v                behavioral Verilog model, for simulation, written with VERBOSE = 0
#   <macro>.gds, <macro>.sp, <macro>.lvs.sp, <macro>.html   layout, netlists, datasheet
# It stops when a view is missing, the DRC is not clean or the LVS does not match.
#
# make openram-char (hours per corner, the corners in parallel): ngspice characterization at the
# spice_corners of the configuration, the PVT of the NanGate corners, into
# lib/openram45/<macro>/spice/<macro>_<corner>.lib, published to views/<macro>/spice/.
# syn/tech/tech.mk reads those files when they exist. It stops when a run fails or the area
# differs from the one of the published TT Liberty file.
#
# Logs and intermediate files go to build/openram/<macro>/<corner>/ (make openram) and
# build/openram/<macro>/char/<corner>/ (make openram-char): openram.log, and tmp/ (OpenRAM's
# OPENRAM_TMP, kept) with the SPICE decks and results and the DRC and LVS reports. OpenRAM empties
# that directory when it starts, so it is always one of its own.

OPENRAM45_CFG_DIR := $(PROJ_ROOT)/syn/tech/openram45
MACROS            ?= $(OPENRAM45_MACROS)
OPENRAM_RUN_DIR    = $(BUILD_DIR)/openram
OPENRAM_ENV        = PATH=$(EDA)/bin:$$PATH CONDA_HOME=$(OPENRAM45_CFG_DIR)/conda
OPENRAM_MACRO      = $(OPENRAM_ENV) $(VENV)/bin/python3 $(PROJ_ROOT)/scripts/utils/openram_macro.py

.PHONY: openram openram-char openram-check

openram-check:
	@for m in $(MACROS); do \
	  test -r $(OPENRAM45_CFG_DIR)/$$m.py || \
	    { echo "[openram] No configuration $(OPENRAM45_CFG_DIR)/$$m.py" >&2; exit 1; }; \
	done

openram: openram-check $(VENV_STAMP) $(EDA_STAMP)
	@for m in $(MACROS); do \
	  $(OPENRAM_MACRO) --config $(OPENRAM45_CFG_DIR)/$$m.py --out $(OPENRAM45)/$$m \
	    --run $(OPENRAM_RUN_DIR)/$$m --publish $(OPENRAM45_VIEWS)/$$m || exit 1; \
	done

openram-char: openram-check $(VENV_STAMP) $(EDA_STAMP)
	@for m in $(MACROS); do \
	  $(OPENRAM_MACRO) --char --config $(OPENRAM45_CFG_DIR)/$$m.py --out $(OPENRAM45)/$$m/spice \
	    --run $(OPENRAM_RUN_DIR)/$$m/char --area-ref $(OPENRAM45_VIEWS)/$$m/$${m}_$(OPENRAM45_TT).lib \
	    --publish $(OPENRAM45_VIEWS)/$$m/spice || exit 1; \
	done
