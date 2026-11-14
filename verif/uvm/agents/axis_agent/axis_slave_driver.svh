// Stream slave: drives TREADY every cycle from the knobs in the configuration. It needs no
// sequence; TREADY is low during reset.

class axis_slave_driver extends uvm_component;

  axis_agent_cfg cfg;

  `uvm_component_utils(axis_slave_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned stall = 0;
    cfg.vif.tready <= 1'b0;
    forever begin
      @(cfg.vif.cb);
      if (cfg.vif.rst_ni !== 1'b1) begin
        cfg.vif.tready <= 1'b0;
        stall = 0;
      end else if (stall > 0) begin
        cfg.vif.tready <= 1'b0;
        stall--;
      end else if (cfg.stall_pct > 0 && $urandom_range(99) < cfg.stall_pct) begin
        cfg.vif.tready <= 1'b0;
        stall = $urandom_range(cfg.max_stall > 1 ? cfg.max_stall - 1 : 0);
      end else begin
        cfg.vif.tready <= ($urandom_range(99) < cfg.ready_pct);
      end
    end
  endtask

endclass
