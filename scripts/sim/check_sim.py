#!/usr/bin/env python3
"""Decide whether one simulation passed, from its log and the simulator exit status.

Usage: check_sim.py <log> <exit status> <name> [--uvm]

Called by `make sim`. Prints one line, "[sim] PASS <name> ..." or "[sim] FAIL <name>: <reason>",
and exits 0 or 1.

Testbenches report through the simulator (verif/README.md): a failed check is $error, a reason to
stop is $fatal, and the UVM tops turn UVM_ERROR and UVM_FATAL into $error at the end. Each of those
makes xrun exit with a nonzero status and writes a *E or *F message, as do compile errors and failed
assertions, so they fail the run; the reason is the first such message. Exit status 0 does not prove
that the test reached its end, so a run also needs its end marker: a line starting with PASS from a
directed testbench, the report summary from UVM.

Timing-check violations of a gate-level run with SDF are counted in the line, without failing it.
"""
import argparse
import os
import re
import sys

# "xmsim: *E,ERRSEV (tb.sv,41): (time 10 NS)."  or  "xrun: *E,ELBERR: Error (*E) or ..."
SIM_MESSAGE = re.compile(r"^\S+: \*([EF]),(\w+)\s*(?:\(([^,)]+),(\d+)[^)]*\))?:?\s*(.*)$")
# "UVM_ERROR /path/scoreboard.svh(120) @ 4500: uvm_test_top.env.sb [SB] C word mismatch"
# "UVM_FATAL @ 0: reporter [INVTST] Requested test ... not found."
UVM_REPORT = re.compile(r"^(UVM_ERROR|UVM_FATAL)(?: (\S+)\((\d+)\))? @ ([^:]+): (.*)$")


def sim_messages(log, severity):
    """The *E or *F messages of the log, each as 'file:line: text'."""
    lines = log.splitlines()
    messages = []
    for i, line in enumerate(lines):
        m = SIM_MESSAGE.match(line)
        if not m or m.group(1) != severity:
            continue
        code, path, number, text = m.group(2), m.group(3), m.group(4), m.group(5).strip()
        # $error and $fatal write their text two lines further down, after the scope.
        if code in ("ERRSEV", "FATSEV") and i + 2 < len(lines):
            text = lines[i + 2].strip()
        where = f"{os.path.basename(path)}:{number}: " if path else ""
        messages.append(f"{where}{text}")
    return messages


def uvm_failures(log):
    """The UVM_ERROR and UVM_FATAL counts of the report summary, and the first such report."""
    counts = {}
    for severity in ("UVM_ERROR", "UVM_FATAL"):
        m = re.search(rf"^{severity}\s*:\s*(\d+)", log, re.M)
        counts[severity] = int(m.group(1)) if m else 0
    first = None
    for line in log.splitlines():
        m = UVM_REPORT.match(line)
        if m:
            where = f"{os.path.basename(m.group(2))}:{m.group(3)} " if m.group(2) else ""
            first = f"{where}@ {m.group(4)}: {m.group(5)}"
            break
    return counts, first


def verdict(log, status, uvm):
    """Returns None when the run passed, otherwise the reason it failed."""
    if uvm:
        counts, first = uvm_failures(log)
        if counts["UVM_ERROR"] or counts["UVM_FATAL"]:
            summary = f"{counts['UVM_ERROR']} UVM_ERROR, {counts['UVM_FATAL']} UVM_FATAL"
            return f"{summary}; first: {first}" if first else summary

    errors = sim_messages(log, "E")
    if errors:
        count = f"{len(errors)} error{'s' if len(errors) > 1 else ''}"
        return f"{count} ($error, assertion or tool), first: {errors[0]}"
    fatals = sim_messages(log, "F")
    if fatals:
        return f"fatal: {fatals[0]}"
    if status != 0:
        return f"xrun exit status {status}"

    if uvm and "UVM Report Summary" not in log:
        return "no UVM report summary: the test did not reach its end"
    if not uvm and not re.search(r"^PASS\b", log, re.M):
        return "no PASS line: the testbench did not reach its end"
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("log")
    parser.add_argument("status", type=int)
    parser.add_argument("name")
    parser.add_argument("--uvm", action="store_true", help="UVM test: read the report summary")
    args = parser.parse_args()

    try:
        with open(args.log, errors="replace") as f:
            log = f.read()
    except OSError as e:
        print(f"[sim] FAIL {args.name}: cannot read {args.log} ({e.strerror})")
        return 1

    seed = re.search(r"SVSEED.*?(-?\d+)\s*$", log, re.M)
    notes = f" (seed {seed.group(1)})" if seed else ""
    violations = log.count("Timing violation")
    if violations:
        notes += f", {violations} timing violations in xrun.log"

    reason = verdict(log, args.status, args.uvm)
    if reason is None:
        print(f"[sim] PASS {args.name}{notes}")
        return 0
    print(f"[sim] FAIL {args.name}{notes}: {reason}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
