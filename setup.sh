#!/usr/bin/env bash
# Build and install Spike (vendor/riscv-isa-sim), the RISC-V ISA simulator used as
# reference model. Run it from any directory:
#
#   ./setup.sh [--prefix DIR] [--jobs N] [--skip-deps] [--clean]
#
# Installs into $RISCV (default: build/riscv). Afterwards, put it on the PATH with
#   export RISCV=<prefix>
#   export PATH="$RISCV/bin:$PATH"

set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_SRC="${PROJ_ROOT}/vendor/riscv-isa-sim"
BUILD_DIR="${PROJ_ROOT}/build/spike"

PREFIX="${RISCV:-${PROJ_ROOT}/build/riscv}"
JOBS="$(nproc 2>/dev/null || echo 4)"
SKIP_DEPS=0
CLEAN=0

APT_PACKAGES=(build-essential device-tree-compiler libboost-regex-dev libboost-system-dev)

die()  { echo "setup.sh: $*" >&2; exit 1; }
info() { echo "==> $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)    [[ $# -ge 2 ]] || die "--prefix needs a directory"; PREFIX="$2"; shift 2 ;;
    --prefix=*)  PREFIX="${1#*=}"; shift ;;
    --jobs|-j)   [[ $# -ge 2 ]] || die "--jobs needs a number"; JOBS="$2"; shift 2 ;;
    --jobs=*)    JOBS="${1#*=}"; shift ;;
    --skip-deps) SKIP_DEPS=1; shift ;;
    --clean)     CLEAN=1; shift ;;
    -h|--help)   sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *)           die "unknown option: $1 (see --help)" ;;
  esac
done

# Root can apt-get and install directly; anyone else needs sudo for those two steps.
if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  SUDO=()
  info "sudo not found: apt-get and 'make install' will run as $(id -un)"
fi

# --- 1. Submodules -----------------------------------------------------------
info "Fetching submodules"
git -C "${PROJ_ROOT}" submodule update --init --recursive

[[ -f "${SPIKE_SRC}/configure" ]] || die "${SPIKE_SRC}/configure missing: submodule checkout failed"

# --- 2. Dependencies ---------------------------------------------------------
if [[ "${SKIP_DEPS}" -eq 1 ]]; then
  info "Skipping dependency install (--skip-deps)"
elif ! command -v apt-get >/dev/null 2>&1; then
  info "apt-get not found: install these yourself: ${APT_PACKAGES[*]}"
else
  missing=()
  for pkg in "${APT_PACKAGES[@]}"; do
    dpkg -s "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
  done
  if [[ "${#missing[@]}" -eq 0 ]]; then
    info "Dependencies already installed"
  else
    info "Installing: ${missing[*]}"
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y "${missing[@]}"
  fi
fi

# --- 3. Configure and build (out of tree, under build/) ----------------------
if [[ "${CLEAN}" -eq 1 ]]; then
  info "Removing ${BUILD_DIR}"
  rm -rf "${BUILD_DIR}"
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

if [[ ! -f Makefile ]]; then
  info "Configuring with --prefix=${PREFIX}"
  "${SPIKE_SRC}/configure" --prefix="${PREFIX}"
else
  info "Reusing existing configuration in ${BUILD_DIR} (--clean to reconfigure)"
fi

info "Building with ${JOBS} jobs"
make "-j${JOBS}"

# --- 4. Install --------------------------------------------------------------
# Only ask for sudo when the prefix is not writable by the current user.
install_sudo=("${SUDO[@]}")
mkdir -p "${PREFIX}" 2>/dev/null || true
if [[ -w "${PREFIX}" ]]; then
  install_sudo=()
fi

info "Installing into ${PREFIX}"
"${install_sudo[@]}" make install

cat <<EOF

Spike installed: ${PREFIX}/bin/spike
Add it to your environment with:

  export RISCV="${PREFIX}"
  export PATH="\$RISCV/bin:\$PATH"
EOF
