class core_pc_agent extends uvm_agent;

  core_pc_agent_cfg cfg;
  core_pc_sequencer sqr;
  core_pc_driver    drv;
  core_pc_monitor   mon;

  `uvm_component_utils(core_pc_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(core_pc_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("CFG", "core_pc_agent_cfg not found in config_db")
    end
    mon     = core_pc_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
    if (cfg.is_active == UVM_ACTIVE) begin
      sqr     = core_pc_sequencer::type_id::create("sqr", this);
      drv     = core_pc_driver::type_id::create("drv", this);
      drv.cfg = cfg;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (cfg.is_active == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass
