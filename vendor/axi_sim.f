// pulp-platform/axi (vendor/axi): the simulation-only files, in the order of the `simulation` and
// `test` targets of its Bender.yml. Simulation only: never read by synthesis.
// Needs common_cells.f and axi.f (the RTL lists) and common_verification.f first.
//   axi_test.sv        random masters and slaves, scoreboard (classes in package axi_test)
//   axi_sim_mem.sv     AXI4 memory model with direct access to its byte array
//   tb_axi_xbar_pkg.sv axi_xbar_monitor, the routing checker of the upstream axi_xbar testbench
${PROJ_ROOT}/vendor/axi/src/axi_chan_compare.sv
${PROJ_ROOT}/vendor/axi/src/axi_dumper.sv
${PROJ_ROOT}/vendor/axi/src/axi_sim_mem.sv
${PROJ_ROOT}/vendor/axi/src/axi_test.sv
${PROJ_ROOT}/vendor/axi/test/tb_axi_xbar_pkg.sv
