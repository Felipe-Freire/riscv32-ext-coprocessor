typedef uvm_sequencer #(axis_item) axis_sequencer;

class axis_agent extends uvm_agent;

  axis_agent_cfg     cfg;
  axis_sequencer     sqr;
  axis_master_driver mdrv;
  axis_slave_driver  sdrv;
  axis_monitor       mon;

  `uvm_component_utils(axis_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(axis_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("CFG", "axis_agent_cfg not found in config_db")
    end
    mon     = axis_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
    if (cfg.is_active == UVM_ACTIVE) begin
      if (cfg.mode == AxisMaster) begin
        sqr      = axis_sequencer::type_id::create("sqr", this);
        mdrv     = axis_master_driver::type_id::create("mdrv", this);
        mdrv.cfg = cfg;
      end else begin
        sdrv     = axis_slave_driver::type_id::create("sdrv", this);
        sdrv.cfg = cfg;
      end
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (cfg.is_active == UVM_ACTIVE && cfg.mode == AxisMaster) begin
      mdrv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass
