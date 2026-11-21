# Simulation, included by the top-level Makefile. Usage: scripts/README.md.
#
# One `make sim` for every simulator: SIM picks scripts/sim/<SIM>/sim.mk, which only knows how to
# compile and run. What runs, the co-simulation against Spike, sim-list and regress live here, so
# they behave the same whatever the simulator.
#
# Directed testbench (TB=): verif/unit/<block>/<TB>.sv. The directory names the block, whose RTL
# file lists come from the top-level Makefile, and the last module of the file is the top.
# UVM test (UVM= TEST=): verif/uvm/<env>/<env>.f with the top tb_<env>; the block is the first word
# of the environment name (core_pc -> core).
# Co-simulation (SW=): a program from sw/tests runs on the testbench (tb_rv32_core_cosim by default)
# and on Spike, and the two retirement traces are compared.

SIM       ?= xrun
TB        ?=
UVM       ?=
TEST      ?=
SEED      ?= 1
VERBOSITY ?= UVM_MEDIUM
PLUSARGS  ?=
WAVES     ?= 0
GUI       ?= 0
COV       ?= 0
GLS       ?= 0
SDF       ?= 0
LIST      ?= $(PROJ_ROOT)/verif/regress/smoke.list
JOBS      ?= 1

SIM_TOOLS  = $(notdir $(patsubst %/,%,$(dir $(wildcard $(PROJ_ROOT)/scripts/sim/*/sim.mk))))

# ---- Co-simulation against Spike ----------------------------------------------------------------
#
# Both sides run the same ELF, Spike from the ELF and the testbench from the $readmemh image of it,
# with memory at the same base address. Spike logs every commit (--log-commits), the testbench logs
# every retirement, and check_sim.py compares the two with scripts/utils/cmp_trace.py.

RISCV        ?= $(BUILD_DIR)/riscv
SPIKE        ?= $(RISCV)/bin/spike
SPIKE_ISA    ?= rv32i_zicsr
# Machine mode only, like the core: Spike would otherwise implement S and U as well and report
# them in misa (0x40140100 instead of 0x40000100).
SPIKE_PRIV   ?= m
SPIKE_LOG     = $(SW_BUILD)/$(SW).spike.log
COSIM_TIMEOUT?= 1000000

# Memory wait states on the data port. Zero is the fast model: granted at once, response the next
# cycle. A nonzero COSIM_WAIT_SEED makes the waits pseudo-random up to those maxima.
COSIM_GNT_WAIT  ?= 0
COSIM_RSP_WAIT  ?= 0
COSIM_WAIT_SEED ?= 0

ifneq ($(strip $(SW)),)
TB          := $(or $(TB),tb_rv32_core_cosim)
COSIM_WAITS  = $(if $(filter-out 0,$(COSIM_GNT_WAIT) $(COSIM_RSP_WAIT) $(COSIM_WAIT_SEED)),_w$(COSIM_GNT_WAIT)-$(COSIM_RSP_WAIT)-$(COSIM_WAIT_SEED))
# The testbench writes the trace into its run directory; TOHOST is read from the symbol table
# when the recipe runs, after the program is built.
COSIM_ARGS   = +HEX=$(SW_HEX) +TRACE=trace.txt +TIMEOUT=$(COSIM_TIMEOUT) \
               +GNT_WAIT=$(COSIM_GNT_WAIT) +RSP_WAIT=$(COSIM_RSP_WAIT) +WAIT_SEED=$(COSIM_WAIT_SEED) \
               +TOHOST=$$(awk '$$3 == "tohost" { print $$1 }' $(SW_SYM))
COSIM_CHECK  = --cosim $(SPIKE_LOG) trace.txt --start $(RAM_BASE)
endif

# Builds the program and its Spike log. Parallel regression runs of the same program would race on
# build/sw, so the build is a sub-make under a lock per program.
define COSIM_PREPARE
	@mkdir -p $(SW_BUILD)
	@flock $(SW_BUILD)/.$(SW).lock $(MAKE) --no-print-directory SW=$(SW) sw-build cosim-spike
endef

.PHONY: cosim-spike

cosim-spike: $(SPIKE_LOG)

# Spike exits with the program's own exit code, which crt0 takes from main: a nonzero one means a
# CHECK in the program failed on the reference itself, so the program is wrong, not the core.
$(SPIKE_LOG): $(SW_ELF)
	@[ -x "$(SPIKE)" ] || { echo "[sim] $(SPIKE) not found, run ./setup.sh first" >&2; exit 1; }
	@echo "[sim] Spike: $(SW)"
	@$(SPIKE) --isa=$(SPIKE_ISA) --priv=$(SPIKE_PRIV) --log-commits --log=$@ $< || { \
	  code=$$?; rm -f $@; \
	  echo "[sim] FAIL $(SW): check $$code failed on Spike itself, so the program is wrong" >&2; \
	  exit $$code; }

# ---- What runs ----------------------------------------------------------------------------------

SIM_TB_FILE = $(firstword $(wildcard $(PROJ_ROOT)/verif/unit/*/$(TB).sv))
SIM_UVM_DIR = $(PROJ_ROOT)/verif/uvm/$(UVM)

ifneq ($(strip $(UVM)),)
SIM_BLOCK   = $(firstword $(subst _, ,$(UVM)))
SIM_TOP     = tb_$(UVM)
SIM_NAME    = $(TEST)_s$(SEED)
else
SIM_BLOCK   = $(notdir $(patsubst %/,%,$(dir $(SIM_TB_FILE))))
SIM_TOP     = $(shell sed -n 's/^\s*module\s\+\(\w\+\).*/\1/p' $(SIM_TB_FILE) | tail -1)
SIM_NAME    = $(if $(strip $(SW)),cosim_$(SW)$(COSIM_WAITS),$(TB))
endif

SIM_RUN_DIR = $(BUILD_DIR)/sim/$(SIM)/$(SIM_NAME)$(if $(filter 1,$(GLS)),_gls$(if $(filter 1,$(SDF)),_sdf))

# Checks shared by every simulator, run first by its sim recipe.
define SIM_CHECK
	@test -n "$(strip $(TB)$(UVM))" || \
	  { echo "[sim] Choose TB=<testbench>, UVM=<env> TEST=<test> or SW=<program> (see make sim-list)" >&2; exit 1; }
	@test -z "$(TB)" -o -n "$(SIM_TB_FILE)" || \
	  { echo "[sim] No testbench verif/unit/*/$(TB).sv (see make sim-list)" >&2; exit 1; }
	@test -z "$(UVM)" -o -f "$(SIM_UVM_DIR)/$(UVM).f" || \
	  { echo "[sim] No UVM environment verif/uvm/$(UVM)/$(UVM).f (see make sim-list)" >&2; exit 1; }
	@test -z "$(UVM)" -o -n "$(TEST)" || \
	  { echo "[sim] UVM=$(UVM) needs TEST=<test> (see make sim-list)" >&2; exit 1; }
	@test -z "$(SW)" -o -z "$(UVM)" || \
	  { echo "[sim] SW= runs on a directed testbench, not with UVM=" >&2; exit 1; }
	@test -n "$(RTL_FLIST_$(SIM_BLOCK))" || \
	  { echo "[sim] Block '$(SIM_BLOCK)' of $(TB)$(UVM) is not in the Makefile block table" >&2; exit 1; }
endef

# Runs the simulator command $(1) in the run directory, then decides PASS or FAIL from its log $(2):
# check_sim.py prints the one [sim] line that regress.py reads.
define SIM_RUN
	cd $(SIM_RUN_DIR) && { $(1); \
	  python3 $(PROJ_ROOT)/scripts/sim/check_sim.py $(2) $$? $(notdir $(SIM_RUN_DIR)) \
	    $(if $(strip $(UVM)),--uvm) $(COSIM_CHECK); }
endef

# ---- Simulator ----------------------------------------------------------------------------------

ifeq ($(wildcard $(PROJ_ROOT)/scripts/sim/$(SIM)/sim.mk),)
$(error SIM=$(SIM): no scripts/sim/$(SIM)/sim.mk, choose one of: $(SIM_TOOLS))
endif
include $(PROJ_ROOT)/scripts/sim/$(SIM)/sim.mk

# ---- Lists and regressions ----------------------------------------------------------------------

.PHONY: sim-list regress

sim-list:
	@echo "Simulators (SIM=): $(SIM_TOOLS)"
	@echo "Directed testbenches (TB=):"
	@$(foreach d,$(wildcard $(PROJ_ROOT)/verif/unit/*/),echo "  $(notdir $(patsubst %/,%,$(d))):" \
	  $(basename $(notdir $(wildcard $(d)tb_*.sv)));)
	@echo "UVM environments (UVM=) and their tests (TEST=):"
	@$(foreach f,$(wildcard $(PROJ_ROOT)/verif/uvm/*/*.f),echo "  $(notdir $(basename $(f))):" \
	  $(filter-out %_base_test,$(basename $(notdir $(wildcard $(dir $(f))tests/*_test.svh))));)
	@echo "Programs for co-simulation (SW=):" $(notdir $(patsubst %/,%,$(wildcard $(PROJ_ROOT)/sw/tests/*/))) \
	  "random<seed> rdv-<test>-<seed>"
	@echo "riscv-dv tests (SW=rdv-<test>-<seed>):" \
	  $$(sed -n 's/^- test: *//p' $(PROJ_ROOT)/verif/riscv-dv/testlist.yaml $(PROJ_ROOT)/vendor/riscv-dv/yaml/base_testlist.yaml 2>/dev/null | sort -u)
	@echo "Regression lists (LIST=):" $(patsubst $(PROJ_ROOT)/%,%,$(wildcard $(PROJ_ROOT)/verif/regress/*.list))

# SIM and every other variable given here reach each run through MAKEFLAGS.
regress:
	@python3 $(PROJ_ROOT)/scripts/sim/regress.py --jobs $(JOBS) --out $(BUILD_DIR)/regress/$(SIM) $(LIST)
