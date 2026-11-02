// Drives one item per clock cycle, starting after the reset is released.

class core_pc_driver extends uvm_driver #(core_pc_seq_item);

  core_pc_agent_cfg cfg;

  `uvm_component_utils(core_pc_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    // Known values during reset, so the DUT never sees X on its inputs
    cfg.vif.stall     <= 1'b0;
    cfg.vif.pc_set    <= 1'b0;
    cfg.vif.pc_target <= '0;

    wait (cfg.vif.rst_ni === 1'b0);
    wait (cfg.vif.rst_ni === 1'b1);

    forever begin
      seq_item_port.get_next_item(req);
      @(cfg.vif.drv_cb);
      cfg.vif.drv_cb.stall     <= req.stall;
      cfg.vif.drv_cb.pc_set    <= req.pc_set;
      cfg.vif.drv_cb.pc_target <= req.pc_target;
      seq_item_port.item_done();
    end
  endtask

endclass
