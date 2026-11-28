# OpenRAM configuration of sram_sp_2048x32_m8: 2048 words of 32 bits (8 KiB), one read/write port,
# byte write mask. It is the tile of every SRAM of the SoC (rtl/prim/openram45): 4 deep for each TCM,
# 4 wide for each L2 bank. `make openram` and `make openram-char` run it; the file name is the macro
# name, and the Makefile gives the output name and directory.

word_size = 32
num_words = 2048
write_size = 8          # one wmask0 bit per byte

num_rw_ports = 1
num_r_ports = 0
num_w_ports = 0

tech_name = "freepdk45"

# make openram: the layout flow of OpenRAM's sky130 macros. Supply rings and every pin on the edge
# of the macro, for place and route, then DRC and LVS of the final layout with KLayout. The tools
# come from PATH, where the Makefile puts the conda environment of the venv (eda-tools.yml) first,
# so OpenRAM's own conda installer is off.
use_conda = False
route_supplies = "ring"
perimeter_pins = True
check_lvsdrc = True

# make openram: timing from OpenRAM's analytical model, at the typical corner of the NanGate cells
# (TT, 1.1 V, 25 C). The model is only plausible there: at SS 0.95 V 125 C it gives a negative
# clk0 -> dout0 delay, and it gives the same setup and hold at every corner.
analytical_delay = True
use_specified_corners = [("TT", 1.1, 25)]

# make openram-char: ngspice characterization at the PVT of the three NanGate corners, one OpenRAM
# run per corner (scripts/utils/openram_macro.py --char). The process corner selects the FreePDK45
# transistor models OpenRAM ships (models_nom, models_ss, models_ff). OpenRAM simulates a netlist
# trimmed to the rows and columns of the measured access and takes the leakage from the full array.
spice_corners = [("TT", 1.1, 25), ("SS", 0.95, 125), ("FF", 1.25, 0)]
spice_name = "ngspice"
num_sim_threads = 4
