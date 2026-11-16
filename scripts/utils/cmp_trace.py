#!/usr/bin/env python3
"""Compare the core's retirement trace against a Spike commit log, instruction by instruction.

    cmp_trace.py build/sw/sum.spike.log build/verilator/sum.trace --start 0x80000000

The DUT trace has one line per retired instruction, `<pc> <instr> <rd> <rd_value>` in hex, with
rd = 0 for no register write (see verif/unit/core/tb_rv32_core_cosim.sv). The Spike log is what
`spike --log-commits` writes:

    core   0: 3 0x80000008 (0x00b50633) x12 0x0000002a

Spike boots through its own reset vector at 0x1000 before jumping to the ELF entry, so --start
drops everything before the first time it reaches that address. Comparison runs over the DUT
trace: the first difference in PC, instruction word or register write is reported with context,
and the run fails. CSR state and store data are not compared here, that is what the full RVFI
co-simulation in verif/models/riscv does.

Volatile CSRs are the exception to comparing the destination value. A read of a cycle or
instruction counter must differ, because the reference has no pipeline, and this core reads mtval
as zero, which the privileged spec allows. For those, the PC, the instruction word and the
destination register are still compared, only the value is not. --volatile-csr adds more.
"""

import argparse
import re
import sys

# core   0: 3 0x80000008 (0x00b50633) x12 0x0000002a mem 0x80000050 0x0000002a
COMMIT_RE = re.compile(
    r"^core\s+\d+:\s+\d+\s+0x([0-9a-f]+)\s+\(0x([0-9a-f]+)\)(?P<rest>.*)$", re.IGNORECASE)
XREG_RE = re.compile(r"\bx(\d+)\s+0x([0-9a-f]+)", re.IGNORECASE)
TRAP_RE = re.compile(r"\b(exception|interrupt|trap_)\w*", re.IGNORECASE)


# Counters, which must differ between a pipeline and the reference, and mtval, which this core
# reads as zero (legal: the privileged spec allows a read-only-zero mtval).
def default_volatile_csrs():
    csrs = {0x343}                                      # mtval
    for base in (0xB00, 0xB80, 0xC00, 0xC80):           # m/u counters and their high halves
        csrs.update(range(base, base + 0x20))
    return csrs


def csr_number(instr):
    """The CSR a SYSTEM instruction addresses, or None if it is not a CSR access."""
    if (instr & 0x7F) != 0x73:                          # SYSTEM
        return None
    if ((instr >> 12) & 0x7) == 0:                      # ECALL, EBREAK, MRET, WFI
        return None
    return (instr >> 20) & 0xFFF


class Record:
    __slots__ = ("pc", "instr", "rd", "value", "source", "volatile")

    def __init__(self, pc, instr, rd, value, source):
        self.pc, self.instr, self.rd, self.value, self.source = pc, instr, rd, value, source
        self.volatile = False

    def __str__(self):
        write = f"x{self.rd} = 0x{self.value:08x}" if self.rd else "no register write"
        if self.volatile:
            write += "  (volatile CSR: value not compared)"
        return f"pc 0x{self.pc:08x}  instr 0x{self.instr:08x}  {write}"

    def same_as(self, other):
        if self.pc != other.pc or self.instr != other.instr or self.rd != other.rd:
            return False
        if self.rd == 0 or self.volatile or other.volatile:
            return True
        return self.value == other.value


def mark_volatile(records, csrs):
    """Flag the records whose destination value must not be compared."""
    count = 0
    for record in records:
        csr = csr_number(record.instr)
        if csr is not None and csr in csrs and record.rd != 0:
            record.volatile = True
            count += 1
    return count


def read_spike(path, start):
    records, traps, started = [], 0, start is None
    with open(path) as fd:
        for line in fd:
            if TRAP_RE.search(line) and not line.lstrip().startswith("core"):
                traps += 1
            match = COMMIT_RE.match(line.strip())
            if not match:
                continue
            pc = int(match.group(1), 16) & 0xffffffff
            if not started:
                if pc != start:
                    continue
                started = True
            write = XREG_RE.search(match.group("rest"))
            rd, value = (int(write.group(1)), int(write.group(2), 16)) if write else (0, 0)
            records.append(Record(pc, int(match.group(2), 16), rd if rd else 0,
                                  value if rd else 0, "spike"))
    if start is not None and not started:
        sys.exit(f"cmp_trace.py: Spike never reached the start address {start:#x}")
    return records, traps


def read_dut(path):
    records = []
    with open(path) as fd:
        for lineno, line in enumerate(fd, 1):
            line = line.split("//")[0].strip()
            if not line:
                continue
            fields = line.split()
            if len(fields) != 4:
                sys.exit(f"cmp_trace.py: {path}:{lineno}: expected 4 fields, got {len(fields)}")
            pc, instr, rd, value = fields
            records.append(Record(int(pc, 16), int(instr, 16), int(rd, 10), int(value, 16), "dut"))
    return records


def show(records, index, label, context):
    lo = max(0, index - context)
    for i in range(lo, min(len(records), index + 1)):
        mark = ">>" if i == index else "  "
        print(f"  {mark} {label}[{i}] {records[i]}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spike_log", help="Spike log from --log-commits")
    ap.add_argument("dut_trace", help="retirement trace from the testbench")
    ap.add_argument("--start", default="0x80000000",
                    help="skip the Spike log until this PC (default 0x80000000, 'none' to keep all)")
    ap.add_argument("--context", type=int, default=4, help="records of context on a mismatch")
    ap.add_argument("--volatile-csr", action="append", default=[], metavar="ADDR",
                    help="CSR whose read value is not compared, on top of the counters and mtval; "
                         "repeatable, e.g. --volatile-csr 0x340")
    args = ap.parse_args()

    start = None if args.start.lower() == "none" else int(args.start, 0)
    spike, traps = read_spike(args.spike_log, start)
    dut = read_dut(args.dut_trace)

    csrs = default_volatile_csrs()
    csrs.update(int(addr, 0) for addr in args.volatile_csr)
    volatile = mark_volatile(dut, csrs)
    mark_volatile(spike, csrs)

    if not dut:
        print("MISMATCH: the core retired no instruction")
        return 1
    if not spike:
        print("MISMATCH: the Spike log has no commit record")
        return 1

    for i, got in enumerate(dut):
        if i >= len(spike):
            print(f"MISMATCH at instruction {i}: the core retired more instructions than Spike "
                  f"({len(dut)} vs {len(spike)})")
            show(dut, i, "dut", args.context)
            return 1
        if not got.same_as(spike[i]):
            print(f"MISMATCH at instruction {i}:")
            show(spike, i, "spike", args.context)
            show(dut, i, "dut  ", args.context)
            return 1

    print(f"MATCH: {len(dut)} instructions identical to Spike "
          f"(Spike log holds {len(spike)} from {args.start})")
    if volatile:
        print(f"note: {volatile} volatile CSR read(s) compared without their value")
    if traps:
        print(f"note: Spike reported {traps} trap(s); traps are not compared")
    return 0


if __name__ == "__main__":
    sys.exit(main())
