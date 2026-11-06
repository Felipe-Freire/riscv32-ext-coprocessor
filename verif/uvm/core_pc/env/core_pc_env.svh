class core_pc_env extends uvm_env;

  core_pc_env_cfg    cfg;
  core_pc_agent      agent;
  core_pc_scoreboard scb;
  core_pc_coverage   cov;

  `uvm_component_utils(core_pc_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(core_pc_env_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("CFG", "core_pc_env_cfg not found in config_db")
    end
    uvm_config_db #(core_pc_agent_cfg)::set(this, "agent", "cfg", cfg.agent_cfg);

    agent   = core_pc_agent::type_id::create("agent", this);
    scb     = core_pc_scoreboard::type_id::create("scb", this);
    scb.cfg = cfg;
    if (cfg.has_coverage) begin
      cov = core_pc_coverage::type_id::create("cov", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    agent.mon.ap.connect(scb.analysis_export);
    if (cfg.has_coverage) begin
      agent.mon.ap.connect(cov.analysis_export);
    end
  endfunction

endclass
