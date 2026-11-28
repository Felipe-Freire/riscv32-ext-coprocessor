# Technology of synthesis, STA and gate-level simulation. Included by the top-level Makefile.
#
# TECH picks the kit:
#   freepdk45  (default) FreePDK45 with the NanGate Open Cell Library, as packaged by
#              mflowgen/freepdk-45nm. `make freepdk45` downloads it to lib/freepdk45 (ignored by git,
#              see syn/tech/freepdk45/freepdk45.mk); FREEPDK45=<dir> points elsewhere. The PDK is
#              open and cannot be fabricated: area and timing are estimates. CORNER picks the
#              Liberty corner (typical 1.1 V 25 C, the default, the corner of the analytical
#              timing of the OpenRAM macros; slow 0.95 V 125 C; fast 1.25 V 0 C), and the wires
#              are estimated from the LEF with the capacitance table of the kit.
#   gpdk045    Cadence GPDK045 (gsclib045), on standby until the lab memory libraries are checked.
#              The kit is the first of these directories that holds it:
#                1. /apps/cds/installs/STRATUS2501/share/stratus/techlibs/GPDK045 (the Stratus install)
#                2. lib/GPDK045 in the project, or lib/ itself (a local copy, ignored by git: the kit
#                   is under NDA)
#              GPDK045=<dir> skips the search. VT picks the threshold flavour (svt, lvt, hvt),
#              CORNER the Liberty corner (slow_vdd1v0, slow_vdd1v2, fast_vdd1v0, fast_vdd1v2) and
#              RC_CORNER the extraction rules of the wire estimation (rcworst, typical, rcbest).
#              gsclib045_svt_v4.4 is not used: it ships LEF and QRC but no Liberty files.
#
# With no kit of the chosen TECH, the flows use the Genus tutorial library: a dozen generic cells
# whose area and timing only compare RTL versions with each other, no physical data, and the
# simulation models in tutorial_cells.v. Overrides:
#   LIBS=   (empty) Genus tutorial library, even with the kit
#   LEFS=   (empty) zero wire load instead of physical-aware estimation (PLE)
TECH  ?= freepdk45
TECHS := freepdk45 gpdk045

# ---- FreePDK45 (NanGate Open Cell Library) -----------------------------------------------------

FREEPDK45_PATHS := $(PROJ_ROOT)/lib/freepdk45
freepdk45_in     = $(wildcard $(1)/rtk-tech.lef)
FREEPDK45       ?= $(firstword $(foreach d,$(FREEPDK45_PATHS),$(if $(call freepdk45_in,$(d)),$(d))))

FREEPDK45_CORNERS     := typical slow fast
FREEPDK45_LIB_typical := stdcells.lib
FREEPDK45_LIB_slow    := stdcells-wc.lib
FREEPDK45_LIB_fast    := stdcells-bc.lib

# ---- OpenRAM SRAM macros of FreePDK45 ----------------------------------------------------------
# The flows read the views kept in git, OPENRAM45_VIEWS/<macro>/ (syn/tech/openram45/views): the
# Liberty file, LEF and Verilog model of each macro, about 30 KB, so a clone needs no OpenRAM run.
# `make openram` (syn/tech/openram45/openram45.mk) regenerates one macro per configuration in
# syn/tech/openram45/ into lib/openram45/<macro>/ (ignored by git, with the GDS and netlists;
# OPENRAM45=<dir> points elsewhere) and copies those views back to OPENRAM45_VIEWS. Its Liberty
# file has OpenRAM's analytical timing at TT (OPENRAM45_TT). `make openram-char` adds
# OPENRAM45_VIEWS/<macro>/spice/, with ngspice characterizations at the PVT of the NanGate corners.
# The Liberty files are named the way OpenRAM names its corners, <process>_<supply>V_<temperature>C
# (syn/tech/openram45/README.md).
#
# openram45_lib gives the Liberty file of a macro at CORNER: the SPICE one of that corner when
# make openram-char wrote it, the analytical TT one otherwise (so a slow or fast run before the
# characterization pairs those cells with TT macros).

