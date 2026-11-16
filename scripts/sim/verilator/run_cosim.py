#!/usr/bin/env python3
"""Run every software test on Spike and on the RTL core and compare the traces.

    scripts/sim/verilator/run_cosim.py                 # all tests
    scripts/sim/verilator/run_cosim.py sort matmul     # just these
    scripts/sim/verilator/run_cosim.py 'l*' -j 4       # glob patterns, four at a time
    scripts/sim/verilator/run_cosim.py --random 20       # 20 generated random programs
    scripts/sim/verilator/run_cosim.py --list

Works from any directory. Each test goes through `make cosim TEST=<name>`, so the flow itself
stays defined in sw/sw.mk and scripts/sim/verilator/verilator.mk and this script only selects the
tests, runs them in parallel and reports. Output goes to build/ only: the full log of each run is
build/sw/<test>.cosim.log.

With --random, the tests are generated instead: scripts/utils/gen_random_test.py writes a random
straight-line RV32I program per seed into build/sw/<name>, and Spike is the only oracle it needs.
Hand-written tests stop finding things long before random ones do.

Exit code is 0 when every test passed, 1 otherwise.
"""

import argparse
import concurrent.futures
import fnmatch
import os
import re
import subprocess
import sys
import time

PROJ_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))

# PASS: program exited with code 0, 292 instructions retired in 467 cycles
TB_PASS_RE = re.compile(r"^PASS: program exited with code 0, (\d+) instructions retired in (\d+) cycles",
                        re.MULTILINE)
TB_FAIL_RE = re.compile(r"^FAIL: .*$", re.MULTILINE)
# MATCH: 292 instructions identical to Spike (Spike log holds 4995 from 0x80000000)
MATCH_RE = re.compile(r"^MATCH: (\d+) instructions identical to Spike", re.MULTILINE)
MISMATCH_RE = re.compile(r"^(MISMATCH.*(?:\n(?:  .*)?)*)", re.MULTILINE)

PASS, FAIL, MISMATCH, BUILD = "PASS", "FAIL", "MISMATCH", "BUILD"


class Result:
    def __init__(self, test):
        self.test = test
        self.status = BUILD
        self.retired = None
        self.cycles = None
        self.compared = None
        self.detail = ""
        self.seconds = 0.0
        self.log = os.path.join(PROJ_ROOT, "build", "sw", f"{test}.cosim.log")

    @property
    def ok(self):
        return self.status == PASS

    @property
    def ipc(self):
        if self.retired and self.cycles:
            return self.retired / self.cycles
        return None


def colour(enabled):
    if not enabled:
        return lambda _code, text: text
    codes = {"green": "32", "red": "31", "yellow": "33", "dim": "2", "bold": "1"}
    return lambda code, text: f"\033[{codes[code]}m{text}\033[0m"


def discover(sw_tests):
    """Test directories under sw/tests that hold at least one source file."""
    if not os.path.isdir(sw_tests):
        sys.exit(f"run_cosim.py: {sw_tests} does not exist")
    found = []
    for name in sorted(os.listdir(sw_tests)):
        path = os.path.join(sw_tests, name)
        if os.path.isdir(path) and any(f.endswith((".c", ".S")) for f in os.listdir(path)):
            found.append(name)
    return found


def select(available, patterns):
    if not patterns:
        return available
    chosen, unknown = [], []
    for pattern in patterns:
        hits = [t for t in available if fnmatch.fnmatch(t, pattern)]
        if not hits:
            unknown.append(pattern)
        for hit in hits:
            if hit not in chosen:
                chosen.append(hit)
    if unknown:
        sys.exit(f"run_cosim.py: no test matches {', '.join(unknown)}; "
                 f"available: {' '.join(available)}")
    return chosen


def make(args, extra_vars, capture=True):
    """Run make in PROJ_ROOT and return (returncode, output)."""
    cmd = ["make", "--no-print-directory"] + args + extra_vars
    proc = subprocess.run(cmd, cwd=PROJ_ROOT, text=True,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.STDOUT if capture else None)
    return proc.returncode, (proc.stdout or "")


