# Cadence Xcelium (xrun), the default simulator: included by scripts/sim/sim.mk when SIM=xrun.
# Everything but compiling and running (what runs, co-simulation, regress) is in scripts/sim/sim.mk.
#
# Gate level (GLS=1): the RTL is replaced by the netlist `make syn` wrote for TOP (default: the
# block's top), the packages and interfaces of the block and the cell models; SDF=1 adds the delays
# of SDF_FILE.
# Testbench-only file lists (SIM_FLIST_<block> in the top-level Makefile: verification IP, or the RTL
# of another block a testbench runs against) are compiled after the design and before the testbench,
# at RTL and at gate level. Synthesis never reads them.

XRUN      ?= xrun
XRUN_OPTS ?=

# Gate level: TOP given on the command line, or the block's top.
GLS_TOP     = $(if $(filter command line environment override,$(origin TOP)),$(TOP),$(RTL_TOP_$(SIM_BLOCK)))
GLS_NETLIST = $(BUILD_DIR)/syn/$(GLS_TOP)/outputs/$(GLS_TOP).v
SDF_FILE   ?= $(BUILD_DIR)/syn/$(GLS_TOP)/outputs/$(GLS_TOP).sdf
SDF_SCOPE  ?= $(SIM_TOP).dut

# ---- xrun command line --------------------------------------------------------------------------

ifeq ($(GLS),1)
# Packages, interfaces and include directories of the block (the testbenches use them), the
# netlist, and the cell models as a library: zero delay, or the SDF delays with timing checks.
SIM_DESIGN = -f gls_pkgs.f $(GLS_NETLIST) -v $(abspath $(TECH_MODELS)) -define GLS \
             $(if $(filter 1,$(SDF)),-sdf_cmd_file sdf.cmd -neg_tchk,-nospecify -notimingchecks)
else
SIM_DESIGN = $(foreach f,$(RTL_FLIST_$(SIM_BLOCK)),-f $(f))
endif

SIM_FLISTS = $(foreach f,$(SIM_FLIST_$(SIM_BLOCK)),-f $(f))

SIM_ARGS = -64bit -sv -timescale 1ns/1ps -licqueue -l xrun.log -svseed $(SEED) \
           $(SIM_DESIGN) $(SIM_FLISTS) $(SIM_TB) -top $(SIM_TOP) \
XRUN_TB    = $(if $(strip $(UVM)),-f $(SIM_UVM_DIR)/$(UVM).f,$(SIM_TB_FILE))

SIM_ARGS = -64bit -sv -timescale 1ns/1ps -licqueue -l xrun.log -svseed $(SEED) \
           $(SIM_DESIGN) $(XRUN_TB) -top $(SIM_TOP) \
           $(if $(strip $(UVM)),-uvm -uvmhome CDNS-1.2 +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY)) \
           $(if $(filter 1,$(WAVES)),-access +r -input $(PROJ_ROOT)/scripts/sim/xrun/waves.tcl) \
           $(if $(filter 1,$(GUI)),-gui -access +rwc) \
           $(if $(filter 1,$(COV)),-coverage all -covoverwrite -covtest $(SIM_NAME)) \
           $(COSIM_ARGS) $(PLUSARGS) $(XRUN_OPTS)

# ---- Targets ------------------------------------------------------------------------------------

.PHONY: sim gls

sim:
	$(SIM_CHECK)
ifeq ($(GLS),1)
	@test -r "$(GLS_NETLIST)" || { echo "[sim] No netlist $(GLS_NETLIST):" \
	  "run make syn BLOCK=$(SIM_BLOCK) TOP=$(GLS_TOP) first" >&2; exit 1; }
	$(call NETLIST_CHECK,$(BUILD_DIR)/syn/$(GLS_TOP))
	@test -n "$(TECH_MODELS)" && test -r "$(TECH_MODELS)" || { echo "[sim] No Verilog cell" \
	  "models for $(TECH_NAME): set CELL_MODELS=<file.v>" >&2; exit 1; }
endif
ifneq ($(strip $(SW)),)
	$(COSIM_PREPARE)
endif
	@mkdir -p $(SIM_RUN_DIR)
ifeq ($(GLS),1)
	@sed -n -e '/^\s*+incdir+/p' -e '/_\(pkg\|intf\)\.sv\s*$$/p' $(RTL_FLIST_$(SIM_BLOCK)) > $(SIM_RUN_DIR)/gls_pkgs.f
ifeq ($(SDF),1)
	@test -r "$(SDF_FILE)" || { echo "[sim] No SDF $(SDF_FILE)" >&2; exit 1; }
	cd $(SIM_RUN_DIR) && xmsdfc -output $(GLS_TOP).sdf.X $(abspath $(SDF_FILE)) > xmsdfc.log
	@printf 'COMPILED_SDF_FILE = "%s",\nSCOPE = %s,\nMTM_CONTROL = "MAXIMUM",\nLOG_FILE = "sdf.log";\n' \
	  "$(SIM_RUN_DIR)/$(GLS_TOP).sdf.X" "$(SDF_SCOPE)" > $(SIM_RUN_DIR)/sdf.cmd
endif
endif
	$(call SIM_RUN,$(XRUN) $(SIM_ARGS),xrun.log)

gls:
	@$(MAKE) --no-print-directory sim GLS=1
