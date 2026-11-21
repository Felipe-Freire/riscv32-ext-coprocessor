# Top-level entry point. Run `make help` for the targets and their variables.

export PROJ_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

BUILD_DIR ?= $(PROJ_ROOT)/build

# Blocks: RTL file lists in compile order (vendor IP first) and the top module. Synthesis, STA and
# gate-level simulation pick one with BLOCK=<name>; simulation finds it from the testbench.
BLOCKS           := core coproc
RTL_FLIST_core   := $(PROJ_ROOT)/rtl/core/core.f
RTL_TOP_core     := rv32_core
RTL_FLIST_coproc := $(PROJ_ROOT)/vendor/common_cells.f $(PROJ_ROOT)/rtl/coproc/coproc.f
RTL_TOP_coproc   := coproc_top

.DEFAULT_GOAL := help
.PHONY: help clean

include $(PROJ_ROOT)/syn/tech/tech.mk
include $(PROJ_ROOT)/syn/syn.mk
include $(PROJ_ROOT)/syn/sta.mk
include $(PROJ_ROOT)/sw/sw.mk
include $(PROJ_ROOT)/scripts/sim/sim.mk

define HELP_TEXT
Usage: make <target> [VAR=value ...]

Synthesis and timing (Genus), see syn/README.md
  syn             Synthesize BLOCK (or TOP)                  -> build/syn/<top>/
  syn-list        List the blocks and the modules each one can synthesize
  sta             Static timing of the synthesized TOP at CORNER -> build/sta/<top>/<corner>/

Simulation (Xcelium, or Verilator with SIM=verilator), see scripts/README.md
  sim             Run a directed testbench (TB=), a UVM test (UVM= TEST=) or a program
                  against Spike (SW=)                        -> build/sim/<sim>/<run>/
  gls             Same as sim, on the synthesized netlist of TOP (run syn first)
  sim-list        List the testbenches, the UVM environments, their tests and the programs
  regress         Run every line of a regression list, then a PASS/FAIL table

Software, see sw/README.md
  sw              Build a program (SW=)                      -> build/sw/

  clean           Remove $(BUILD_DIR)

Design and technology (syn, sta, gls)
  BLOCK                 $(BLOCKS) (default: core)
  TOP                   Top module (default: the block's top, see syn-list)
  CLK_PERIOD            clk_i period in ns (default: 10)
  ACC_CLK_PERIOD        clk_acc_i period of coproc_top in ns (default: CLK_PERIOD)
  EFFORT                Synthesis effort: low, medium, high (default: medium)
  CLOCK_GATING          1 inserts clock-gating cells, 0 keeps enable muxes (default: 1)
  VT                    GPDK045 threshold flavour: svt, lvt, hvt (default: svt)
  CORNER                slow_vdd1v0, slow_vdd1v2, fast_vdd1v0, fast_vdd1v2 (default: slow_vdd1v0)
  RC_CORNER             Wire estimation rules: rcworst, typical, rcbest (default: rcworst)
  LIBS= LEFS=           Empty: Genus tutorial library, no physical data
  In use here: $(strip $(TECH_NAME))

Simulation
  SIM                   Simulator: xrun, verilator (default: xrun; verilator: directed only)
  TB                    Directed testbench verif/unit/<block>/<TB>.sv
  UVM, TEST             UVM environment verif/uvm/<UVM>/ and its test class
  SEED                  Random seed, or random (default: 1)
  VERBOSITY             UVM verbosity (default: UVM_MEDIUM)
  PLUSARGS              Extra plusargs, e.g. PLUSARGS="+JOBS=10 +BIG_K"
  WAVES=1               Record every signal to waves.shm (open with simvision)
  GUI=1                 Run inside SimVision
  COV=1                 Collect code and functional coverage
  XRUN_OPTS             Extra xrun options
  GLS=1                 Gate level, what gls does; with SDF=1, the delays of SDF_FILE
  SDF_FILE              SDF to annotate (default: the one make syn wrote for TOP)
  CELL_MODELS           Verilog models of the cells (default: found in the kit)
  LIST, JOBS            Regression lists and runs at a time (default: smoke.list, 1)

Software and co-simulation against Spike
  SW                    Program sw/tests/<SW>, random<seed> (gen_random_test.py) or
                        rdv-<test>-<seed> (riscv-dv, verif/riscv-dv/testlist.yaml); with sim,
                        runs on TB (default: tb_rv32_core_cosim) and on Spike, traces compared
  RANDOM_COUNT          Instructions of a random<seed> program (default: 2000)
  RDV_OPTS              Extra riscv-dv generator plusargs, e.g. RDV_OPTS=+instr_cnt=2000
  RISCV                 Spike install prefix, see setup.sh (default: build/riscv)
  RISCV_PREFIX          GCC prefix (default: riscv64-unknown-elf-)
  COSIM_TIMEOUT         Cycles before the testbench gives up (default: 1000000)
  COSIM_GNT_WAIT        Cycles a data request waits for its grant (default: 0)
  COSIM_RSP_WAIT        Cycles from grant to response (default: 0)
  COSIM_WAIT_SEED       Nonzero: random waits up to those maxima (default: 0)

Examples
  make syn BLOCK=coproc CLK_PERIOD=5 ACC_CLK_PERIOD=2.5
  make syn BLOCK=core TOP=rv32_alu
  make sta BLOCK=core CORNER=slow_vdd1v2
  make sim TB=tb_rv32_core
  make sim TB=tb_rv32_alu SIM=verilator
  make sim SW=sort COSIM_GNT_WAIT=3 COSIM_RSP_WAIT=3 COSIM_WAIT_SEED=1
  make sim SW=rdv-riscv_rand_instr_test-7
  make sim UVM=coproc TEST=coproc_matmul_rand_test SEED=random PLUSARGS=+JOBS=10
  make gls TB=tb_rv32_core SDF=1
  make regress LIST=verif/regress/smoke.list JOBS=4
  make regress LIST=verif/regress/cosim.list JOBS=8 SIM=verilator
  make regress LIST=verif/regress/riscv_dv.list JOBS=8
endef
export HELP_TEXT

help:
	@echo "$$HELP_TEXT"

clean:
	rm -rf $(BUILD_DIR)
