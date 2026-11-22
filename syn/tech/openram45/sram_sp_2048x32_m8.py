# OpenRAM configuration of sram_sp_2048x32_m8: 2048 words of 32 bits (8 KiB), one read/write port,
# byte write mask. It is the tile of every SRAM of the SoC (rtl/prim/openram45): 4 deep for each TCM,
# 4 wide for each L2 bank. `make openram` runs it; the file name is the macro name, and the Makefile
# gives the output name and directory.

word_size = 32
num_words = 2048
write_size = 8          # one wmask0 bit per byte

num_rw_ports = 1
num_r_ports = 0
num_w_ports = 0

tech_name = "freepdk45"

# The typical corner of the NanGate cells (lib/freepdk45/stdcells.lib): TT, 1.1 V, 25 C. Only that
# one: the analytical model of OpenRAM 1.2.48 gives a negative clk0 -> dout0 delay at SS 0.95 V
# 125 C, and the same setup and hold at every corner, so the slow and fast corners wait for a
# SPICE characterization.
use_specified_corners = [("TT", 1.1, 25)]

# No tool the machine lacks: OpenRAM would otherwise install conda, run DRC/LVS with Magic and
# Netgen, and characterize with SPICE. The timing is then OpenRAM's analytical model.
use_conda = False
check_lvsdrc = False
analytical_delay = True

# As in OpenRAM's own FreePDK45 example of this size (32 x 2048): the supplies are not routed to
# rings and the signal pins are not moved to the edge of the macro. Enough for synthesis and STA; a
# place and route of the SoC would need both.
route_supplies = False
perimeter_pins = False
