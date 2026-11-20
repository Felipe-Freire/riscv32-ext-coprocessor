# Technology of synthesis, STA and gate-level simulation. Included by the top-level Makefile.
#
# GPDK045 standard cells (gsclib045). The kit is the first of these directories that holds it:
#   1. /apps/cds/installs/STRATUS2501/share/stratus/techlibs/GPDK045 (the Stratus install)
#   2. lib/GPDK045 in the project, or lib/ itself (a local copy, ignored by git: the kit is under NDA)
# GPDK045=<dir> on the command line skips the search. With no kit in either place, the flows use the
# Genus tutorial library: a dozen generic cells whose area and timing only compare RTL versions with
# each other, no physical data, and the simulation models in tutorial_cells.v.
#
# VT picks the threshold flavour (svt, lvt, hvt) and CORNER the timing corner of its Liberty file
# (slow_vdd1v0, slow_vdd1v2, fast_vdd1v0, fast_vdd1v2). RC_CORNER picks the extraction rules used
# for wire estimation (rcworst, typical, rcbest). gsclib045_svt_v4.4 is not used: it ships LEF and
# QRC but no Liberty files. Overrides:
#   LIBS=   (empty) Genus tutorial library, even with the kit
#   LEFS=   (empty) zero wire load instead of physical-aware estimation (PLE)
VT        ?= svt
CORNER    ?= slow_vdd1v0
RC_CORNER ?= rcworst

# A directory holds the kit when it has the technology LEF.
GPDK045_PATHS := /apps/cds/installs/STRATUS2501/share/stratus/techlibs/GPDK045 \
                 $(PROJ_ROOT)/lib/GPDK045 $(PROJ_ROOT)/lib
gpdk045_in     = $(wildcard $(1)/gpdk/lef/gsclib045_tech.lef)
GPDK045       ?= $(firstword $(foreach d,$(GPDK045_PATHS),$(if $(call gpdk045_in,$(d)),$(d))))

GSC_SUFFIX_svt :=
GSC_SUFFIX_lvt := _lvt
GSC_SUFFIX_hvt := _hvt
GSC_LEF_svt    := gsclib045_macro.lef
GSC_LEF_lvt    := gsclib045_lvt_macro.lef
GSC_LEF_hvt    := gsclib045_hvt_macro.lef

ifneq ($(call gpdk045_in,$(GPDK045)),)
GSC_DIR      = $(GPDK045)/gsclib045_$(VT)
LIBS        ?= $(GSC_DIR)/timing/$(CORNER)_basicCells$(GSC_SUFFIX_$(VT)).lib
LEFS        ?= $(GPDK045)/gpdk/lef/gsclib045_tech.lef $(GSC_DIR)/lef/$(GSC_LEF_$(VT))
QRC         ?= $(GPDK045)/gpdk/qrc/$(RC_CORNER)/qrcTechFile
# Verilog models of the cells, for gate-level simulation, of the same corner as the Liberty file.
CELL_MODELS ?= $(GSC_DIR)/verilog/$(CORNER)_basicCells$(GSC_SUFFIX_$(VT)).v
endif

TUTORIAL_CELLS := $(PROJ_ROOT)/syn/tech/tutorial_cells.v

# Empty LIBS selects the tutorial library: Genus finds it, and only its own models simulate it.
TECH_TUTORIAL = $(if $(strip $(LIBS)),,1)
TECH_NAME     = $(if $(TECH_TUTORIAL),Genus tutorial library$(if $(call gpdk045_in,$(GPDK045)),, \
                  (no GPDK045 in $(or $(GPDK045),$(GPDK045_PATHS)))),$(if $(filter file,$(origin LIBS)), \
                  GPDK045 gsclib045_$(VT) $(CORNER) ($(GPDK045)),$(LIBS)))
TECH_CORNER   = $(if $(TECH_TUTORIAL),tutorial,$(CORNER))
# Cell set of a netlist: make syn writes it next to the netlist, sta and gls compare it.
TECH_CELLS    = $(if $(TECH_TUTORIAL),tutorial,$(if $(filter file,$(origin LIBS)),gsclib045_$(VT),$(notdir $(LIBS))))
TECH_MODELS   = $(if $(TECH_TUTORIAL),$(TUTORIAL_CELLS),$(CELL_MODELS))

# Recipe lines that show the technology and stop when a GPDK045= given on the command line has no
# kit, or a technology file is missing or not readable.
define TECH_CHECK
@echo "[$@] Technology: $(strip $(TECH_NAME))"
@test "$(origin GPDK045)" = file -o -n "$(call gpdk045_in,$(GPDK045))" || \
  { echo "[$@] No GPDK045 kit in GPDK045=$(GPDK045) (gpdk/lef/gsclib045_tech.lef missing)" >&2; exit 1; }
@for f in $(LIBS) $(LEFS) $(if $(LEFS),$(QRC)); do test -r "$$f" || \
  { echo "[$@] Cannot read $$f (check VT, CORNER, RC_CORNER and the cidigital group)" >&2; exit 1; }; done
endef

# Recipe line that stops when the netlist in $(1)/outputs was synthesized with other cells.
define NETLIST_CHECK
@test "$$(cat $(1)/outputs/cells 2>/dev/null)" = "$(TECH_CELLS)" || { echo "[$@] The netlist in" \
  "$(1) has the cells of '$$(cat $(1)/outputs/cells 2>/dev/null || echo unknown)', this run" \
  "'$(TECH_CELLS)': run make syn again, or pick the same technology" >&2; exit 1; }
endef
