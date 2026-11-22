# Python environment of the project, included by the top-level Makefile.
#
#   make venv                       .venv (ignored by git) with the packages of requirements.txt
#   make venv PYTHON_BOOT=<python>  built from another interpreter (default: python3 on PATH)
#
# Every Python tool of the flows runs on $(PYTHON): the interpreter of the venv once it exists, the
# python3 on PATH before that. The simulation scripts need only the standard library, so they run
# either way; the targets whose tools come from requirements.txt (make openram) build the venv
# first. `source scripts/setup.sh` activates it in a shell. The venv is rebuilt from
# requirements.txt when that file changes.

VENV        ?= $(PROJ_ROOT)/.venv
PYTHON_BOOT ?= python3
VENV_STAMP   = $(VENV)/.requirements
PYTHON       = $(if $(wildcard $(VENV)/bin/python3),$(VENV)/bin/python3,python3)

.PHONY: venv

venv: $(VENV_STAMP)

$(VENV_STAMP): $(PROJ_ROOT)/requirements.txt
	@test -x $(VENV)/bin/python3 || { echo "[venv] Creating $(VENV) with $(PYTHON_BOOT)"; \
	  $(PYTHON_BOOT) -m venv $(VENV); }
	@$(VENV)/bin/python3 -m pip install --quiet --upgrade pip
	@echo "[venv] Installing requirements.txt"
	@$(VENV)/bin/python3 -m pip install --quiet -r $<
	@cp $< $@
	@echo "[venv] $(VENV): $$($(VENV)/bin/python3 --version)"
