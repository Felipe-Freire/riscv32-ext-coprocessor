#!/usr/bin/env bash
# Project environment setup. Source it from any directory:
#   source scripts/setup.sh
# It exports PROJ_ROOT and activates the Python environment .venv when it exists (make venv).

export PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "PROJ_ROOT=${PROJ_ROOT}"
if [ -f "${PROJ_ROOT}/.venv/bin/activate" ]; then
  source "${PROJ_ROOT}/.venv/bin/activate"
  echo "Python environment: ${PROJ_ROOT}/.venv ($(python3 --version))"
else
  echo "No Python environment yet: run make venv"
fi
