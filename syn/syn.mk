# ASIC synthesis with Cadence Genus, included by the top-level Makefile. Usage: syn/README.md.

# Blocks that can be synthesized. BLOCK picks the file list and the default top; TOP can name any
# other module of that file list. To add a block, add it to SYN_BLOCKS with its two variables.
SYN_BLOCKS       := core coproc
SYN_FLIST_core   := $(PROJ_ROOT)/rtl/core/core.f
SYN_TOP_core     := rv32_core
SYN_FLIST_coproc := $(PROJ_ROOT)/rtl/coproc/coproc.f
SYN_TOP_coproc   := coproc_pe_array

BLOCK      ?= core
TOP        ?= $(SYN_TOP_$(BLOCK))
CLK_PERIOD ?= 10
EFFORT     ?= medium
LIBS       ?=
GENUS      ?= genus

SYN_RUN_DIR = $(BUILD_DIR)/syn/$(TOP)
# The top's own constraints if syn/constraints/<top>.sdc exists, the generic ones otherwise.
SYN_SDC     = $(firstword $(wildcard $(PROJ_ROOT)/syn/constraints/$(TOP).sdc) \
                $(PROJ_ROOT)/syn/constraints/default.sdc)

.PHONY: syn syn-list

syn:
	@test -n "$(SYN_FLIST_$(BLOCK))" || \
	  { echo "[syn] Unknown BLOCK '$(BLOCK)', choose one of: $(SYN_BLOCKS)" >&2; exit 1; }
	@mkdir -p $(SYN_RUN_DIR)
	cd $(SYN_RUN_DIR) && \
	  SYN_TOP=$(TOP) SYN_FLIST="$(SYN_FLIST_$(BLOCK))" SYN_SDC=$(SYN_SDC) \
	  SYN_CLK_PERIOD=$(CLK_PERIOD) SYN_LIBS="$(abspath $(LIBS))" SYN_EFFORT=$(EFFORT) \
	  $(GENUS) -batch -no_gui -abort_on_error -overwrite -log genus \
	    -files $(PROJ_ROOT)/syn/genus/syn.tcl
	@echo "[syn] Reports in $(SYN_RUN_DIR)/reports"

# Lists each block with the modules of its file list, any of which can be TOP.
syn-list:
	@$(foreach b,$(SYN_BLOCKS),echo "BLOCK=$(b) (default TOP=$(SYN_TOP_$(b))):"; \
	  sed -n 's|^\s*$${PROJ_ROOT}|$(PROJ_ROOT)|p' $(SYN_FLIST_$(b)) | \
	  xargs sed -n 's/^\s*module\s\+\(\w\+\).*/  \1/p';)
