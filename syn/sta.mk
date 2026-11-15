# Static timing analysis of the synthesized netlist with the Genus timer, included by the top-level
# Makefile. Genus checks setup and design rules only; hold needs Tempus, not available yet.
#
# The netlist and the SDC come from `make syn` with the same TOP. CORNER can differ from the one
# of the synthesis: the same netlist is then timed with the Liberty file of that corner.

STA_NETLIST ?= $(SYN_RUN_DIR)/outputs/$(TOP).v
STA_SDC     ?= $(SYN_RUN_DIR)/outputs/$(TOP).sdc
STA_RUN_DIR  = $(BUILD_DIR)/sta/$(TOP)/$(TECH_CORNER)

.PHONY: sta

sta:
	$(TECH_CHECK)
	@test -r "$(STA_NETLIST)" || { echo "[sta] No netlist $(STA_NETLIST):" \
	  "run make syn BLOCK=$(BLOCK) TOP=$(TOP) first" >&2; exit 1; }
ifeq ($(origin STA_NETLIST),file)
	$(call NETLIST_CHECK,$(SYN_RUN_DIR))
endif
	@mkdir -p $(STA_RUN_DIR)
	cd $(STA_RUN_DIR) && \
	  STA_TOP=$(TOP) STA_NETLIST=$(abspath $(STA_NETLIST)) STA_SDC=$(abspath $(STA_SDC)) \
	  STA_CORNER=$(TECH_CORNER) \
	  SYN_LIBS="$(abspath $(LIBS))" SYN_LEFS="$(abspath $(LEFS))" SYN_QRC="$(abspath $(QRC))" \
	  $(GENUS) -batch -no_gui -abort_on_error -overwrite -log genus \
	    -files $(PROJ_ROOT)/syn/genus/sta.tcl
	@echo "[sta] Reports in $(STA_RUN_DIR)/reports"
