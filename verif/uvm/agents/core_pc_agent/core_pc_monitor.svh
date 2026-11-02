// Publishes one item per rising edge: the inputs and the PC as they were just before the edge.

class core_pc_monitor extends uvm_monitor;

  core_pc_agent_cfg                     cfg;
  uvm_analysis_port #(core_pc_seq_item) ap;

  `uvm_component_utils(core_pc_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    core_pc_seq_item tr;
    forever begin
      @(cfg.vif.mon_cb);
      tr           = core_pc_seq_item::type_id::create("tr");
      tr.rst_n     = cfg.vif.mon_cb.rst_ni;
      tr.stall     = cfg.vif.mon_cb.stall;
      tr.pc_set    = cfg.vif.mon_cb.pc_set;
      tr.pc_target = cfg.vif.mon_cb.pc_target;
      tr.pc        = cfg.vif.mon_cb.pc;
      `uvm_info("MON", tr.convert2string(), UVM_DEBUG)
      ap.write(tr);
    end
  endtask

endclass
