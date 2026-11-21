# ASIC synthesis with Cadence Genus, included by the top-level Makefile. Usage: syn/README.md.
# The blocks are in the top-level Makefile and the technology in syn/tech/tech.mk.

BLOCK          ?= core
TOP            ?= $(RTL_TOP_$(BLOCK))
CLK_PERIOD     ?= 10
ACC_CLK_PERIOD ?= $(CLK_PERIOD)
EFFORT         ?= medium
CLOCK_GATING   ?= 1
GENUS          ?= genus

SYN_RUN_DIR = $(BUILD_DIR)/syn/$(TOP)
# The top's own constraints if syn/constraints/<top>.sdc exists, the generic ones otherwise.
SYN_SDC     = $(firstword $(wildcard $(PROJ_ROOT)/syn/constraints/$(TOP).sdc) \
                $(PROJ_ROOT)/syn/constraints/default.sdc)

# Recipe line that stops on a BLOCK missing from the table.
define BLOCK_CHECK
@test -n "$(RTL_FLIST_$(BLOCK))" || \
  { echo "[$@] Unknown BLOCK '$(BLOCK)', choose one of: $(BLOCKS)" >&2; exit 1; }
endef

.PHONY: syn syn-list

syn:
	$(BLOCK_CHECK)
	$(TECH_CHECK)
	@mkdir -p $(SYN_RUN_DIR)
	cd $(SYN_RUN_DIR) && \
	  SYN_TOP=$(TOP) SYN_FLIST="$(RTL_FLIST_$(BLOCK))" SYN_SDC=$(SYN_SDC) \
	  SYN_CLK_PERIOD=$(CLK_PERIOD) SYN_ACC_CLK_PERIOD=$(ACC_CLK_PERIOD) \
	  SYN_EFFORT=$(EFFORT) SYN_CLOCK_GATING=$(CLOCK_GATING) \
	  SYN_LIBS="$(abspath $(LIBS))" SYN_LEFS="$(abspath $(LEFS))" SYN_QRC="$(abspath $(QRC))" \
	  SYN_CAPTBL="$(abspath $(CAPTBL))" \
	  $(GENUS) -batch -no_gui -abort_on_error -overwrite -log genus \
	    -files $(PROJ_ROOT)/syn/genus/syn.tcl
	@echo "$(TECH_CELLS)" > $(SYN_RUN_DIR)/outputs/cells
	@echo "[syn] Reports in $(SYN_RUN_DIR)/reports"

# Lists each block with the modules of its own RTL (vendor IP left out), any of which can be TOP.
syn-list:
	@$(foreach b,$(BLOCKS),echo "BLOCK=$(b) (default TOP=$(RTL_TOP_$(b))):"; \
	  sed -n 's|^\s*$${PROJ_ROOT}/rtl/|$(PROJ_ROOT)/rtl/|p' $(RTL_FLIST_$(b)) | \
	  xargs sed -n 's/^\s*module\s\+\(\w\+\).*/  \1/p';)
