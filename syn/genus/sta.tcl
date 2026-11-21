# Static timing analysis of a gate-level netlist with the Genus timer. Run it through the
# top-level Makefile (`make sta`), which starts Genus in build/sta/<top>/<corner>/ with:
#
#   STA_TOP      top module of the netlist
#   STA_NETLIST  gate-level netlist (default: the one `make syn` wrote)
#   STA_SDC      constraints (default: the SDC `make syn` wrote, with every value resolved)
#   STA_CORNER   corner name, for the summary
#   SYN_LIBS, SYN_LEFS, SYN_QRC, SYN_CAPTBL  technology, as in syn.tcl
#
# Genus times setup and checks max transition, capacitance and fanout. It has no hold analysis,
# which needs Tempus. Output, in the current directory: genus.log, reports/ and outputs/<top>.sdf
# with the cell delays of this corner and an ideal clock (sdf.tcl), for gate-level simulation.

proc sta_env {name} {
  if {![info exists ::env($name)] || [string trim $::env($name)] eq ""} {
    error "sta.tcl: $name is not set; run the flow with `make sta`"
  }
  return [string trim $::env($name)]
}

proc sta_env_opt {name} {
  return [expr {[info exists ::env($name)] ? [string trim $::env($name)] : ""}]
}

set top     [sta_env STA_TOP]
set netlist [sta_env STA_NETLIST]
set sdc     [sta_env STA_SDC]
set corner  [sta_env STA_CORNER]
set libs    [sta_env_opt SYN_LIBS]
set lefs    [sta_env_opt SYN_LEFS]
set qrc     [sta_env_opt SYN_QRC]
set captbl  [sta_env_opt SYN_CAPTBL]

# Same fallback as syn.tcl: no Liberty files means the tutorial library, without physical data.
if {$libs eq ""} {
  set libs [file normalize $::env(CDN_SYNTH_ROOT)/../share/synth/tutorials/tech/tutorial.lib]
  set lefs   ""
  set qrc    ""
  set captbl ""
  puts "WARNING: LIBS not set, using the Genus tutorial library $libs"
}

# ---- Design -----------------------------------------------------------------------------------

read_libs $libs

# Wires estimated as in synthesis (PLE) when the LEF is there, zero wire load otherwise.
if {$lefs ne ""} {
  read_physical -lef $lefs
  if {$qrc ne ""} {
    set_db qrc_tech_file $qrc
  } elseif {$captbl ne ""} {
    set_db cap_table_file $captbl
  }
  set_db interconnect_mode ple
}

read_netlist -top $top $netlist
read_sdc -stop_on_errors $sdc

# ---- Reports ----------------------------------------------------------------------------------

file mkdir reports outputs

report_clocks                                                  > reports/clocks.rpt
report_qor                                                     > reports/qor.rpt
report_timing -max_paths 20                                    > reports/timing.rpt
if {[llength [all_registers]] > 0} {   ;# a combinational top has none, and -from would stop
  report_timing -from [all_registers] -to [all_registers] -max_paths 10 > reports/timing_reg2reg.rpt
}
report_timing -path_type endpoint -max_paths 100               > reports/endpoints.rpt
report_constraint -all_violators                               > reports/violators.rpt
check_timing_intent -verbose                                   > reports/check_timing.rpt

source [file join $::env(PROJ_ROOT) syn genus sdf.tcl]
write_ideal_clock_sdf outputs/$top.sdf

# ---- Summary ----------------------------------------------------------------------------------

proc ns {ps} {
  return [expr {[string is double -strict $ps] ? [format "%.3f ns" [expr {$ps / 1000.0}]] : $ps}]
}

set slack_ps [get_db current_design .slack]
if {[string is double -strict $slack_ps]} {
  set slack "[ns $slack_ps] ([expr {$slack_ps < 0 ? "VIOLATED" : "met"}])"
} else {
  set slack "no timed paths"
}

set clocks {}
foreach clk [get_db clocks] {
  lappend clocks "[get_db $clk .base_name] [ns [get_db $clk .period]]"
}

set summary [join [list \
  [format "%-14s %s" "Top"         $top] \
  [format "%-14s %s" "Netlist"     $netlist] \
  [format "%-14s %s" "Corner"      $corner] \
  [format "%-14s %s" "Libraries"   $libs] \
  [format "%-14s %s" "Wires"       [expr {$lefs eq "" ? "zero wire load" : "PLE"}]] \
  [format "%-14s %s" "Clocks"      [join $clocks ", "]] \
  [format "%-14s %s" "Worst slack" $slack] \
  [format "%-14s %s" "Total neg."  [ns [get_db current_design .tns]]] \
  [format "%-14s %s" "Hold"        "not checked (Genus has no hold analysis)"] \
  [format "%-14s %s" "Genus"       [get_db program_version]] \
] "\n"]

set fh [open reports/summary.rpt w]
puts $fh $summary
close $fh
puts "\n$summary\n"
