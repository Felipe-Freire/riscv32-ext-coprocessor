class axil_agent_cfg extends uvm_object;

  virtual axil_if         vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  // With delays off, the master raises every valid and ready as early as it can.
  bit                     delays = 1'b1;

  `uvm_object_utils(axil_agent_cfg)

  function new(string name = "axil_agent_cfg");
    super.new(name);
  endfunction

endclass
