/* Linker script for the riscv-arch-test (ACT4) framework, matching the memory map of
 * tb_rv32_core_cosim: one 4 MiB RAM at 0x8000_0000, which is also where Spike puts its memory.
 *
 * Derived from the framework's own config/spike/spike-rv32-m/link.ld, with RAM_LENGTH cut to what
 * the testbench models. .text.rvmodel stays after .data, as the framework requires, so the DUT and
 * the reference model agree on the address of every piece of test data.
 */
RAM_ORIGIN = 0x80000000;
RAM_LENGTH = 0x00400000;
TEST_BASE  = RAM_ORIGIN;
NUM_HARTS  = 1;

STACK_SIZE = 0x20000;

OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

MEMORY
{
  ram (rwx) : ORIGIN = RAM_ORIGIN, LENGTH = RAM_LENGTH
}

PROVIDE(__stack_size = STACK_SIZE);
PROVIDE(__num_harts = NUM_HARTS);

SECTIONS
{
  ASSERT(TEST_BASE >= ORIGIN(ram) && TEST_BASE < ORIGIN(ram) + LENGTH(ram), "TEST_BASE is outside RAM")

  .text.init   TEST_BASE : { *(.text.init) } > ram
  .text.rvtest . : { *(.text.rvtest) *(.text.rvtest.*) } > ram

  . = ALIGN(0x4000);
  .rodata . : { *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*) } > ram
  .data   . : { *(.data) *(.data.*) *(.sdata) *(.sdata.*) } > ram

  . = ALIGN(16);
  .bss . : {
    __bss_start = .;
    *(.sbss) *(.sbss.*) *(.bss) *(.bss.*) *(COMMON)
    . = ALIGN(16);
    __bss_end = .;
  } > ram

  . = ALIGN(16);
  __stack_bottom = .;
  . += __stack_size * __num_harts;
  __stack_top = .;

  . = ALIGN(0x1000);
  .text.rvmodel . : { *(.text.rvmodel) *(.text.rvmodel.*) *(.text) *(.text.*) } > ram

  . = ALIGN(0x1000);
  _end = .;

  ASSERT(_end <= ORIGIN(ram) + LENGTH(ram), "the ELF does not fit in the 4 MiB the testbench models")
}
