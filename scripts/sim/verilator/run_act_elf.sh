#!/usr/bin/env bash
# Run one ELF on the RTL core and report pass or fail. Used as the DUT run command of the
# riscv-arch-test framework (verif/arch-test/run_cmd.txt), and usable on its own:
#
#   scripts/sim/verilator/run_act_elf.sh --elf build/sw/sum.elf [--trace FILE] [--timeout N]
#
# The ELF is converted to a $readmemh image and run on tb_rv32_core_cosim, which stops when the
# program writes the HTIF tohost word. Exit status 0 means the program reported success.
# Prints RVCP-SUMMARY lines, which is what the framework's log parser looks for.

set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${PROJ_ROOT}/build}"
RAM_BASE="${RAM_BASE:-0x80000000}"
TIMEOUT="${COSIM_TIMEOUT:-20000000}"
ELF=""
TRACE=""

die() { echo "run_act_elf.sh: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --elf)     [[ $# -ge 2 ]] || die "--elf needs a path"; ELF="$2"; shift 2 ;;
    --trace)   [[ $# -ge 2 ]] || die "--trace needs a path"; TRACE="$2"; shift 2 ;;
    --timeout) [[ $# -ge 2 ]] || die "--timeout needs a number"; TIMEOUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *)         [[ -z "${ELF}" ]] || die "unexpected argument: $1"; ELF="$1"; shift ;;
  esac
done

[[ -n "${ELF}" ]] || die "no ELF given (--elf PATH)"
[[ -f "${ELF}" ]] || die "${ELF} does not exist"

SIM="${BUILD_DIR}/verilator/tb_rv32_core_cosim/tb_rv32_core_cosim"
if [[ ! -x "${SIM}" ]]; then
  make -C "${PROJ_ROOT}" --no-print-directory SIM=verilator TB=tb_rv32_core_cosim sim-build >&2
fi

NAME="$(basename "${ELF}" .elf)"
WORK="${BUILD_DIR}/arch-test"
mkdir -p "${WORK}"

python3 "${PROJ_ROOT}/scripts/utils/elf2hex.py" "${ELF}" -o "${WORK}/${NAME}.hex" \
  --base "${RAM_BASE}" >/dev/null

# The framework's halt macros write the HTIF tohost word, the same way sw/common/crt0.S does.
TOHOST="$(riscv64-unknown-elf-nm "${ELF}" | awk '$3 == "tohost" { print $1 }')"
[[ -n "${TOHOST}" ]] || die "${ELF} has no tohost symbol: the model macros must define one"

ARGS=(+HEX="${WORK}/${NAME}.hex" +TOHOST="${TOHOST}" +TIMEOUT="${TIMEOUT}")
[[ -n "${TRACE}" ]] && ARGS+=(+TRACE="${TRACE}")

LOG="${WORK}/${NAME}.log"
"${SIM}" "${ARGS[@]}" | tee "${LOG}"

if grep -q '^PASS' "${LOG}"; then
  echo "RVCP-SUMMARY: TEST PASSED - Test File \"${NAME}\""
else
  echo "RVCP-SUMMARY: TEST FAILED - Test File \"${NAME}\""
  exit 1
fi
