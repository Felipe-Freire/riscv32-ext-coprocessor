// Environment of coproc_top (verification plan, figure "Ambiente do coproc_top"): AXI4-Lite
// master with the register model, A and B stream masters, C stream slave with random TREADY, the
// scoreboard on the golden model and the coverage collector.

class coproc_env extends uvm_env;

  coproc_env_cfg    cfg;
  axil_agent        axil_agt;
  axis_agent        a_agt;
  axis_agent        b_agt;
  axis_agent        c_agt;
  coproc_reg_block  regmodel;
  axil_reg_adapter  adapter;
  coproc_scoreboard scb;
  coproc_coverage   cov;
  coproc_vseqr      vseqr;

  `uvm_component_utils(coproc_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(coproc_env_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("CFG", "coproc_env_cfg not found in config_db")
    end
    uvm_config_db #(axil_agent_cfg)::set(this, "axil_agt", "cfg", cfg.axil_cfg);
    uvm_config_db #(axis_agent_cfg)::set(this, "a_agt", "cfg", cfg.a_cfg);
    uvm_config_db #(axis_agent_cfg)::set(this, "b_agt", "cfg", cfg.b_cfg);
    uvm_config_db #(axis_agent_cfg)::set(this, "c_agt", "cfg", cfg.c_cfg);

    axil_agt = axil_agent::type_id::create("axil_agt", this);
    a_agt    = axis_agent::type_id::create("a_agt", this);
    b_agt    = axis_agent::type_id::create("b_agt", this);
    c_agt    = axis_agent::type_id::create("c_agt", this);

    regmodel = coproc_reg_block::type_id::create("regmodel");
    regmodel.build();
    regmodel.lock_model();
    adapter = axil_reg_adapter::type_id::create("adapter");

    scb     = coproc_scoreboard::type_id::create("scb", this);
    scb.cfg = cfg;
    if (cfg.has_coverage) begin
      cov = coproc_coverage::type_id::create("cov", this);
    end
    vseqr = coproc_vseqr::type_id::create("vseqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    regmodel.default_map.set_sequencer(axil_agt.sqr, adapter);
    regmodel.default_map.set_auto_predict(1);

    axil_agt.mon.ap.connect(scb.reg_export);
    a_agt.mon.ap.connect(scb.a_export);
    b_agt.mon.ap.connect(scb.b_export);
    c_agt.mon.ap.connect(scb.c_export);
    if (cfg.has_coverage) begin
      scb.job_ap.connect(cov.analysis_export);
    end

    vseqr.cfg      = cfg;
    vseqr.axil_sqr = axil_agt.sqr;
    vseqr.a_sqr    = a_agt.sqr;
    vseqr.b_sqr    = b_agt.sqr;
    vseqr.regmodel = regmodel;
    vseqr.scb      = scb;
  endfunction

endclass
