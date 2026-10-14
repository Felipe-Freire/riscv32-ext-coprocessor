#!/usr/bin/env bash
# Project environment setup. Source it from any directory:
#   source scripts/setup.sh

export PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "PROJ_ROOT=${PROJ_ROOT}"
