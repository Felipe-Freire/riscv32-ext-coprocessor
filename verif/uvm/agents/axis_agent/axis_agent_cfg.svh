typedef enum bit {
  AxisMaster,  // drives TVALID / TDATA from a sequence
  AxisSlave    // drives TREADY on its own, following the knobs below
} axis_mode_e;

class axis_agent_cfg extends uvm_object;

  virtual axis_if         vif;
  uvm_active_passive_enum is_active  = UVM_ACTIVE;
  axis_mode_e             mode       = AxisMaster;
  int unsigned            data_width = 64;

  // Slave: every cycle TREADY is high with probability ready_pct %. With probability stall_pct %
  // per cycle a long stall starts instead, 1 to max_stall cycles with TREADY low. The knobs are
  // read every cycle, so a sequence may change them during a run.
  int unsigned ready_pct = 100;
  int unsigned stall_pct = 0;
  int unsigned max_stall = 16;

  `uvm_object_utils(axis_agent_cfg)

  function new(string name = "axis_agent_cfg");
    super.new(name);
  endfunction

endclass
