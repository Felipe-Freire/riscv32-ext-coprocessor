# Project environment, included by the top-level Makefile. Everything lives in .venv (ignored by
# git):
#
#   make venv                       Python packages of requirements.txt in .venv, and the EDA tools
#                                   of eda-tools.yml (ngspice, KLayout) in .venv/eda
#   make venv PYTHON_BOOT=<python>  the Python part built from another interpreter (default:
#                                   python3 on PATH)
#
# Every Python tool of the flows runs on $(PYTHON): the interpreter of the venv once it exists, the
# python3 on PATH before that. The simulation scripts need only the standard library, so they run
# either way; the targets whose tools come from the venv (make openram) build it first.
# `source scripts/setup.sh` activates it in a shell. Each part is rebuilt when its file changes.
#
# The EDA tools are conda packages, installed by a micromamba of fixed version, checked against its
# published SHA-256. Its package cache ($(VENV)/mamba) is emptied after the install.

VENV        ?= $(PROJ_ROOT)/.venv
PYTHON_BOOT ?= python3
VENV_STAMP   = $(VENV)/.requirements
PYTHON       = $(if $(wildcard $(VENV)/bin/python3),$(VENV)/bin/python3,python3)

EDA                ?= $(VENV)/eda
EDA_STAMP           = $(EDA)/.eda-tools
MICROMAMBA_VERSION := 2.9.0-0
MICROMAMBA_SHA256  := 366cd9cd8be14df1ab8ed50352a82111082a36686b2d389fdb79a92c3fafb3e3
MICROMAMBA_URL     := https://github.com/mamba-org/micromamba-releases/releases/download/$(MICROMAMBA_VERSION)/micromamba-linux-64
MICROMAMBA          = $(VENV)/bin/micromamba
MAMBA_ENV           = MAMBA_ROOT_PREFIX=$(VENV)/mamba

.PHONY: venv

venv: $(VENV_STAMP) $(EDA_STAMP)

$(VENV_STAMP): $(PROJ_ROOT)/requirements.txt
	@test -x $(VENV)/bin/python3 || { echo "[venv] Creating $(VENV) with $(PYTHON_BOOT)"; \
	  $(PYTHON_BOOT) -m venv $(VENV); }
	@$(VENV)/bin/python3 -m pip install --quiet --upgrade pip
	@echo "[venv] Installing requirements.txt"
	@$(VENV)/bin/python3 -m pip install --quiet -r $<
	@cp $< $@
	@echo "[venv] $(VENV): $$($(VENV)/bin/python3 --version)"

$(MICROMAMBA):
	@mkdir -p $(dir $@)
	@echo "[venv] Downloading micromamba $(MICROMAMBA_VERSION)"
	@curl -sSfL -o $@.part $(MICROMAMBA_URL)
	@echo "$(MICROMAMBA_SHA256)  $@.part" | sha256sum -c --quiet - || \
	  { echo "[venv] micromamba download does not match its SHA-256" >&2; exit 1; }
	@chmod +x $@.part && mv $@.part $@

$(EDA_STAMP): $(PROJ_ROOT)/eda-tools.yml | $(MICROMAMBA)
	@echo "[venv] Installing eda-tools.yml in $(EDA)"
	@$(MAMBA_ENV) $(MICROMAMBA) create --no-rc --yes --quiet --override-channels -p $(EDA) -f $< > /dev/null
	@$(MAMBA_ENV) $(MICROMAMBA) clean --no-rc --yes --quiet --all > /dev/null
	@cp $< $@
	@echo "[venv] $(EDA): $$($(EDA)/bin/ngspice --version | grep -o 'ngspice-[0-9]*'), $$($(EDA)/bin/klayout -v)"
