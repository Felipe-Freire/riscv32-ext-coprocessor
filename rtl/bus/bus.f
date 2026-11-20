// Interconnect: the data bus crossbar and the core's OBI -> AXI4 bridge so far; the core data-port
// demux, the control bus and bus_top come next. Needs vendor/common_cells.f, vendor/axi.f and
// rtl/common/common.f (soc_pkg) first.
${PROJ_ROOT}/rtl/bus/bus_axi_xbar.sv
${PROJ_ROOT}/rtl/bus/bus_obi2axi.sv
