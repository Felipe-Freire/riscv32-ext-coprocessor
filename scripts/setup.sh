#!/usr/bin/env bash
# Project environment setup. Source it from any directory:
#   source scripts/setup.sh
# It exports PROJ_ROOT and, once `make venv` has built them, activates the Python environment .venv
# and puts the EDA tools of .venv/eda (ngspice, KLayout) at the end of PATH. At the end, so that the
# other programs of that conda environment (its own python3, among others) never shadow the ones
# of the system or of .venv.

export PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "PROJ_ROOT=${PROJ_ROOT}"
if [ -f "${PROJ_ROOT}/.venv/bin/activate" ]; then
  source "${PROJ_ROOT}/.venv/bin/activate"
  echo "Python environment: ${PROJ_ROOT}/.venv ($(python3 --version))"
else
  echo "No Python environment yet: run make venv"
fi
if [ -d "${PROJ_ROOT}/.venv/eda/bin" ]; then
  case ":${PATH}:" in
    *":${PROJ_ROOT}/.venv/eda/bin:"*) ;;
    *) export PATH="${PATH}:${PROJ_ROOT}/.venv/eda/bin" ;;
  esac
  echo "EDA tools: ${PROJ_ROOT}/.venv/eda/bin (ngspice, klayout)"
fi
