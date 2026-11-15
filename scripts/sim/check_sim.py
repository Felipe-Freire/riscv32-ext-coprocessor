#!/usr/bin/env python3
"""Decide whether one simulation passed, from its log and the simulator exit status.

Usage: check_sim.py <log> <exit status> <name> [--uvm]

Called by `make sim`. Prints one line, "[sim] PASS <name> ..." or "[sim] FAIL <name>: <reason>",
and exits 0 or 1. A directed testbench passes when it printed PASS and no FAIL; a UVM test when
its report summary shows no UVM_ERROR or UVM_FATAL. Both fail on a simulator error (*E, *F) or a
nonzero exit status. Timing-check violations of a gate-level run with SDF are counted in the line:
they usually come from stimulus that changes on the clock edge, so they do not fail the run.
"""
import argparse
import re
import sys


def verdict(log, status, uvm):
    """Returns None when the run passed, otherwise the reason it failed."""
    if re.search(r"^\S*: \*F,", log, re.M):
        return "simulator fatal error (*F), see xrun.log"
    if re.search(r"^\S*: \*E,", log, re.M):
        return "simulator error (*E), see xrun.log"
    if status != 0:
        return f"xrun exit status {status}"
    if uvm:
        if "UVM Report Summary" not in log:
            return "no UVM report summary (the test did not finish)"
        for severity in ("UVM_FATAL", "UVM_ERROR"):
            count = re.search(rf"^{severity}\s*:\s*(\d+)", log, re.M)
            if count and int(count.group(1)) > 0:
                return f"{count.group(1)} {severity}"
        return None
    if re.search(r"\bFAIL\b", log):
        return "the testbench printed FAIL"
    if not re.search(r"\bPASS\b", log):
        return "the testbench never printed PASS"
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
    seed = f" (seed {seed.group(1)})" if seed else ""
    reason = verdict(log, args.status, args.uvm)
    violations = log.count("Timing violation")
    if violations:
        seed += f", {violations} timing violations in xrun.log"
    if reason is None:
        print(f"[sim] PASS {args.name}{seed}")
        return 0
    print(f"[sim] FAIL {args.name}{seed}: {reason}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
