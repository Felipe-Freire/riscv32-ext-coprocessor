// AXI4-Lite master. A write raises AW and W independently (each after its own delay) and then
// accepts B; a read raises AR and then accepts R. The response is written back into the item, so
// a sequence (or the register layer) reads it after finish_item.
//
// A reset aborts the transaction in flight: the item returns with resp = 2'b11 and the outputs go
// back to idle until the reset is released.

class axil_driver extends uvm_driver #(axil_item);

  axil_agent_cfg cfg;

  `uvm_component_utils(axil_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    idle();
    forever begin
      wait (cfg.vif.rst_ni === 1'b1);
      seq_item_port.get_next_item(req);
      fork
        begin
          if (req.kind == AxilWrite) begin
            write(req);
          end else begin
            read(req);
          end
        end
        begin
          wait (cfg.vif.rst_ni !== 1'b1);
          req.resp = 2'b11;
        end
      join_any
      disable fork;
      if (cfg.vif.rst_ni !== 1'b1) begin
        idle();
      end
      seq_item_port.item_done();
    end
  endtask

  function void idle();
    cfg.vif.awvalid <= 1'b0;
    cfg.vif.wvalid  <= 1'b0;
    cfg.vif.bready  <= 1'b0;
    cfg.vif.arvalid <= 1'b0;
    cfg.vif.rready  <= 1'b0;
    cfg.vif.awaddr  <= '0;
    cfg.vif.wdata   <= '0;
    cfg.vif.wstrb   <= '0;
    cfg.vif.araddr  <= '0;
  endfunction

  task automatic wait_cycles(int unsigned n);
    if (cfg.delays) begin
      repeat (n) @(cfg.vif.cb);
    end
  endtask

  task automatic write(axil_item t);
    fork
      begin
        wait_cycles(t.aw_delay);
        cfg.vif.awaddr  <= t.addr;
        cfg.vif.awvalid <= 1'b1;
        do @(cfg.vif.cb); while (!cfg.vif.cb.awready);
        cfg.vif.awvalid <= 1'b0;
      end
      begin
        wait_cycles(t.w_delay);
        cfg.vif.wdata  <= t.data;
        cfg.vif.wstrb  <= t.strb;
        cfg.vif.wvalid <= 1'b1;
        do @(cfg.vif.cb); while (!cfg.vif.cb.wready);
        cfg.vif.wvalid <= 1'b0;
      end
    join
    wait_cycles(t.b_delay);
    cfg.vif.bready <= 1'b1;
    do @(cfg.vif.cb); while (!cfg.vif.cb.bvalid);
    t.resp = cfg.vif.cb.bresp;
    cfg.vif.bready <= 1'b0;
  endtask

  task automatic read(axil_item t);
    wait_cycles(t.ar_delay);
    cfg.vif.araddr  <= t.addr;
    cfg.vif.arvalid <= 1'b1;
    do @(cfg.vif.cb); while (!cfg.vif.cb.arready);
    cfg.vif.arvalid <= 1'b0;
    wait_cycles(t.r_delay);
    cfg.vif.rready <= 1'b1;
    do @(cfg.vif.cb); while (!cfg.vif.cb.rvalid);
    t.data = cfg.vif.cb.rdata;
    t.resp = cfg.vif.cb.rresp;
    cfg.vif.rready <= 1'b0;
  endtask

endclass
