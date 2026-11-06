// UVM environment for core_pc. Compile after the RTL (rtl/core/core.f).
+incdir+${PROJ_ROOT}/verif/uvm/agents/core_pc_agent
+incdir+${PROJ_ROOT}/verif/uvm/core_pc/env
+incdir+${PROJ_ROOT}/verif/uvm/core_pc/seq
+incdir+${PROJ_ROOT}/verif/uvm/core_pc/tests
${PROJ_ROOT}/verif/uvm/agents/core_pc_agent/core_pc_if.sv
${PROJ_ROOT}/verif/uvm/agents/core_pc_agent/core_pc_agent_pkg.sv
${PROJ_ROOT}/verif/uvm/core_pc/env/core_pc_env_pkg.sv
${PROJ_ROOT}/verif/uvm/core_pc/seq/core_pc_seq_pkg.sv
${PROJ_ROOT}/verif/uvm/core_pc/tests/core_pc_test_pkg.sv
${PROJ_ROOT}/verif/uvm/core_pc/tb/tb_core_pc.sv
