# Software

RISC-V programs that run on the core during simulation: ISA tests, coprocessor tests and matrix
multiplication kernels. Programs are compiled to memory images (`.hex`) that the testbench
loads with `$readmemh`.

## Contents

| Directory | Contents |
|---|---|
| [`common/`](common/) | Startup code (`crt0.S`), linker script (`linker.ld`), helper headers, coprocessor intrinsics |
| [`tests/`](tests/) | Assembly and C test programs, one subdirectory or file per test |

## Toolchain

Use the RISC-V GNU toolchain (`riscv64-unknown-elf-gcc` handles RV32 with the flags below). Set
`-march` to the extensions the core actually implements:

```bash
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -T common/linker.ld ...
```

Custom coprocessor instructions can be emitted before the compiler knows about them, using the
assembler's `.insn` directive on the `custom-0`/`custom-1` opcodes. Wrap them in inline functions in
`common/` so tests never hard-code encodings. The encodings are defined in
[`docs/spec/`](../docs/README.md#specifications).

## Conventions

- Build products (`.o`, `.elf`, `.hex`, disassembly) go to `build/sw/`, never into this directory.
- Each test reports pass/fail the same way (e.g. writing to a fixed "tohost" address) so the
  testbench can check every program with the same logic.

---
[← Back to project root](../README.md)
