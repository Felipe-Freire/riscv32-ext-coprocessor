# Simulation with Cadence Xcelium (xrun), included by the top-level Makefile. Usage: scripts/README.md.
#
# Directed testbench (TB=): verif/unit/<block>/<TB>.sv. The directory names the block, whose RTL
# file lists come from the top-level Makefile, and the last module of the file is the top.
# UVM test (UVM= TEST=): verif/uvm/<env>/<env>.f with the top tb_<env>; the block is the first word
# of the environment name (core_pc -> core).
# Gate level (GLS=1): the RTL is replaced by the netlist `make syn` wrote for TOP (default: the
# block's top), the packages and interfaces of the block and the cell models; SDF=1 adds the delays
# of SDF_FILE.
# Testbench-only file lists (SIM_FLIST_<block> in the top-level Makefile: verification IP, or the RTL
# of another block a testbench runs against) are compiled after the design and before the testbench,
# at RTL and at gate level. Synthesis never reads them.

XRUN      ?= xrun
TB        ?=
UVM       ?=
TEST      ?=
SEED      ?= 1
VERBOSITY ?= UVM_MEDIUM
PLUSARGS  ?=
XRUN_OPTS ?=
WAVES     ?= 0
GUI       ?= 0
COV       ?= 0
GLS       ?= 0
SDF       ?= 0
LIST      ?= $(PROJ_ROOT)/verif/regress/smoke.list
JOBS      ?= 1

# ---- What runs ----------------------------------------------------------------------------------

