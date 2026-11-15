# coproc_top: the clk_i domain of default.sdc (register port and streams, all its I/O), plus the
# array clock clk_acc_i, with the period in ::clk_acc_period (ACC_CLK_PERIOD, ns).
#
# The two clocks are unrelated. They meet only inside the cdc_fifo_gray and cdc_2phase cells of
# common_cells (gray pointers, FIFO slots and handshake data), so every path from one domain to
# the other is one of those. As the cells' documentation asks, bound them to the shorter of the two
# periods instead of the edge relation of two unrelated clocks, and do not check hold on them.

source $::env(PROJ_ROOT)/syn/constraints/default.sdc

create_clock -name clk_acc -period $::clk_acc_period [get_ports clk_acc_i]
set_clock_uncertainty [expr {0.05 * $::clk_acc_period}] [get_clocks clk_acc]

set cdc_max_delay [expr {min($::clk_period, $::clk_acc_period)}]
set_max_delay $cdc_max_delay -from [get_clocks clk]     -to [get_clocks clk_acc]
set_max_delay $cdc_max_delay -from [get_clocks clk_acc] -to [get_clocks clk]
set_false_path -hold -from [get_clocks clk]     -to [get_clocks clk_acc]
set_false_path -hold -from [get_clocks clk_acc] -to [get_clocks clk]
