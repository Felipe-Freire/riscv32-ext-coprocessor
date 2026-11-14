// Publishes every beat on its handshake, with the gap before it and how long it waited for
// TREADY. A beat with X in its data_width bits is an error. A handshake on the clock edge where a
// reset is asserted does not count: the reset clears whatever the edge stored.

class axis_monitor extends uvm_monitor;

  axis_agent_cfg                 cfg;
  uvm_analysis_port #(axis_item) ap;

  `uvm_component_utils(axis_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned          gap = 0, stall = 0;
    bit [AXIS_MAX_DW-1:0] mask;
    axis_item             t;
    mask = (cfg.data_width >= AXIS_MAX_DW) ? '1 : ((AXIS_MAX_DW'(1) << cfg.data_width) - 1);
    forever begin
      @(cfg.vif.cb);
      if (cfg.vif.cb.rst_ni !== 1'b1 || cfg.vif.rst_ni !== 1'b1) begin
        gap   = 0;
        stall = 0;
      end else if (cfg.vif.cb.tvalid && cfg.vif.cb.tready) begin
        t       = axis_item::type_id::create("t");
        t.data  = cfg.vif.cb.tdata & mask;
        t.gap   = gap;
        t.stall = stall;
        if ($isunknown(cfg.vif.cb.tdata & mask)) begin
          `uvm_error("AXIS_MON", $sformatf("%s: beat with X in tdata", get_full_name()))
        end
        `uvm_info("AXIS_MON", t.convert2string(), UVM_HIGH)
        ap.write(t);
        gap   = 0;
        stall = 0;
      end else if (cfg.vif.cb.tvalid) begin
        stall++;
      end else begin
        gap++;
      end
    end
  endtask

endclass