SIM_TB_FILE = $(firstword $(wildcard $(PROJ_ROOT)/verif/unit/*/$(TB).sv))
SIM_UVM_DIR = $(PROJ_ROOT)/verif/uvm/$(UVM)

ifneq ($(strip $(UVM)),)
SIM_BLOCK   = $(firstword $(subst _, ,$(UVM)))
SIM_TOP     = tb_$(UVM)
SIM_TB      = -f $(SIM_UVM_DIR)/$(UVM).f
SIM_NAME    = $(TEST)_s$(SEED)
else
SIM_BLOCK   = $(notdir $(patsubst %/,%,$(dir $(SIM_TB_FILE))))
SIM_TOP     = $(shell sed -n 's/^\s*module\s\+\(\w\+\).*/\1/p' $(SIM_TB_FILE) | tail -1)
SIM_TB      = $(SIM_TB_FILE)
SIM_NAME    = $(TB)
endif

# Gate level: TOP given on the command line, or the block's top.
GLS_TOP     = $(if $(filter command line environment override,$(origin TOP)),$(TOP),$(RTL_TOP_$(SIM_BLOCK)))
GLS_NETLIST = $(BUILD_DIR)/syn/$(GLS_TOP)/outputs/$(GLS_TOP).v
SDF_FILE   ?= $(BUILD_DIR)/syn/$(GLS_TOP)/outputs/$(GLS_TOP).sdf
SDF_SCOPE  ?= $(SIM_TOP).dut

SIM_RUN_DIR = $(BUILD_DIR)/sim/$(SIM_NAME)$(if $(filter 1,$(GLS)),_gls$(if $(filter 1,$(SDF)),_sdf))

# ---- xrun command line --------------------------------------------------------------------------

ifeq ($(GLS),1)
# Packages, interfaces and include directories of the block (the testbenches use them), the
# netlist, and the cell models as a library: zero delay, or the SDF delays with timing checks.
SIM_DESIGN = -f gls_pkgs.f $(GLS_NETLIST) -v $(abspath $(TECH_MODELS)) -define GLS \
             $(foreach d,$(if $(TECH_TUTORIAL),,$(CELL_MODEL_DEFINES)),-define $(d)) \
             $(if $(filter 1,$(SDF)),-sdf_cmd_file sdf.cmd -neg_tchk,-nospecify -notimingchecks)
else
SIM_DESIGN = $(foreach f,$(RTL_FLIST_$(SIM_BLOCK)),-f $(f))
endif

SIM_FLISTS = $(foreach f,$(SIM_FLIST_$(SIM_BLOCK)),-f $(f))

SIM_ARGS = -64bit -sv -timescale 1ns/1ps -licqueue -l xrun.log -svseed $(SEED) \
           $(SIM_DESIGN) $(SIM_FLISTS) $(SIM_TB) -top $(SIM_TOP) \
           $(if $(strip $(UVM)),-uvm -uvmhome CDNS-1.2 +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY)) \
           $(if $(filter 1,$(WAVES)),-access +r -input $(PROJ_ROOT)/scripts/sim/xrun/waves.tcl) \
           $(if $(filter 1,$(GUI)),-gui -access +rwc) \
           $(if $(filter 1,$(COV)),-coverage all -covoverwrite -covtest $(SIM_NAME)) \
           $(PLUSARGS) $(XRUN_OPTS)

# ---- Targets ------------------------------------------------------------------------------------

.PHONY: sim gls sim-list regress

sim:
	@test -n "$(strip $(TB)$(UVM))" || \
	  { echo "[sim] Choose TB=<testbench> or UVM=<env> TEST=<test> (see make sim-list)" >&2; exit 1; }
	@test -z "$(TB)" -o -n "$(SIM_TB_FILE)" || \
	  { echo "[sim] No testbench verif/unit/*/$(TB).sv (see make sim-list)" >&2; exit 1; }
	@test -z "$(UVM)" -o -f "$(SIM_UVM_DIR)/$(UVM).f" || \
	  { echo "[sim] No UVM environment verif/uvm/$(UVM)/$(UVM).f (see make sim-list)" >&2; exit 1; }
	@test -z "$(UVM)" -o -n "$(TEST)" || \
	  { echo "[sim] UVM=$(UVM) needs TEST=<test> (see make sim-list)" >&2; exit 1; }
	@test -n "$(RTL_FLIST_$(SIM_BLOCK))" || \
	  { echo "[sim] Block '$(SIM_BLOCK)' of $(TB)$(UVM) is not in the Makefile block table" >&2; exit 1; }
ifeq ($(GLS),1)
	@test -r "$(GLS_NETLIST)" || { echo "[sim] No netlist $(GLS_NETLIST):" \
	  "run make syn BLOCK=$(SIM_BLOCK) TOP=$(GLS_TOP) first" >&2; exit 1; }
	$(call NETLIST_CHECK,$(BUILD_DIR)/syn/$(GLS_TOP))
	@test -n "$(TECH_MODELS)" && test -r "$(TECH_MODELS)" || { echo "[sim] No Verilog cell" \
	  "models for $(TECH_NAME): set CELL_MODELS=<file.v>" >&2; exit 1; }
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
	cd $(SIM_RUN_DIR) && { $(XRUN) $(SIM_ARGS); \
	  $(PYTHON) $(PROJ_ROOT)/scripts/sim/check_sim.py xrun.log $$? $(notdir $(SIM_RUN_DIR)) \
	    $(if $(strip $(UVM)),--uvm); }

gls:
	@$(MAKE) --no-print-directory sim GLS=1

sim-list:
	@echo "Directed testbenches (TB=):"
	@$(foreach d,$(wildcard $(PROJ_ROOT)/verif/unit/*/),echo "  $(notdir $(patsubst %/,%,$(d))):" \
	  $(basename $(notdir $(wildcard $(d)tb_*.sv)));)
	@echo "UVM environments (UVM=) and their tests (TEST=):"
	@$(foreach f,$(wildcard $(PROJ_ROOT)/verif/uvm/*/*.f),echo "  $(notdir $(basename $(f))):" \
	  $(filter-out %_base_test,$(basename $(notdir $(wildcard $(dir $(f))tests/*_test.svh))));)
	@echo "Regression lists (LIST=):" $(patsubst $(PROJ_ROOT)/%,%,$(wildcard $(PROJ_ROOT)/verif/regress/*.list))

regress:
	@$(PYTHON) $(PROJ_ROOT)/scripts/sim/regress.py --jobs $(JOBS) --out $(BUILD_DIR)/regress $(LIST)
