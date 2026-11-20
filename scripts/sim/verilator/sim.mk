# Verilator, the free alternative to Xcelium: included by scripts/sim/sim.mk when SIM=verilator.
# Everything but compiling and running (what runs, co-simulation, regress) is in scripts/sim/sim.mk.
#
#   make sim SIM=verilator TB=tb_rv32_alu
#   make sim SIM=verilator SW=sum
#   make regress SIM=verilator LIST=verif/regress/cosim.list JOBS=8
#
# Directed testbenches only: no UVM, gate level, coverage, waves or GUI. The model of a testbench
# is built once in build/verilator/<TB>/ and shared by every run of it; each run has its own
# directory under build/sim/verilator/, like the Xcelium runs.

VERILATOR ?= verilator
VL_FLAGS  ?= --binary --timing -j 0 -Wno-fatal

VL_BUILD   = $(BUILD_DIR)/verilator/$(TB)
VL_MODEL   = $(VL_BUILD)/$(TB)
# Rebuild when the testbench, a file list or any RTL source changes.
VL_DEPS    = $(SIM_TB_FILE) $(RTL_FLIST_$(SIM_BLOCK)) \
             $(shell find $(PROJ_ROOT)/rtl -name '*.sv' -o -name '*.svh' 2>/dev/null)

# SEED=random: +verilator+seed+0 draws one.
VL_SEED    = $(if $(filter random,$(SEED)),0,$(SEED))

VL_UNSUPPORTED = $(strip $(if $(UVM),UVM=) $(if $(filter 1,$(GLS)),GLS=1) $(if $(filter 1,$(COV)),COV=1) \
                 $(if $(filter 1,$(WAVES)),WAVES=1) $(if $(filter 1,$(GUI)),GUI=1))

.PHONY: sim sim-build gls

$(VL_MODEL): $(VL_DEPS)
	@mkdir -p $(VL_BUILD)
	$(VERILATOR) $(VL_FLAGS) --Mdir $(VL_BUILD) -o $(TB) --top-module $(SIM_TOP) \
	  $(foreach f,$(RTL_FLIST_$(SIM_BLOCK)),-f $(f)) $(SIM_TB_FILE)

sim-build: $(VL_MODEL)

# The model is built in a sub-make under a lock, so parallel regression runs of the same testbench
# build it once instead of racing on build/verilator/<TB>.
sim:
	@test -z "$(VL_UNSUPPORTED)" || \
	  { echo "[sim] SIM=verilator does not support $(VL_UNSUPPORTED): use SIM=xrun" >&2; exit 1; }
	$(SIM_CHECK)
	@mkdir -p $(BUILD_DIR)/verilator
	@flock $(VL_BUILD).lock $(MAKE) --no-print-directory sim-build TB=$(TB) || \
	  { echo "[sim] FAIL $(notdir $(SIM_RUN_DIR)): Verilator did not build $(TB)"; exit 1; }
ifneq ($(strip $(SW)),)
	$(COSIM_PREPARE)
endif
	@mkdir -p $(SIM_RUN_DIR)
	$(call SIM_RUN,{ echo "verilator seed $(SEED)"; \
	  $(VL_MODEL) +verilator+seed+$(VL_SEED) $(COSIM_ARGS) $(PLUSARGS); } > sim.log 2>&1; \
	  s=$$?; cat sim.log; (exit $$s),sim.log)

gls:
	@echo "[sim] SIM=verilator has no gate-level flow: use SIM=xrun" >&2; exit 1
