// Rebuilds AXI4-Lite transactions from the handshakes and publishes each one when it completes:
// a write on its B handshake, a read on its R handshake. AW and W are paired in order, so the
// monitor also works with a slave that takes them in different cycles. Nothing is published on
// the clock edge where a reset is asserted.

class axil_monitor extends uvm_monitor;

  axil_agent_cfg                 cfg;
  uvm_analysis_port #(axil_item) ap;

  `uvm_component_utils(axil_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    bit [31:0] aw_q[$], ar_q[$];
    bit [35:0] w_q[$];
    axil_item  t;
    forever begin
      @(cfg.vif.cb);
      if (cfg.vif.cb.rst_ni !== 1'b1 || cfg.vif.rst_ni !== 1'b1) begin
        aw_q.delete();
        w_q.delete();
        ar_q.delete();
        continue;
      end
      if (cfg.vif.cb.awvalid && cfg.vif.cb.awready) aw_q.push_back(cfg.vif.cb.awaddr);
      if (cfg.vif.cb.wvalid && cfg.vif.cb.wready) begin
        w_q.push_back({cfg.vif.cb.wstrb, cfg.vif.cb.wdata});
      end
      if (cfg.vif.cb.arvalid && cfg.vif.cb.arready) ar_q.push_back(cfg.vif.cb.araddr);

      if (cfg.vif.cb.bvalid && cfg.vif.cb.bready) begin
        if (aw_q.size() == 0 || w_q.size() == 0) begin
          `uvm_error("AXIL_MON", "B handshake without a preceding AW and W")
        end else begin
          t      = axil_item::type_id::create("t");
          t.kind = AxilWrite;
          t.addr = aw_q.pop_front();
          {t.strb, t.data} = w_q.pop_front();
          t.resp = cfg.vif.cb.bresp;
          `uvm_info("AXIL_MON", t.convert2string(), UVM_HIGH)
          ap.write(t);
        end
      end

      if (cfg.vif.cb.rvalid && cfg.vif.cb.rready) begin
        if (ar_q.size() == 0) begin
          `uvm_error("AXIL_MON", "R handshake without a preceding AR")
        end else begin
          t      = axil_item::type_id::create("t");
          t.kind = AxilRead;
          t.addr = ar_q.pop_front();
          t.data = cfg.vif.cb.rdata;
          t.resp = cfg.vif.cb.rresp;
          `uvm_info("AXIL_MON", t.convert2string(), UVM_HIGH)
          ap.write(t);
        end
      end
    end
  endtask

endclass
