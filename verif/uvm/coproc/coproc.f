// UVM environment of coproc_top. Compile after the RTL: vendor/common_cells.f and
// rtl/coproc/coproc.f. The golden model is C++ called through DPI-C; xrun compiles the .cc file
// with the rest.
-f ${PROJ_ROOT}/verif/uvm/agents/axil_agent/axil_agent.f
-f ${PROJ_ROOT}/verif/uvm/agents/axis_agent/axis_agent.f
+incdir+${PROJ_ROOT}/verif/uvm/coproc/env
+incdir+${PROJ_ROOT}/verif/uvm/coproc/seq
+incdir+${PROJ_ROOT}/verif/uvm/coproc/tests
${PROJ_ROOT}/verif/models/coproc/coproc_model.cc
${PROJ_ROOT}/verif/models/coproc/coproc_model_pkg.sv
${PROJ_ROOT}/verif/uvm/coproc/tb/coproc_tb_if.sv
${PROJ_ROOT}/verif/uvm/coproc/env/coproc_env_pkg.sv
${PROJ_ROOT}/verif/uvm/coproc/seq/coproc_seq_pkg.sv
${PROJ_ROOT}/verif/uvm/coproc/tests/coproc_test_pkg.sv
${PROJ_ROOT}/verif/uvm/coproc/tb/tb_coproc.sv
