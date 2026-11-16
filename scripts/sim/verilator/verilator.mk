# Verilator flows. Included by the top-level Makefile.
#
#   make cosim TEST=sum      build the program, run it on Spike and on the RTL core, compare
#   make cosim-all           the same for every program under sw/tests (run_cosim.py)
#   make cosim-all COSIM_GNT_WAIT=3 COSIM_RSP_WAIT=3 COSIM_WAIT_SEED=1    with memory wait states
#   make vsim-unit TB=tb_rv32_core
#
# Co-simulation: both sides run the same ELF, Spike from the ELF and the core from the
# $readmemh image of it, with memory at the same base address. Spike logs every commit
# (--log-commits), the testbench logs every retirement, and scripts/utils/cmp_trace.py compares
# the two instruction by instruction.

VERILATOR    ?= verilator
RISCV        ?= $(BUILD_DIR)/riscv
SPIKE        ?= $(RISCV)/bin/spike
SPIKE_ISA    ?= rv32i_zicsr
# Machine mode only, like the core: Spike would otherwise implement S and U as well and report
# them in misa (0x40140100 instead of 0x40000100).
SPIKE_PRIV   ?= m

VL_BUILD     := $(BUILD_DIR)/verilator
VL_FLAGS     ?= --binary --timing -j 0 -Wno-fatal
COSIM_TB     := tb_rv32_core_cosim
COSIM_SRC    := $(PROJ_ROOT)/verif/unit/core/$(COSIM_TB).sv
COSIM_SIM    := $(VL_BUILD)/$(COSIM_TB)/$(COSIM_TB)
COSIM_TRACE  := $(VL_BUILD)/$(COSIM_TB)/$(TEST).trace
SPIKE_LOG    := $(SW_BUILD)/$(TEST).spike.log
COSIM_TIMEOUT?= 1000000

# Memory wait states on the data port. Zero is the fast model: granted at once, response the next
# cycle. A nonzero COSIM_WAIT_SEED makes the waits pseudo-random up to those maxima.
COSIM_GNT_WAIT  ?= 0
COSIM_RSP_WAIT  ?= 0
COSIM_WAIT_SEED ?= 0

.PHONY: cosim cosim-all cosim-build cosim-spike cosim-rtl vsim-unit

# Every directory under sw/tests, in alphabetical order.
COSIM_TESTS ?= $(sort $(notdir $(patsubst %/,%,$(dir $(wildcard $(PROJ_ROOT)/sw/tests/*/*)))))

# ---- Build the simulator ----------------------------------------------------

$(COSIM_SIM): $(COSIM_SRC) $(shell find $(PROJ_ROOT)/rtl/core -name '*.sv')
	@mkdir -p $(VL_BUILD)/$(COSIM_TB)
	$(VERILATOR) $(VL_FLAGS) --Mdir $(VL_BUILD)/$(COSIM_TB) -o $(COSIM_TB) \
	  --top-module $(COSIM_TB) -f $(PROJ_ROOT)/rtl/core/core.f $(COSIM_SRC)

# ---- Reference run ----------------------------------------------------------

cosim-spike: $(SPIKE_LOG)

# Spike exits with the program's own exit code, which crt0 takes from main: a nonzero one means a
# CHECK in the program failed on the reference itself, so the program is wrong, not the core.
$(SPIKE_LOG): $(SW_ELF) $(PROJ_ROOT)/scripts/sim/verilator/verilator.mk
	@[ -x "$(SPIKE)" ] || { echo "[cosim] $(SPIKE) not found, run ./setup.sh first" >&2; exit 1; }
	@echo "[cosim] Spike: $(TEST)"
	@$(SPIKE) --isa=$(SPIKE_ISA) --priv=$(SPIKE_PRIV) --log-commits --log=$@ $< || { \
	  code=$$?; \
	  echo "FAIL: check $$code of $(TEST) failed on Spike itself, so the program is wrong" >&2; \
	  exit $$code; }

# ---- DUT run and comparison -------------------------------------------------

cosim-rtl: $(COSIM_SIM) $(SW_HEX) $(SW_SYM) $(SW_DIS)
	@echo "[cosim] RTL: $(TEST)"
	$(COSIM_SIM) +HEX=$(SW_HEX) +TRACE=$(COSIM_TRACE) +TIMEOUT=$(COSIM_TIMEOUT) \
	  +GNT_WAIT=$(COSIM_GNT_WAIT) +RSP_WAIT=$(COSIM_RSP_WAIT) +WAIT_SEED=$(COSIM_WAIT_SEED) \
	  +TOHOST=$$(awk '$$3 == "tohost" { print $$1 }' $(SW_SYM)) | tee $(VL_BUILD)/$(COSIM_TB)/$(TEST).log
	@grep -q '^PASS' $(VL_BUILD)/$(COSIM_TB)/$(TEST).log

cosim: cosim-spike cosim-rtl
	@echo "[cosim] comparing traces"
	python3 $(PROJ_ROOT)/scripts/utils/cmp_trace.py $(SPIKE_LOG) $(COSIM_TRACE) --start $(RAM_BASE)

# Everything under sw/tests, reported as a table. The script drives `make cosim` per test, so
# the flow stays here and the selection, parallelism and reporting stay in the script.
cosim-all:
	python3 $(PROJ_ROOT)/scripts/sim/verilator/run_cosim.py

# Just build the testbench, so parallel per-test runs do not race on it.
cosim-build: $(COSIM_SIM)

# ---- Plain unit testbench ---------------------------------------------------

TB ?= tb_rv32_core
TB_SRC = $(firstword $(wildcard $(PROJ_ROOT)/verif/unit/*/$(TB).sv))

vsim-unit:
	@[ -n "$(TB_SRC)" ] || { echo "[vsim-unit] no verif/unit/*/$(TB).sv" >&2; exit 1; }
	@mkdir -p $(VL_BUILD)/$(TB)
	$(VERILATOR) $(VL_FLAGS) --Mdir $(VL_BUILD)/$(TB) -o $(TB) --top-module $(TB) \
	  -f $(PROJ_ROOT)/rtl/rtl.f $(TB_SRC)
	$(VL_BUILD)/$(TB)/$(TB)
