# Builds one bare-metal test program into $(BUILD_DIR)/sw: ELF, $readmemh image, disassembly and
# symbol table. Included by the top-level Makefile.
#
#   make sw SW=sum
#   make sim SW=sum              build it, run it on Spike and on the RTL core, compare (sim.mk)
#
# SW is a directory under sw/tests/ holding the program's .c and .S files; crt0.S and linker.ld
# from sw/common/ are always linked in. SW=random<seed> and SW=rdv-<test>-<seed> are generated
# instead, see below. The variable is SW and not TEST because TEST names the UVM test of `make sim`.

# From the PATH, or else where ./setup.sh puts it.
RISCV_PREFIX ?= $(if $(shell command -v riscv64-unknown-elf-gcc 2>/dev/null),,$(BUILD_DIR)/riscv/bin/)riscv64-unknown-elf-
RISCV_CC     := $(RISCV_PREFIX)gcc
RISCV_OBJDUMP:= $(RISCV_PREFIX)objdump
RISCV_NM     := $(RISCV_PREFIX)nm

SW        ?=
SW_DIR    := $(PROJ_ROOT)/sw
SW_BUILD  := $(BUILD_DIR)/sw

# Random programs: SW=random<seed> is a straight-line RV32I program of RANDOM_COUNT instructions,
# written by scripts/utils/gen_random_test.py into build/sw/random<seed>/. Spike is its oracle.
RANDOM_COUNT ?= 2000
SW_RANDOM := $(if $(filter random%,$(SW)),$(if $(wildcard $(SW_DIR)/tests/$(SW)),,1))

# riscv-dv programs: SW=rdv-<test>-<seed> is test <test> of verif/riscv-dv/testlist.yaml, generated
# with seed <seed> by riscv-dv (vendor/riscv-dv) on Xcelium into build/sw/<SW>/. It brings its own
# startup code, trap handler and HTIF exit, so it is linked with riscv-dv's link.ld instead of crt0.
# RDV_OPTS adds generator plusargs, e.g. RDV_OPTS=+instr_cnt=2000. The generator is compiled once
# into build/riscv-dv/gen, again when the core setting changes.
RDV_ROOT     := $(PROJ_ROOT)/vendor/riscv-dv
RDV_GEN_DIR  := $(BUILD_DIR)/riscv-dv/gen
RDV_STAMP    := $(RDV_GEN_DIR)/.compiled
RDV_PYTHON   ?= $(BUILD_DIR)/venv/bin/python3
RDV_OPTS     ?=
SW_RDV    := $(if $(filter rdv-%,$(SW)),1)
RDV_TEST   = $(word 2,$(subst -, ,$(SW)))
RDV_SEED   = $(word 3,$(subst -, ,$(SW)))

# Where the program's sources live. Override it for a program kept somewhere else.
ifneq ($(SW_RANDOM)$(SW_RDV),)
SW_SRC    ?= $(SW_BUILD)/$(SW)
else
SW_SRC    ?= $(SW_DIR)/tests/$(SW)
endif

# Optional per-test overrides: a test that needs another ISA, a longer timeout or extra flags puts
# them in <test dir>/test.mk. Included before the defaults below, so a plain assignment there wins
# over them, while a variable given on the command line still wins over both.
-include $(SW_SRC)/test.mk

ARCH      ?= rv32i_zicsr
ABI       ?= ilp32
RAM_BASE  ?= 0x80000000
SW_LD     := $(SW_DIR)/common/linker.ld
# crt0 and any shared helper in common/, then the test's own sources.
SW_SRCS   := $(SW_DIR)/common/crt0.S \
             $(sort $(wildcard $(SW_DIR)/common/*.c)) \
             $(sort $(wildcard $(SW_SRC)/*.S $(SW_SRC)/*.c) $(if $(SW_RANDOM),$(SW_SRC)/$(SW).S))

ifeq ($(SW_RDV),1)
SW_LD     := $(RDV_ROOT)/scripts/link.ld
SW_SRCS   := $(SW_SRC)/$(SW).S
endif

# Listed as prerequisites, so touching a header rebuilds the tests that include it.
SW_HDRS   := $(sort $(wildcard $(SW_DIR)/common/*.h $(SW_SRC)/*.h))

SW_ELF    := $(SW_BUILD)/$(SW).elf
SW_HEX    := $(SW_BUILD)/$(SW).hex
SW_DIS    := $(SW_BUILD)/$(SW).dis
SW_SYM    := $(SW_BUILD)/$(SW).sym

# -lgcc provides __mulsi3 and the divide routines: the core has no M extension.
SW_CFLAGS := -march=$(ARCH) -mabi=$(ABI) -Os -g -std=c11 -ffreestanding -fno-builtin \
             -Wall -Wextra -I$(SW_DIR)/common $(if $(SW_RDV),-mcmodel=medany -I$(RDV_ROOT)/user_extension)
SW_LDFLAGS:= -nostdlib -nostartfiles -T $(SW_LD) -Wl,--no-warn-rwx-segments -Wl,-Map,$(SW_BUILD)/$(SW).map

.PHONY: sw sw-build sw-clean rdv-compile

sw:
	@test -n "$(SW)" || { echo "[sw] Choose SW=<program under sw/tests> or SW=random<seed>" >&2; exit 1; }
	@$(MAKE) --no-print-directory sw-build

sw-build: $(SW_HEX) $(SW_DIS) $(SW_SYM)

$(SW_BUILD):
	@mkdir -p $@

# The makefile is a prerequisite too: the compiler flags live in it.
$(SW_ELF): $(SW_SRCS) $(SW_HDRS) $(SW_LD) $(SW_DIR)/sw.mk \
            $(wildcard $(SW_SRC)/test.mk) | $(SW_BUILD)
	@[ -n "$(strip $(filter $(SW_SRC)/%.S $(SW_SRC)/%.c,$^))" ] \
	  || { echo "[sw] no .c or .S sources in $(SW_SRC)" >&2; exit 1; }
	$(RISCV_CC) $(SW_CFLAGS) $(SW_LDFLAGS) -o $@ $(SW_SRCS) -lgcc

$(SW_HEX): $(SW_ELF)
	python3 $(PROJ_ROOT)/scripts/utils/elf2hex.py $< -o $@ --base $(RAM_BASE)

$(SW_DIS): $(SW_ELF)
	$(RISCV_OBJDUMP) -d -S $< > $@

$(SW_SYM): $(SW_ELF)
	$(RISCV_NM) -n $< > $@

ifeq ($(SW_RANDOM),1)
$(SW_SRC)/$(SW).S: $(PROJ_ROOT)/scripts/utils/gen_random_test.py
	@mkdir -p $(dir $@)
	python3 $< --seed $(patsubst random%,%,$(SW)) --count $(RANDOM_COUNT) -o $@
endif

ifeq ($(SW_RDV),1)
# The generator's plusargs are part of the program, so a change of RDV_OPTS regenerates it.
$(SW_SRC)/.opts: FORCE
	@mkdir -p $(dir $@)
	@echo '$(RDV_OPTS)' | cmp -s - $@ || echo '$(RDV_OPTS)' > $@

$(SW_SRC)/$(SW).S: $(RDV_STAMP) $(SW_SRC)/.opts $(PROJ_ROOT)/verif/riscv-dv/testlist.yaml \
                   $(PROJ_ROOT)/scripts/utils/rdv_gen.py
	@[ -n "$(RDV_TEST)" ] && [ -n "$(RDV_SEED)" ] || \
	  { echo "[sw] SW=rdv-<test>-<seed>, e.g. SW=rdv-riscv_rand_instr_test-1" >&2; exit 1; }
	$(RDV_PYTHON) $(PROJ_ROOT)/scripts/utils/rdv_gen.py --test $(RDV_TEST) --seed $(RDV_SEED) \
	  --gen-dir $(RDV_GEN_DIR) --opts '$(RDV_OPTS)' -o $@
endif

# Parallel builds of riscv-dv programs would all compile the generator: the first one does it,
# under the lock, and the others find it done.
$(RDV_STAMP): $(PROJ_ROOT)/verif/riscv-dv/riscv_core_setting.sv
	@[ -x "$(RDV_PYTHON)" ] || { echo "[sw] No $(RDV_PYTHON): run ./setup.sh" >&2; exit 1; }
	@[ -f "$(RDV_ROOT)/run.py" ] || { echo "[sw] No vendor/riscv-dv: run ./setup.sh" >&2; exit 1; }
	@mkdir -p $(dir $@)
	@flock $(RDV_GEN_DIR).lock $(MAKE) --no-print-directory rdv-compile

rdv-compile:
	@if [ ! -f $(RDV_STAMP) ] || [ $(PROJ_ROOT)/verif/riscv-dv/riscv_core_setting.sv -nt $(RDV_STAMP) ]; then \
	  echo "[sw] Compiling the riscv-dv generator into $(RDV_GEN_DIR)"; \
	  cd $(RDV_ROOT) && $(RDV_PYTHON) run.py --co --simulator xlm --custom_target $(PROJ_ROOT)/verif/riscv-dv \
	    --isa $(ARCH) --mabi $(ABI) -o $(RDV_GEN_DIR) > $(RDV_GEN_DIR).log 2>&1 \
	  && ! grep -q '^xm[a-z]*: \*[EF],' $(RDV_GEN_DIR)/compile.log \
	  || { echo "[sw] riscv-dv generator did not compile, see $(RDV_GEN_DIR)/compile.log" >&2; exit 1; }; \
	  touch $(RDV_STAMP); \
	fi

.PHONY: FORCE
FORCE:

sw-clean:
	rm -rf $(SW_BUILD)
