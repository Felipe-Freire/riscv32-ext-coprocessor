# Download of the FreePDK45 kit with the NanGate Open Cell Library, as packaged for mflowgen by
# Cornell (github.com/mflowgen/freepdk-45nm). Included by the top-level Makefile.
#
#   make freepdk45                  views to lib/freepdk45 (ignored by git), where tech.mk looks
#   make freepdk45 FREEPDK45=<dir>  views to another directory
#
# The files come from one fixed commit of that repository, and SHA256SUMS next to this file holds
# their checksums, so every machine synthesizes with the same cells. Only the views the flows read
# are fetched (no GDS, CDL or DRC/LVS rules):
#   stdcells.lib, stdcells-wc.lib, stdcells-bc.lib   Liberty: typical, slow and fast corners
#   rtk-tech.lef, stdcells.lef                       technology LEF (metal1-metal10) and cell LEF
#   rtk-typical.captable                             wire capacitance per length, for PLE
#   stdcells.v                                       Verilog models, for gate-level simulation
#   README.md                                        origin and changes of the package
# FreePDK45 is a generic PDK that cannot be fabricated, and the NanGate files carry their own
# license terms, so they stay out of git like any other PDK.

FREEPDK45_URL   := https://raw.githubusercontent.com/mflowgen/freepdk-45nm
FREEPDK45_REV   := d3be42a72ca6eabff54a4f3be50c16613f69f1b6
FREEPDK45_SUMS  := $(PROJ_ROOT)/syn/tech/freepdk45/SHA256SUMS
FREEPDK45_FILES := $(shell awk '{print $$2}' $(FREEPDK45_SUMS))
# Destination: FREEPDK45 when given, the default kit directory of tech.mk otherwise.
FREEPDK45_DEST   = $(if $(filter command line environment override,$(origin FREEPDK45)),$(FREEPDK45),$(firstword $(FREEPDK45_PATHS)))

.PHONY: freepdk45

freepdk45:
	@mkdir -p $(FREEPDK45_DEST)
	@cd $(FREEPDK45_DEST) && for f in $(FREEPDK45_FILES); do \
	  echo "[freepdk45] $$f"; \
	  curl -fsSL -o $$f.part $(FREEPDK45_URL)/$(FREEPDK45_REV)/$$f && mv $$f.part $$f || \
	    { rm -f $$f.part; echo "[freepdk45] Download of $$f failed" >&2; exit 1; }; \
	done
	@cd $(FREEPDK45_DEST) && sha256sum --quiet -c $(FREEPDK45_SUMS) || \
	  { echo "[freepdk45] Checksum mismatch in $(FREEPDK45_DEST)" >&2; exit 1; }
	@echo "[freepdk45] FreePDK45/NanGate views in $(FREEPDK45_DEST) (mflowgen/freepdk-45nm @ $(FREEPDK45_REV))"
