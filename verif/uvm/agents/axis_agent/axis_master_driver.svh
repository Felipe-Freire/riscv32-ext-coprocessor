// Stream master: for each item, delay idle cycles, then the beat with TVALID until TREADY. Items
// with no delay go out back to back. A reset drops the beat in flight.

class axis_master_driver extends uvm_driver #(axis_item);

  axis_agent_cfg cfg;

  `uvm_component_utils(axis_master_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    cfg.vif.tvalid <= 1'b0;
    cfg.vif.tdata  <= '0;
    forever begin
      wait (cfg.vif.rst_ni === 1'b1);
      seq_item_port.get_next_item(req);
      fork
        send(req);
        wait (cfg.vif.rst_ni !== 1'b1);
      join_any
      disable fork;
      if (cfg.vif.rst_ni !== 1'b1) begin
        cfg.vif.tvalid <= 1'b0;
      end
      seq_item_port.item_done();
    end
  endtask

  task automatic send(axis_item t);
    if (t.delay > 0) begin
      cfg.vif.tvalid <= 1'b0;
      repeat (t.delay) @(cfg.vif.cb);
    end
    cfg.vif.tdata  <= t.data;
    cfg.vif.tvalid <= 1'b1;
    do @(cfg.vif.cb); while (!cfg.vif.cb.tready);
    cfg.vif.tvalid <= 1'b0;
  endtask

endclass
