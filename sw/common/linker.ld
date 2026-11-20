/* Memory image for the core/Spike co-simulation testbench: one 64 KiB RAM at 0x8000_0000 that
 * holds code, data and the stack. Spike's default memory region starts at the same address, so
 * the same ELF runs on both without extra options.
 *
 * .htif holds the tohost/fromhost pair Spike's HTIF polls: writing (code << 1) | 1 to tohost ends
 * the run. The testbench watches a store to the same address, so both sides stop at the same
 * instruction. See sw/common/crt0.S.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  ram (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS {
  .text : {
    *(.text.init)
    *(.text .text.*)
  } > ram

  .rodata : {
    *(.rodata .rodata.*)
    *(.srodata*)
  } > ram

  /* 64-byte aligned, as the HTIF convention wants it. */
  .htif ALIGN(64) : {
    *(.htif)
  } > ram

  .data : {
    *(.data .data.*)
    *(.sdata*)
  } > ram

  /* Not in the image: crt0 zeroes it before main. */
  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss .bss.*)
    *(.sbss*)
    *(COMMON)
    __bss_end = .;
  } > ram

  _stack_top = ORIGIN(ram) + LENGTH(ram);

  /DISCARD/ : { *(.comment) *(.note*) *(.riscv.attributes) }
}