def generate_random(count, instructions, base_seed):
    """Write one random program per seed and return [(name, extra make vars)]."""
    jobs = []
    for i in range(count):
        seed = base_seed + i
        name = f"random{seed}"
        out_dir = os.path.join(PROJ_ROOT, "build", "sw", name)
        os.makedirs(out_dir, exist_ok=True)
        source = os.path.join(out_dir, f"{name}.S")
        subprocess.run([sys.executable,
                        os.path.join(PROJ_ROOT, "scripts", "utils", "gen_random_test.py"),
                        "--seed", str(seed), "--count", str(instructions), "-o", source],
                       check=True, cwd=PROJ_ROOT, stdout=subprocess.DEVNULL)
        jobs.append((name, [f"TEST_DIR={out_dir}"]))
    return jobs


def run_one(test, extra_vars):
    result = Result(test)
    started = time.monotonic()
    code, output = make(["cosim", f"TEST={test}"], extra_vars)
    result.seconds = time.monotonic() - started

    os.makedirs(os.path.dirname(result.log), exist_ok=True)
    with open(result.log, "w") as fd:
        fd.write(output)

    tb_pass = TB_PASS_RE.search(output)
    if tb_pass:
        result.retired, result.cycles = int(tb_pass.group(1)), int(tb_pass.group(2))

    match = MATCH_RE.search(output)
    if match:
        result.compared = int(match.group(1))

    mismatch = MISMATCH_RE.search(output)
    tb_fail = TB_FAIL_RE.search(output)

    if code == 0 and match and tb_pass:
        result.status = PASS
    elif mismatch:
        result.status = MISMATCH
        result.detail = mismatch.group(1).rstrip()
    elif tb_fail:
        result.status = FAIL
        result.detail = tb_fail.group(0).strip()
    else:
        result.status = BUILD
        lines = [ln for ln in output.splitlines() if ln.strip()]
        errors = [ln for ln in lines if re.search(r"error|Error|undefined reference", ln)]
        result.detail = "\n".join((errors or lines)[-6:]) if lines \
            else f"make exited with {code}"
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tests", nargs="*", metavar="TEST",
                    help="test names or glob patterns (default: all)")
    ap.add_argument("-j", "--jobs", type=int, default=min(8, os.cpu_count() or 1),
                    help="tests to run at the same time (default: %(default)s)")
    ap.add_argument("-l", "--list", action="store_true", help="list the tests and exit")
    ap.add_argument("-x", "--fail-fast", action="store_true", help="stop after the first failure")
    ap.add_argument("--timeout", type=int, metavar="CYCLES",
                    help="simulation timeout per test, in cycles")
    ap.add_argument("-w", "--wait", action="store_true",
                    help="memory wait states: pseudo-random, up to 3 cycles for the grant and 3 "
                         "for the response (shorthand for --gnt-wait 3 --rsp-wait 3 --wait-seed 1)")
    ap.add_argument("--gnt-wait", type=int, metavar="N",
                    help="cycles a data request waits for its grant")
    ap.add_argument("--rsp-wait", type=int, metavar="N",
                    help="cycles between the grant and the response")
    ap.add_argument("--wait-seed", type=int, metavar="N",
                    help="nonzero: random waits up to those maxima, from this seed")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="show the failure detail of every failing test in full")
    ap.add_argument("--random", type=int, metavar="N",
                    help="generate and run N random programs instead of the tests in sw/tests")
    ap.add_argument("--random-count", type=int, default=2000, metavar="N",
                    help="instructions per random program (default %(default)s)")
    ap.add_argument("--random-seed", type=int, default=1, metavar="N",
                    help="first seed for --random (default %(default)s)")
    ap.add_argument("-D", dest="make_vars", action="append", default=[], metavar="VAR=VALUE",
                    help="extra make variable, repeatable (e.g. -D ARCH=rv32i)")
    args = ap.parse_args()

    tint = colour(sys.stdout.isatty() and not os.environ.get("NO_COLOR"))
    available = discover(os.path.join(PROJ_ROOT, "sw", "tests"))

    if args.list:
        for test in available:
            print(test)
        return 0

    if args.random:
        if args.tests:
            sys.exit("run_cosim.py: --random generates the tests, so name none")
        print(tint("dim", f"[cosim] generating {args.random} random program(s), "
                          f"{args.random_count} instructions each, "
                          f"from seed {args.random_seed}"))
        jobs = generate_random(args.random, args.random_count, args.random_seed)
    else:
        jobs = [(name, []) for name in select(available, args.tests)]
    tests = [name for name, _ in jobs]
    per_test_vars = dict(jobs)
    if not tests:
        sys.exit("run_cosim.py: no tests found under sw/tests")

    extra_vars = list(args.make_vars)
    if args.timeout:
        extra_vars.append(f"COSIM_TIMEOUT={args.timeout}")

    gnt, rsp, seed = args.gnt_wait, args.rsp_wait, args.wait_seed
    if args.wait:
        gnt = 3 if gnt is None else gnt
        rsp = 3 if rsp is None else rsp
        seed = 1 if seed is None else seed
    waits = ""
    if gnt or rsp or seed:
        extra_vars += [f"COSIM_GNT_WAIT={gnt or 0}", f"COSIM_RSP_WAIT={rsp or 0}",
                       f"COSIM_WAIT_SEED={seed or 0}"]
        waits = (f", memory waits: grant {gnt or 0}, response {rsp or 0}"
                 + (f", random seed {seed}" if seed else " (fixed)"))

    # Build the simulator once: the per-test runs would otherwise race on it.
    print(tint("dim", "[cosim] building the testbench"))
    code, output = make(["cosim-build"], extra_vars)
    if code != 0:
        print(output.rstrip())
        print(tint("red", "[cosim] the testbench did not build"))
        return 1

    print(tint("bold", f"[cosim] {len(tests)} test(s), {args.jobs} at a time{waits}"))
    header = f"  {'test':<12} {'status':<9} {'retired':>9} {'cycles':>9} {'IPC':>5} {'time':>7}"
    print(tint("dim", header))

    results, failed = [], False
    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = {pool.submit(run_one, test, extra_vars + per_test_vars[test]): test
                   for test in tests}
        try:
            for future in concurrent.futures.as_completed(futures):
                result = future.result()
                results.append(result)
                mark = tint("green", f"{result.status:<9}") if result.ok \
                    else tint("red", f"{result.status:<9}")
                print(f"  {result.test:<12} {mark} "
                      f"{result.retired if result.retired is not None else '-':>9} "
                      f"{result.cycles if result.cycles is not None else '-':>9} "
                      f"{f'{result.ipc:.2f}' if result.ipc else '-':>5} "
                      f"{result.seconds:>6.1f}s")
                if not result.ok:
                    failed = True
                    if args.fail_fast:
                        for pending in futures:
                            pending.cancel()
                        break
        except KeyboardInterrupt:
            for pending in futures:
                pending.cancel()
            print(tint("yellow", "\n[cosim] interrupted"))
            return 130

    results.sort(key=lambda r: r.test)
    elapsed = time.monotonic() - started
    passed = [r for r in results if r.ok]
    compared = sum(r.compared or 0 for r in results)
    retired = sum(r.retired or 0 for r in results)

    print()
    print(f"[cosim] {len(passed)}/{len(results)} passed, "
          f"{compared} instructions compared against Spike, "
          f"{retired} retired, {elapsed:.1f}s")

    if failed:
        print()
        for result in [r for r in results if not r.ok]:
            print(tint("red", f"  {result.test}: {result.status}"))
            detail = result.detail if (args.verbose or result.status != MISMATCH) \
                else "\n".join(result.detail.splitlines()[:11])
            for line in detail.splitlines():
                print(f"    {line}")
            print(tint("dim", f"    full log: {os.path.relpath(result.log, PROJ_ROOT)}"))
        return 1

    print(tint("green", "[cosim] the core matches Spike on every test"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
