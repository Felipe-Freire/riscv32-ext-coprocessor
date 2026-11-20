# SDF for gate-level simulation, sourced by syn.tcl and sta.tcl.
#
# Before clock-tree synthesis the timing is checked with an ideal clock: every flop sees the edge
# at the same time, with no latency. The SDF says the same, so gate-level simulation and timing
# agree. Genus would otherwise write the delay of the clock-gating cells (CK to ECK, around 200 ps
# in gsclib045) while the ungated flops switch at the edge: skew that no check accounts for, and
# races with inputs that the testbench changes on the edge. Tempus writes this SDF with
# -ideal_clock_network; Genus has no such option, so the arcs are annotated with zero first.

proc write_ideal_clock_sdf {file} {
  set gates 0
  foreach inst [get_db insts] {
    if {[get_db $inst .lib_cell.clock_gating_integrated_cell] eq ""} {
      continue
    }
    set clk_pin [get_db $inst .pins -if {.lib_pin.clock_gate_clock_pin == true}]
    set out_pin [get_db $inst .pins -if {.lib_pin.clock_gate_out_pin == true}]
    if {$clk_pin ne "" && $out_pin ne ""} {
      set_annotated_delay -cell -from $clk_pin -to $out_pin 0
      incr gates
    }
  }
  write_sdf -setuphold merge_always -recrem merge_always > $file
  puts "SDF $file: ideal clock, $gates clock-gating cells with zero delay"
}
