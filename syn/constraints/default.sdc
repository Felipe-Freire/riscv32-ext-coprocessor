# Constraints for out-of-context synthesis of one block, used by every top that has no
# syn/constraints/<top>.sdc of its own. syn/genus/syn.tcl sets ::clk_period (ns) before reading it.
#
# One clock on clk_i. A top without clk_i (a combinational unit) gets a virtual clock, so its
# input-to-output paths are still timed. Inputs arrive and outputs are needed at 30% of the
# period: the rest of the cycle belongs to the logic of the neighbouring block. Resets are
# asynchronous and soc_top synchronizes their release, so their paths are not timed here.

set io_delay [expr {0.3 * $::clk_period}]

set clk_port  [get_ports -quiet clk_i]
set rst_ports [get_ports -quiet rst*_ni]
set in_ports  [all_inputs]

if {[sizeof_collection $clk_port] > 0} {
  create_clock -name clk -period $::clk_period $clk_port
  set in_ports [remove_from_collection $in_ports $clk_port]
} else {
  create_clock -name clk -period $::clk_period
}

if {[sizeof_collection $rst_ports] > 0} {
  set_false_path -from $rst_ports
  set in_ports [remove_from_collection $in_ports $rst_ports]
}

set_input_delay  $io_delay -clock clk $in_ports
set_output_delay $io_delay -clock clk [all_outputs]

# The neighbouring block is made of real cells: its outputs drive our inputs through a small
# buffer, and our outputs load a few of its inputs. 0.01 is in the Liberty capacitance unit
# (pF for gsclib045: 10 fF, a handful of gate inputs). The tutorial library has no BUFX2, so
# there the inputs keep an ideal driver.
if {[sizeof_collection [get_lib_cells -quiet */BUFX2]] > 0} {
  set_driving_cell -lib_cell BUFX2 $in_ports
}
set_load 0.01 [all_outputs]

# Margin for the clock tree, which synthesis treats as ideal: skew and jitter.
set_clock_uncertainty [expr {0.05 * $::clk_period}] [get_clocks clk]
