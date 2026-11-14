typedef uvm_sequencer #(axil_item) axil_sequencer;

class axil_agent extends uvm_agent;

  axil_agent_cfg cfg;
  axil_sequencer sqr;
  axil_driver    drv;
  axil_monitor   mon;

  `uvm_component_utils(axil_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(axil_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("CFG", "axil_agent_cfg not found in config_db")
    end
    mon     = axil_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
    if (cfg.is_active == UVM_ACTIVE) begin
      sqr     = axil_sequencer::type_id::create("sqr", this);
      drv     = axil_driver::type_id::create("drv", this);
      drv.cfg = cfg;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (cfg.is_active == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass
