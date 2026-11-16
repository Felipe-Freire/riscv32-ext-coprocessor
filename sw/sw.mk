# Builds one bare-metal test program into $(BUILD_DIR)/sw: ELF, $readmemh image, disassembly and
# symbol table. Included by the top-level Makefile.
#
#   make sw TEST=sum
#
# TEST is a directory under sw/tests/ holding the program's .c and .S files; crt0.S and linker.ld
# from sw/common/ are always linked in.

RISCV_PREFIX ?= riscv64-unknown-elf-
RISCV_CC     := $(RISCV_PREFIX)gcc
RISCV_OBJDUMP:= $(RISCV_PREFIX)objdump
RISCV_NM     := $(RISCV_PREFIX)nm

TEST      ?= sum
SW_DIR    := $(PROJ_ROOT)/sw

# Where the test's sources live. Override it for a generated program, which belongs in build/:
#   make cosim TEST=random7 TEST_DIR=$(BUILD_DIR)/sw/random7
TEST_DIR  ?= $(SW_DIR)/tests/$(TEST)

# Optional per-test overrides: a test that needs another ISA, a longer timeout or extra flags puts
# them in <test dir>/test.mk. Included before the defaults below, so a plain assignment there wins
# over them, while a variable given on the command line still wins over both.
-include $(TEST_DIR)/test.mk

ARCH      ?= rv32i_zicsr
ABI       ?= ilp32
RAM_BASE  ?= 0x80000000
SW_BUILD  := $(BUILD_DIR)/sw
SW_LD     := $(SW_DIR)/common/linker.ld
# crt0 and any shared helper in common/, then the test's own sources.
SW_SRCS   := $(SW_DIR)/common/crt0.S \
             $(sort $(wildcard $(SW_DIR)/common/*.c)) \
             $(sort $(wildcard $(TEST_DIR)/*.S $(TEST_DIR)/*.c))

# Listed as prerequisites, so touching a header rebuilds the tests that include it.
SW_HDRS   := $(sort $(wildcard $(SW_DIR)/common/*.h $(TEST_DIR)/*.h))

SW_ELF    := $(SW_BUILD)/$(TEST).elf
SW_HEX    := $(SW_BUILD)/$(TEST).hex
SW_DIS    := $(SW_BUILD)/$(TEST).dis
SW_SYM    := $(SW_BUILD)/$(TEST).sym

# -lgcc provides __mulsi3 and the divide routines: the core has no M extension.
SW_CFLAGS := -march=$(ARCH) -mabi=$(ABI) -Os -g -std=c11 -ffreestanding -fno-builtin \
             -Wall -Wextra -I$(SW_DIR)/common
SW_LDFLAGS:= -nostdlib -nostartfiles -T $(SW_LD) -Wl,--no-warn-rwx-segments -Wl,-Map,$(SW_BUILD)/$(TEST).map

.PHONY: sw sw-clean

sw: $(SW_HEX) $(SW_DIS) $(SW_SYM)

$(SW_BUILD):
	@mkdir -p $@

# The makefile is a prerequisite too: the compiler flags live in it.
$(SW_ELF): $(SW_SRCS) $(SW_HDRS) $(SW_LD) $(SW_DIR)/sw.mk \
            $(wildcard $(TEST_DIR)/test.mk) | $(SW_BUILD)
	@[ -n "$(strip $(wildcard $(TEST_DIR)/*.S) $(wildcard $(TEST_DIR)/*.c))" ] \
	  || { echo "[sw] no .c or .S sources in $(TEST_DIR)" >&2; exit 1; }
	$(RISCV_CC) $(SW_CFLAGS) $(SW_LDFLAGS) -o $@ $(SW_SRCS) -lgcc

$(SW_HEX): $(SW_ELF)
	python3 $(PROJ_ROOT)/scripts/utils/elf2hex.py $< -o $@ --base $(RAM_BASE)

$(SW_DIS): $(SW_ELF)
	$(RISCV_OBJDUMP) -d -S $< > $@

$(SW_SYM): $(SW_ELF)
	$(RISCV_NM) -n $< > $@

sw-clean:
	rm -rf $(SW_BUILD)