OPENRAM45_PATHS          := $(PROJ_ROOT)/lib/openram45
OPENRAM45                ?= $(firstword $(OPENRAM45_PATHS))
OPENRAM45_VIEWS          ?= $(PROJ_ROOT)/syn/tech/openram45/views
OPENRAM45_MACROS         := $(basename $(notdir $(wildcard $(PROJ_ROOT)/syn/tech/openram45/*.py)))
OPENRAM45_TT             := TT_1p1V_25C
OPENRAM45_CORNER_typical := TT_1p1V_25C
OPENRAM45_CORNER_slow    := SS_0p95V_125C
OPENRAM45_CORNER_fast    := FF_1p25V_0C
openram45_lib             = $(firstword $(wildcard $(OPENRAM45_VIEWS)/$(1)/spice/$(1)_$(OPENRAM45_CORNER_$(CORNER)).lib) \
                                        $(OPENRAM45_VIEWS)/$(1)/$(1)_$(OPENRAM45_TT).lib)

# ---- GPDK045 (standby) -------------------------------------------------------------------------

GPDK045_PATHS := /apps/cds/installs/STRATUS2501/share/stratus/techlibs/GPDK045 \
                 $(PROJ_ROOT)/lib/GPDK045 $(PROJ_ROOT)/lib
gpdk045_in     = $(wildcard $(1)/gpdk/lef/gsclib045_tech.lef)
GPDK045       ?= $(firstword $(foreach d,$(GPDK045_PATHS),$(if $(call gpdk045_in,$(d)),$(d))))

GPDK045_CORNERS := slow_vdd1v0 slow_vdd1v2 fast_vdd1v0 fast_vdd1v2
GSC_SUFFIX_svt  :=
GSC_SUFFIX_lvt  := _lvt
GSC_SUFFIX_hvt  := _hvt
GSC_LEF_svt     := gsclib045_macro.lef
GSC_LEF_lvt     := gsclib045_lvt_macro.lef
GSC_LEF_hvt     := gsclib045_hvt_macro.lef

# ---- Selected technology -----------------------------------------------------------------------
# TECH_KIT_VAR is the variable that holds the kit directory, TECH_KIT that directory when it holds
# the kit (empty otherwise), TECH_KIT_CELLS the cell set of a netlist synthesized with it.

ifeq ($(TECH),freepdk45)
CORNER         ?= typical
TECH_CORNERS    = $(FREEPDK45_CORNERS)
TECH_KIT_VAR   := FREEPDK45
TECH_KIT        = $(call freepdk45_in,$(FREEPDK45))
TECH_KIT_NAME   = FreePDK45 NanGate $(CORNER) ($(FREEPDK45))
TECH_KIT_CELLS := NangateOpenCellLibrary
TECH_KIT_HINT  := run make freepdk45
ifneq ($(call freepdk45_in,$(FREEPDK45)),)
LIBS           ?= $(FREEPDK45)/$(FREEPDK45_LIB_$(CORNER))
LEFS           ?= $(FREEPDK45)/rtk-tech.lef $(FREEPDK45)/stdcells.lef
# No QRC rules in the kit: PLE takes the capacitance per length from this table.
CAPTBL         ?= $(FREEPDK45)/rtk-typical.captable
# One set of Verilog models for every corner (the timing comes from the SDF).
CELL_MODELS    ?= $(FREEPDK45)/stdcells.v
endif
# Outside `ifdef TETRAMAX the NanGate models add ng_xbuf cells that drive the reset and set inputs
# of the flops back from inside (ng_xbuf(RN, RNx, 1'b1)). Xcelium joins that driver to the net of
# the port, which then settles at X while the reset is active and never resets the flop. The
# timing checks do not use those cells, so the models are compiled without them.
CELL_MODEL_DEFINES := TETRAMAX
# Views of the OpenRAM macros at CORNER, for the flows that read the memory macros: Liberty for
# timing and area (openram45_lib), LEF for the placement estimate (same layers as the tech LEF),
# Verilog models for simulation and gate level.
MEM_LIBS       ?= $(foreach m,$(OPENRAM45_MACROS),$(call openram45_lib,$(m)))
MEM_LEFS       ?= $(foreach m,$(OPENRAM45_MACROS),$(OPENRAM45_VIEWS)/$(m)/$(m).lef)
MEM_MODELS     ?= $(foreach m,$(OPENRAM45_MACROS),$(OPENRAM45_VIEWS)/$(m)/$(m).v)

else ifeq ($(TECH),gpdk045)
VT             ?= svt
CORNER         ?= slow_vdd1v0
RC_CORNER      ?= rcworst
TECH_CORNERS    = $(GPDK045_CORNERS)
TECH_KIT_VAR   := GPDK045
TECH_KIT        = $(call gpdk045_in,$(GPDK045))
TECH_KIT_NAME   = GPDK045 gsclib045_$(VT) $(CORNER) ($(GPDK045))
TECH_KIT_CELLS  = gsclib045_$(VT)
TECH_KIT_HINT  := no kit in $(GPDK045_PATHS)
ifneq ($(call gpdk045_in,$(GPDK045)),)
GSC_DIR         = $(GPDK045)/gsclib045_$(VT)
LIBS           ?= $(GSC_DIR)/timing/$(CORNER)_basicCells$(GSC_SUFFIX_$(VT)).lib
LEFS           ?= $(GPDK045)/gpdk/lef/gsclib045_tech.lef $(GSC_DIR)/lef/$(GSC_LEF_$(VT))
QRC            ?= $(GPDK045)/gpdk/qrc/$(RC_CORNER)/qrcTechFile
# Verilog models of the cells, for gate-level simulation, of the same corner as the Liberty file.
CELL_MODELS    ?= $(GSC_DIR)/verilog/$(CORNER)_basicCells$(GSC_SUFFIX_$(VT)).v
endif

else
$(error Unknown TECH '$(TECH)', choose one of: $(TECHS))
endif

TUTORIAL_CELLS := $(PROJ_ROOT)/syn/tech/tutorial_cells.v

# Empty LIBS selects the tutorial library: Genus finds it, and only its own models simulate it.
TECH_TUTORIAL = $(if $(strip $(LIBS)),,1)
TECH_NAME     = $(if $(TECH_TUTORIAL),Genus tutorial library$(if $(TECH_KIT),, \
                  (no $(TECH) kit in $(or $($(TECH_KIT_VAR)),$($(TECH_KIT_VAR)_PATHS)): $(TECH_KIT_HINT))), \
                  $(if $(filter file,$(origin LIBS)),$(TECH_KIT_NAME),$(LIBS)))
TECH_CORNER   = $(if $(TECH_TUTORIAL),tutorial,$(CORNER))
TECH_MODELS   = $(if $(TECH_TUTORIAL),$(TUTORIAL_CELLS),$(CELL_MODELS))

# ---- Memory technology -------------------------------------------------------------------------
# MEM_TECH picks the version of the technology primitives (rtl/prim, see rtl/prim/README.md):
#   generic    the behavioral models of rtl/prim/prim.f: flip-flop arrays, for simulation only
#   openram45  rtl/prim/openram45/prim.f, built from the OpenRAM macros of FreePDK45
# Empty (the default), each flow takes its own: generic for RTL simulation (MEM_TECH_FLOW of
# sim.mk), and for synthesis, STA and gate level the memories of the technology (MEM_TECH_IMPL):
# openram45 with the FreePDK45 kit, generic with GPDK045, which has no memories, or with the
# tutorial library. The Makefile hands the primitive file list to the flows as PRIM_FLIST, and the
# macro views (Liberty, LEF, Verilog models) come in with openram45 only.
MEM_TECHS       := generic openram45
MEM_TECH        ?=
MEM_TECH_IMPL    = $(if $(and $(filter freepdk45,$(TECH)),$(if $(TECH_TUTORIAL),,1)),openram45,generic)
MEM_TECH_USED    = $(or $(MEM_TECH),$(MEM_TECH_FLOW),generic)
PRIM_FLIST       = $(PROJ_ROOT)/rtl/prim/$(if $(filter openram45,$(MEM_TECH_USED)),openram45/)prim.f
export PRIM_FLIST
MEM_TECH_LIBS    = $(if $(filter openram45,$(MEM_TECH_USED)),$(MEM_LIBS))
MEM_TECH_LEFS    = $(if $(and $(filter openram45,$(MEM_TECH_USED)),$(strip $(LEFS))),$(MEM_LEFS))
MEM_TECH_MODELS  = $(if $(filter openram45,$(MEM_TECH_USED)),$(MEM_MODELS))

# Cell set of a netlist: make syn writes it next to the netlist, sta and gls compare it. The memory
# technology is part of it: a netlist with macros needs their views.
TECH_CELLS    = $(if $(TECH_TUTORIAL),tutorial,$(if $(filter file,$(origin LIBS)),$(TECH_KIT_CELLS),$(notdir $(LIBS))))$(if $(MEM_TECH_LIBS), + $(MEM_TECH_USED))

# Recipe lines that stop on an unknown MEM_TECH, on openram45 without the FreePDK45 views, and on a
# missing macro view.
define MEM_CHECK
@test -n "$(filter $(MEM_TECH_USED),$(MEM_TECHS))" || \
  { echo "[$@] Unknown MEM_TECH '$(MEM_TECH_USED)', choose one of: $(MEM_TECHS)" >&2; exit 1; }
@test "$(MEM_TECH_USED)" != openram45 -o -n "$(strip $(MEM_MODELS))" || \
  { echo "[$@] MEM_TECH=openram45 needs TECH=freepdk45" >&2; exit 1; }
@for f in $(MEM_TECH_MODELS); do test -r "$$f" || \
  { echo "[$@] Cannot read the macro model $$f (syn/tech/openram45/views, see make openram)" >&2; exit 1; }; done
endef

# Recipe lines that show the technology and stop on a CORNER the kit does not have, on a kit
# directory given on the command line that holds no kit, or on a technology file that is missing
# or not readable.
define TECH_CHECK
@echo "[$@] Technology: $(strip $(TECH_NAME)); memories: $(MEM_TECH_USED)"
@test -n "$(TECH_TUTORIAL)" -o -n "$(filter $(CORNER),$(TECH_CORNERS))" -o "$(origin LIBS)" != file || \
  { echo "[$@] Unknown CORNER '$(CORNER)' for TECH=$(TECH), choose one of: $(TECH_CORNERS)" >&2; exit 1; }
@test "$(origin $(TECH_KIT_VAR))" = file -o -n "$(TECH_KIT)" || \
  { echo "[$@] No $(TECH) kit in $(TECH_KIT_VAR)=$($(TECH_KIT_VAR))" >&2; exit 1; }
@for f in $(LIBS) $(LEFS) $(if $(LEFS),$(QRC) $(CAPTBL)) $(MEM_TECH_LIBS) $(MEM_TECH_LEFS); do test -r "$$f" || \
  { echo "[$@] Cannot read $$f (check TECH, CORNER, VT, RC_CORNER and the read permission of the kit)" >&2; exit 1; }; done
endef

# Recipe line that stops when the netlist in $(1)/outputs was synthesized with other cells.
define NETLIST_CHECK
@test "$$(cat $(1)/outputs/cells 2>/dev/null)" = "$(TECH_CELLS)" || { echo "[$@] The netlist in" \
  "$(1) has the cells of '$$(cat $(1)/outputs/cells 2>/dev/null || echo unknown)', this run" \
  "'$(TECH_CELLS)': run make syn again, or pick the same technology" >&2; exit 1; }
endef
