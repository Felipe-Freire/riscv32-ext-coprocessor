#!/usr/bin/env bash
# Build and install Spike (vendor/riscv-isa-sim), the RISC-V ISA simulator used as
# reference model, a bare-metal RISC-V GCC if none is installed, and the Python environment of
# riscv-dv (vendor/riscv-dv, the random program generator) in build/venv. Run it from any directory:
#
#   ./setup.sh [--prefix DIR] [--jobs N] [--skip-deps] [--clean]
#
# Installs into $RISCV (default: build/riscv). Debian/Ubuntu (apt) and RHEL/Rocky/Fedora (dnf).
# The Makefile finds build/riscv by itself; for another prefix, put it on the PATH with
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

APT_PACKAGES=(build-essential device-tree-compiler libboost-regex-dev libboost-system-dev gcc-riscv64-unknown-elf picolibc-riscv64-unknown-elf)
# RHEL has no bare-metal RISC-V GCC package (EPEL's gcc-riscv64-linux-gnu has no rv32 libgcc), so
# the toolchain comes from the xPack prebuilt binaries instead, see step 3.
DNF_PACKAGES=(gcc-c++ make dtc boost-devel xz curl tar python3)

# xPack riscv-none-elf-gcc: bare-metal, rv32i/ilp32 multilib included, installs without root.
XPACK_VERSION="14.2.0-3"
XPACK_NAME="xpack-riscv-none-elf-gcc-${XPACK_VERSION}"
XPACK_URL="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${XPACK_VERSION}/${XPACK_NAME}-linux-x64.tar.gz"

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
# Only what this project builds against. riscv-gnu-toolchain is deliberately NOT recursed
# into: its nested submodules are GCC's test harness (dejagnu, from savannah.gnu.org, which
# is unreliable and regularly returns HTTP 500) and are needed only to build GCC from source.
# The toolchain comes from apt instead, see APT_PACKAGES above.
info "Fetching submodules"
git -C "${PROJ_ROOT}" submodule update --init \
  vendor/axi vendor/common_cells vendor/riscv-arch-test vendor/riscv-dv
# Spike needs its own berkeley-softfloat-3, so this one is recursive.
git -C "${PROJ_ROOT}" submodule update --init --recursive vendor/riscv-isa-sim

[[ -f "${SPIKE_SRC}/configure" ]] || die "${SPIKE_SRC}/configure missing: submodule checkout failed"

# --- 2. Dependencies ---------------------------------------------------------
if [[ "${SKIP_DEPS}" -eq 1 ]]; then
  info "Skipping dependency install (--skip-deps)"
elif command -v apt-get >/dev/null 2>&1; then
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
elif command -v dnf >/dev/null 2>&1; then
  packages=("${DNF_PACKAGES[@]}")
  # The verilator package alone cannot build anything: its include/ is in verilator-devel.
  rpm -q verilator >/dev/null 2>&1 && packages+=(verilator-devel)
  missing=()
  for pkg in "${packages[@]}"; do
    rpm -q "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
  done
  if [[ "${#missing[@]}" -eq 0 ]]; then
    info "Dependencies already installed"
  else
    info "Installing: ${missing[*]}"
    # dtc and boost-devel are in AppStream; verilator-devel needs EPEL, which is optional here.
    "${SUDO[@]}" dnf install -y "${missing[@]}"
  fi
else
  info "Neither apt-get nor dnf found: install a C++17 compiler, make, dtc and Boost yourself"
fi

# --- 3. Bare-metal RISC-V GCC ------------------------------------------------
# sw/sw.mk calls riscv64-unknown-elf-gcc, from the PATH or from ${PREFIX}/bin. Without one, the
# xPack riscv-none-elf-gcc is unpacked into ${PREFIX} and linked under the riscv64-unknown-elf-
# names, so the Makefile and the arch-test scripts work unchanged.
if command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
  info "RISC-V GCC: $(command -v riscv64-unknown-elf-gcc)"
elif [[ -x "${PREFIX}/bin/riscv64-unknown-elf-gcc" ]]; then
  info "RISC-V GCC: ${PREFIX}/bin/riscv64-unknown-elf-gcc"
else
  info "Installing ${XPACK_NAME} into ${PREFIX}"
  mkdir -p "${PREFIX}/bin" "${BUILD_DIR}"
  tarball="${BUILD_DIR}/${XPACK_NAME}.tar.gz"
  curl -fL --retry 3 -o "${tarball}" "${XPACK_URL}"
  expected="$(curl -fsL "${XPACK_URL}.sha" | awk '{ print $1 }')"
  actual="$(sha256sum "${tarball}" | awk '{ print $1 }')"
  [[ -n "${expected}" && "${expected}" == "${actual}" ]] \
    || die "${XPACK_NAME}: checksum mismatch (expected '${expected}', got '${actual}')"
  tar -xzf "${tarball}" -C "${PREFIX}"
  rm -f "${tarball}"
  for tool in "${PREFIX}/${XPACK_NAME}/bin/riscv-none-elf-"*; do
    ln -sf "${tool}" "${PREFIX}/bin/riscv64-unknown-elf-${tool##*/riscv-none-elf-}"
  done
  "${PREFIX}/bin/riscv64-unknown-elf-gcc" --version | head -1
fi

# --- 4. Python environment for riscv-dv ------------------------------------
# Only what the generator step of riscv-dv needs (PyYAML; bitstring for its CSR test), in a venv so
# nothing touches the system Python. The Makefile uses build/venv/bin/python3 for riscv-dv only.
VENV="${PROJ_ROOT}/build/venv"
if "${VENV}/bin/python3" -c "import yaml, bitstring" >/dev/null 2>&1; then
  info "riscv-dv Python environment: ${VENV}"
else
  info "Creating the riscv-dv Python environment in ${VENV}"
  /usr/bin/python3 -m venv "${VENV}" 2>/dev/null || python3 -m venv "${VENV}"
  "${VENV}/bin/python3" -m pip install -q PyYAML bitstring
fi

# --- 5. Configure and build (out of tree, under build/) ----------------------
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

# --- 6. Install --------------------------------------------------------------
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
