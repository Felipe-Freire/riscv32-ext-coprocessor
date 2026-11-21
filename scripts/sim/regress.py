#!/usr/bin/env python3
"""Run a regression: every line of the lists through `make sim`, then a PASS/FAIL table.

Usage: regress.py [--jobs N] [--out DIR] <list> [<list> ...]

Called by `make regress LIST=<list> JOBS=<n>`. A list has one run per line, written as the
arguments of `make sim`; '#' starts a comment:

    TB=tb_rv32_core
    SW=sort COSIM_GNT_WAIT=3 COSIM_RSP_WAIT=3 COSIM_WAIT_SEED=1
    UVM=coproc TEST=coproc_matmul_rand_test SEED=random PLUSARGS=+JOBS=20

SEED=random is replaced by a seed drawn here, so each run has its own directory and the table
shows the seed that reproduces it. Variables given to `make regress` (GLS=1, COV=1, ...) reach
every run. The output of each run is in <out>/<lists>/<n>_<name>.log, a directory emptied at
the start. Exits 1 when any run failed.
"""
import argparse
import glob
import os
import random
import re
import shlex
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

PROJ_ROOT = os.environ.get("PROJ_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))


def read_lists(paths):
    """Returns the runs of all lists, each a list of make arguments."""
    runs = []
    for path in paths:
        with open(path) as f:
            for line in f:
                args = shlex.split(line.split("#", 1)[0])
                if args:
                    runs.append([a if a != "SEED=random" else f"SEED={random.randrange(1, 2**31)}"
                                 for a in args])
    return runs


def run_name(args):
    """A short label for the table: TB, SW, or TEST plus SEED, plus the other arguments."""
    values = dict(a.split("=", 1) for a in args if "=" in a)
    if "SW" in values:
        name = " ".join(filter(None, (values.get("TB"), f"SW={values['SW']}")))
    else:
        name = values.get("TB") or f"{values.get('TEST', '?')} seed {values.get('SEED', '1')}"
    extra = [a for a in args if a.split("=", 1)[0] not in ("TB", "SW", "UVM", "TEST", "SEED")]
    return " ".join([name] + extra)


def run(index, args, out_dir):
    log_path = os.path.join(out_dir, f"{index:03d}_{re.sub(r'[^A-Za-z0-9]+', '_', run_name(args))}.log")
    start = time.time()
    with open(log_path, "w") as log:
        proc = subprocess.run(["make", "-C", PROJ_ROOT, "--no-print-directory", "sim"] + args,
                              stdout=log, stderr=subprocess.STDOUT)
    with open(log_path, errors="replace") as log:
        result = [l.strip() for l in log if l.startswith("[sim] ")]
    if proc.returncode == 0:
        violations = re.search(r"\d+ timing violations", result[-1]) if result else None
        status, reason = "PASS", violations.group(0) if violations else ""
    else:
        status = "FAIL"
        reason = result[-1].split(": ", 1)[-1] if result else f"make exit status {proc.returncode}"
    return status, run_name(args), time.time() - start, reason, log_path


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("lists", nargs="+", help="regression list files")
    parser.add_argument("--jobs", type=int, default=1, help="simulations at the same time")
    parser.add_argument("--out", default=os.path.join(PROJ_ROOT, "build", "regress"),
                        help="directory of the run logs")
    args = parser.parse_args()

    runs = read_lists(args.lists)
    if not runs:
        print("[regress] The lists have no runs", file=sys.stderr)
        return 1
    out_dir = os.path.join(args.out, "+".join(
        os.path.splitext(os.path.basename(l))[0] for l in args.lists))
    os.makedirs(out_dir, exist_ok=True)
    for old_log in glob.glob(os.path.join(out_dir, "*.log")):
        os.remove(old_log)
    print(f"[regress] {len(runs)} runs from {' '.join(args.lists)}, {args.jobs} at a time")

    results = []
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = [pool.submit(run, i + 1, r, out_dir) for i, r in enumerate(runs)]
        for future in futures:
            results.append(future.result())
            status, name, seconds, reason, _ = results[-1]
            print(f"[regress] {status} {name} ({seconds:.0f} s){': ' + reason if reason else ''}",
                  flush=True)

    width = max(len(r[1]) for r in results)
    print(f"\n{'Status':<6}  {'Run':<{width}}  {'Time':>6}  Log / reason")
    for status, name, seconds, reason, log_path in results:
        detail = os.path.relpath(log_path, PROJ_ROOT) + (f"  {reason}" if reason else "")
        print(f"{status:<6}  {name:<{width}}  {seconds:5.0f}s  {detail}")
    failed = sum(r[0] != "PASS" for r in results)
    print(f"\n[regress] {len(results) - failed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
