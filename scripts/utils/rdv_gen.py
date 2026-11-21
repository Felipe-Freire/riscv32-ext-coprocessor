#!/usr/bin/env python3
"""Generate one riscv-dv program: a test of verif/riscv-dv/testlist.yaml, with one seed.

    rdv_gen.py --test riscv_rand_instr_test --seed 7 --gen-dir build/riscv-dv/gen -o prog.S

Called by sw/sw.mk for SW=rdv-<test>-<seed>; run it with the Python of build/venv (./setup.sh),
which has PyYAML. The generator must already be compiled into --gen-dir (`run.py --co`, which
sw.mk does once); this script only runs it, with xrun -R, in the directory of the output file.

Not run.py --so: that names every program <test>_0.S in one shared directory, so parallel
regression runs would overwrite each other's programs. The command line is the one run.py builds
for the xlm simulator (vendor/riscv-dv/yaml/simulator.yaml), with the gen_opts of the test.
--opts come first, so they win: the generator reads the first match of each plusarg.
"""

import argparse
import os
import shlex
import subprocess
import sys

PROJ_ROOT = os.environ.get("PROJ_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))
RDV_ROOT = os.path.join(PROJ_ROOT, "vendor", "riscv-dv")
TESTLIST = os.path.join(PROJ_ROOT, "verif", "riscv-dv", "testlist.yaml")


def find_test(name):
    """The testlist entry of the test, with riscv-dv's own parser (it resolves the imports)."""
    sys.path.insert(0, RDV_ROOT)
    try:
        from scripts.lib import process_regression_list
    except ImportError as e:
        sys.exit(f"rdv_gen.py: cannot load riscv-dv ({e}); run ./setup.sh for the venv and the "
                 "vendor/riscv-dv submodule")
    matched = []
    process_regression_list(TESTLIST, name, 0, matched, RDV_ROOT)
    if not matched:
        sys.exit(f"rdv_gen.py: no test {name} in {os.path.relpath(TESTLIST, PROJ_ROOT)}")
    test = matched[0]
    if "gen_test" not in test:
        sys.exit(f"rdv_gen.py: {name} is not a generated test (no gen_test)")
    return test


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--test", required=True, help="test name in verif/riscv-dv/testlist.yaml")
    ap.add_argument("--seed", type=int, required=True, help="generator seed")
    ap.add_argument("--gen-dir", required=True, help="output directory of run.py --co")
    ap.add_argument("--opts", default="", help="extra generator plusargs, e.g. '+instr_cnt=2000'")
    ap.add_argument("-o", "--output", required=True, help="assembly file to write")
    args = ap.parse_args()

    test = find_test(args.test)
    gen_dir = os.path.abspath(args.gen_dir)
    if not os.path.isdir(os.path.join(gen_dir, "xcelium.d")):
        sys.exit(f"rdv_gen.py: no compiled generator in {gen_dir}")

    output = os.path.abspath(args.output)
    work = os.path.dirname(output)
    os.makedirs(work, exist_ok=True)
    stem = os.path.join(work, "gen")
    cmd = (["xrun", "-R", "-xmlibdirpath", gen_dir, "-svseed", str(args.seed),
            "-svrnc", "rand_struct", "-nokey", "-l", os.path.join(work, "gen.log"),
            f"+UVM_TESTNAME={test['gen_test']}", "+num_of_tests=1", "+start_idx=0",
            f"+asm_file_name={stem}", "+disable_compressed_instr=1"]
           + shlex.split(args.opts) + shlex.split(test.get("gen_opts", "")))

    proc = subprocess.run(cmd, cwd=work, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    with open(os.path.join(work, "gen.log"), errors="replace") as f:
        log = f.read()
    generated = f"{stem}_0.S"
    if proc.returncode != 0 or not os.path.isfile(generated) or "UVM_FATAL @" in log \
            or "UVM_ERROR @" in log:
        sys.exit(f"rdv_gen.py: the generator failed for {args.test} seed {args.seed}, "
                 f"see {os.path.join(work, 'gen.log')}")
    os.replace(generated, output)
    print(f"rdv_gen.py: {args.test} seed {args.seed} -> {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
