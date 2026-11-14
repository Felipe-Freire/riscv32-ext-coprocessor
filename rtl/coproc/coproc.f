// Systolic-array matrix coprocessor: package first, then the leaf cells, the array, the core and
// the registers, then the block top. coproc_top also needs cdc_2phase and cdc_fifo_gray from
// vendor/common_cells.f.
${PROJ_ROOT}/rtl/coproc/coproc_pkg.sv
${PROJ_ROOT}/rtl/coproc/coproc_mac.sv
${PROJ_ROOT}/rtl/coproc/coproc_pe.sv
${PROJ_ROOT}/rtl/coproc/coproc_demux.sv
${PROJ_ROOT}/rtl/coproc/coproc_pe_array.sv
${PROJ_ROOT}/rtl/coproc/coproc_skew.sv
${PROJ_ROOT}/rtl/coproc/coproc_core.sv
${PROJ_ROOT}/rtl/coproc/coproc_regs.sv
${PROJ_ROOT}/rtl/coproc/coproc_top.sv
