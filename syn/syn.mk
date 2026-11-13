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
GENUS      ?= genus

# ---- Technology: GPDK045 standard cells (gsclib045) ---------------------------------------------
# VT picks the threshold flavour (svt, lvt, hvt) and CORNER the timing corner of its Liberty file
# (slow_vdd1v0, slow_vdd1v2, fast_vdd1v0, fast_vdd1v2). RC_CORNER picks the extraction rules used
# for wire estimation (rcworst, typical, rcbest). Overrides:
#   LIBS=   (empty) Genus tutorial library, no physical data
#   LEFS=   (empty) zero wire load instead of physical-aware estimation (PLE)
# gsclib045_svt_v4.4 is not usable: it ships LEF and QRC but no Liberty files.
GPDK045    ?= /apps/cds/installs/STRATUS2501/share/stratus/techlibs/GPDK045
VT         ?= svt
CORNER     ?= slow_vdd1v0
RC_CORNER  ?= rcworst

GSC_SUFFIX_svt :=
GSC_SUFFIX_lvt := _lvt
GSC_SUFFIX_hvt := _hvt
GSC_LEF_svt    := gsclib045_macro.lef
GSC_LEF_lvt    := gsclib045_lvt_macro.lef
GSC_LEF_hvt    := gsclib045_hvt_macro.lef

LIBS ?= $(GPDK045)/gsclib045_$(VT)/timing/$(CORNER)_basicCells$(GSC_SUFFIX_$(VT)).lib
LEFS ?= $(GPDK045)/gpdk/lef/gsclib045_tech.lef $(GPDK045)/gsclib045_$(VT)/lef/$(GSC_LEF_$(VT))
QRC  ?= $(GPDK045)/gpdk/qrc/$(RC_CORNER)/qrcTechFile

SYN_RUN_DIR = $(BUILD_DIR)/syn/$(TOP)
# The top's own constraints if syn/constraints/<top>.sdc exists, the generic ones otherwise.
SYN_SDC     = $(firstword $(wildcard $(PROJ_ROOT)/syn/constraints/$(TOP).sdc) \
                $(PROJ_ROOT)/syn/constraints/default.sdc)

.PHONY: syn syn-list

syn:
	@test -n "$(SYN_FLIST_$(BLOCK))" || \
	  { echo "[syn] Unknown BLOCK '$(BLOCK)', choose one of: $(SYN_BLOCKS)" >&2; exit 1; }
	@for f in $(LIBS) $(LEFS) $(if $(LEFS),$(QRC)); do test -r "$$f" || \
	  { echo "[syn] Cannot read $$f (check VT, CORNER, RC_CORNER and the cidigital group)" >&2; exit 1; }; done
	@mkdir -p $(SYN_RUN_DIR)
	cd $(SYN_RUN_DIR) && \
	  SYN_TOP=$(TOP) SYN_FLIST="$(SYN_FLIST_$(BLOCK))" SYN_SDC=$(SYN_SDC) \
	  SYN_CLK_PERIOD=$(CLK_PERIOD) SYN_EFFORT=$(EFFORT) \
	  SYN_LIBS="$(abspath $(LIBS))" SYN_LEFS="$(abspath $(LEFS))" SYN_QRC="$(abspath $(QRC))" \
	  $(GENUS) -batch -no_gui -abort_on_error -overwrite -log genus \
	    -files $(PROJ_ROOT)/syn/genus/syn.tcl
	@echo "[syn] Reports in $(SYN_RUN_DIR)/reports"

# Lists each block with the modules of its file list, any of which can be TOP.
syn-list:
	@$(foreach b,$(SYN_BLOCKS),echo "BLOCK=$(b) (default TOP=$(SYN_TOP_$(b))):"; \
	  sed -n 's|^\s*$${PROJ_ROOT}|$(PROJ_ROOT)|p' $(SYN_FLIST_$(b)) | \
	  xargs sed -n 's/^\s*module\s\+\(\w\+\).*/  \1/p';)
