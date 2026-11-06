class core_pc_agent_cfg extends uvm_object;

  virtual core_pc_if     vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  `uvm_object_utils(core_pc_agent_cfg)

  function new(string name = "core_pc_agent_cfg");
    super.new(name);
  endfunction

endclass
