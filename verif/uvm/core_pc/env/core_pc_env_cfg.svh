class core_pc_env_cfg extends uvm_object;

  core_pc_agent_cfg agent_cfg;
  logic [31:0]      boot_addr;     // BootAddr parameter of the DUT
  bit               has_coverage = 1'b1;

  `uvm_object_utils(core_pc_env_cfg)

  function new(string name = "core_pc_env_cfg");
    super.new(name);
  endfunction

endclass
