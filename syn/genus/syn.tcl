# Genus synthesis of one top module. Run it through the top-level Makefile (`make syn`), which
# starts Genus in build/syn/<top>/ and passes the settings in environment variables:
#
#   SYN_TOP         top module
#   SYN_FLIST       file list(s) holding the top and everything below it
#   SYN_SDC         constraints; they read ::clk_period and ::clk_acc_period
#   SYN_CLK_PERIOD  clk_i period in ns
#   SYN_ACC_CLK_PERIOD  clk_acc_i period in ns (coproc_top); default SYN_CLK_PERIOD
#   SYN_LIBS        Liberty files; empty selects the tutorial library shipped with Genus
#   SYN_LEFS        technology and cell LEF; empty means no physical data (zero wire load)
#   SYN_QRC         QRC extraction rules for the wire estimation; optional, used only with SYN_LEFS
#   SYN_EFFORT      effort of syn_generic, syn_map and syn_opt: low, medium or high
#
# Output, in the current directory: genus.log, reports/ and outputs/ (netlist, SDC and SDF).

proc syn_env {name {default ""}} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  if {$default eq ""} {
    error "syn.tcl: $name is not set; run the flow with `make syn`"
  }
  return $default
}

# An optional setting: empty when absent.
proc syn_env_opt {name} {
  return [expr {[info exists ::env($name)] ? [string trim $::env($name)] : ""}]
}

set top        [syn_env SYN_TOP]
set flists     [syn_env SYN_FLIST]
set sdc        [syn_env SYN_SDC]
set clk_period [syn_env SYN_CLK_PERIOD 10]
set acc_period [syn_env SYN_ACC_CLK_PERIOD $clk_period]
set effort     [syn_env SYN_EFFORT medium]
set libs       [syn_env_opt SYN_LIBS]
set lefs       [syn_env_opt SYN_LEFS]
set qrc        [syn_env_opt SYN_QRC]

# The default is GPDK045 (gsclib045), chosen in syn/syn.mk. An empty LIBS falls back to the tutorial
# library: a dozen generic cells whose area and timing only compare RTL versions with each other.
# The GPDK045 LEF does not describe those cells, so that run has no physical data.
if {$libs eq ""} {
  set libs [file normalize $::env(CDN_SYNTH_ROOT)/../share/synth/tutorials/tech/tutorial.lib]
  set lefs ""
  set qrc  ""
  puts "WARNING: LIBS not set, using the Genus tutorial library $libs"
}

# ---- Setup ------------------------------------------------------------------------------------

set_db hdl_error_on_blackbox true   ;# a module missing from the file lists stops the run
set_db auto_ungroup          none   ;# keep the hierarchy: area per stage and unit in area.rpt
set_db syn_generic_effort    $effort
set_db syn_map_effort        $effort
set_db syn_opt_effort        $effort

read_libs $libs

# With the LEF, Genus estimates each net from the placement it predicts for the cells (PLE)
# instead of using zero wire load; the QRC rules give the resistance and capacitance per length.
if {$lefs ne ""} {
  read_physical -lef $lefs
  if {$qrc ne ""} {
    set_db qrc_tech_file $qrc
  }
  set_db interconnect_mode ple
}

# Registers that share an enable get one integrated clock-gating cell instead of an enable mux in
# every flop: smaller flops with less setup, and no clock toggling while the array holds.
# SYN_CLOCK_GATING=0 turns it off, to compare both versions in the area x f_max study. Genus reads
# the attribute at elaboration, so it is set before the RTL, and only with an ICG cell in the
# library (the tutorial library has none, and syn_generic stops without one).
set icg_cells {}
foreach cell [get_db lib_cells] {
  if {[get_db $cell .clock_gating_integrated_cell] ne ""} {
    lappend icg_cells [get_db $cell .base_name]
  }
}
set clock_gating [expr {[syn_env_opt SYN_CLOCK_GATING] ne "0" && [llength $icg_cells] > 0}]
if {$clock_gating} {
  set_db lp_insert_clock_gating true
} elseif {[syn_env_opt SYN_CLOCK_GATING] ne "0"} {
  puts "WARNING: no integrated clock-gating cell in the libraries, clock gating is off"
}

# ---- RTL and constraints ----------------------------------------------------------------------

# The defines Bender passes to a Genus synthesis: the vendor IP keys its simulation-only code
# (assertions, interface wrappers Genus cannot parse) on them.
foreach flist $flists {
  read_hdl -language sv -define {SYNTHESIS TARGET_SYNTHESIS TARGET_GENUS} -f $flist
}
elaborate $top

set ::clk_period     $clk_period
set ::clk_acc_period $acc_period
read_sdc -stop_on_errors $sdc

# ---- Synthesis --------------------------------------------------------------------------------

syn_generic
syn_map
syn_opt   ;# not -logical/-spatial: they need a license feature the CEPEDI server lacks

# ---- Reports and outputs ----------------------------------------------------------------------

file mkdir reports outputs

report_qor                   > reports/qor.rpt
report_area                  > reports/area.rpt
report_gates                 > reports/gates.rpt
report_timing -max_paths 10  > reports/timing.rpt
report_power                 > reports/power.rpt
check_design -all            > reports/check_design.rpt
check_timing_intent -verbose > reports/timing_intent.rpt
report_messages              > reports/messages.rpt

report_timing -from [all_registers] -to [all_registers] -max_paths 5 > reports/timing_reg2reg.rpt

write_hdl > outputs/$top.v
write_sdc > outputs/$top.sdc
# Cell delays at this corner with an ideal clock, for gate-level simulation (SDF=1).
source [file join $::env(PROJ_ROOT) syn genus sdf.tcl]
write_ideal_clock_sdf outputs/$top.sdf

# ---- Summary ----------------------------------------------------------------------------------

set slack_ps [get_db current_design .slack]
if {[string is double -strict $slack_ps]} {
  set slack [format "%.3f ns (%s)" [expr {$slack_ps / 1000.0}] \
                 [expr {$slack_ps < 0 ? "VIOLATED" : "met"}]]
} else {
  set slack "no timed paths"
}

set physical [expr {$lefs eq "" ? "none (zero wire load)" : "PLE, [expr {$qrc eq "" ? "no QRC" : $qrc}]"}]

set clocks "$clk_period ns"
if {[llength [get_ports -quiet clk_acc_i]] > 0} {
  append clocks ", clk_acc_i $acc_period ns"
}

# An integrated clock-gating cell holds a latch; count those apart from the latches of the RTL.
set clock_gates 0
set latches     0
foreach inst [get_db insts -if {.is_latch}] {
  if {[get_db $inst .lib_cell.clock_gating_integrated_cell] ne ""} {
    incr clock_gates
  } else {
    incr latches
  }
}

set summary [join [list \
  [format "%-14s %s" "Top"          $top] \
  [format "%-14s %s" "File lists"   $flists] \
  [format "%-14s %s" "Libraries"    $libs] \
  [format "%-14s %s" "Wires"        $physical] \
  [format "%-14s %s" "Clock period" $clocks] \
  [format "%-14s %s" "Effort"       $effort] \
  [format "%-14s %s" "Clock gating" [expr {$clock_gating ? "on, $clock_gates cells" : "off"}]] \
  [format "%-14s %s" "Worst slack"  $slack] \
  [format "%-14s %.1f" "Cell area"  [get_db current_design .area]] \
  [format "%-14s %d" "Cells"        [llength [get_db insts]]] \
  [format "%-14s %d" "Flip-flops"   [llength [get_db insts -if {.is_flop}]]] \
  [format "%-14s %d" "Latches"      $latches] \
  [format "%-14s %s" "Genus"        [get_db program_version]] \
] "\n"]

set fh [open reports/summary.rpt w]
puts $fh $summary
close $fh
puts "\n$summary\n"
