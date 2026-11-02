// Builds the environment and prints the verdict. Derived tests start their sequences in run_phase.

class core_pc_base_test extends uvm_test;

  core_pc_env_cfg cfg;
  core_pc_env     env;

  `uvm_component_utils(core_pc_base_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg           = core_pc_env_cfg::type_id::create("cfg");
    cfg.agent_cfg = core_pc_agent_cfg::type_id::create("agent_cfg");
    if (!uvm_config_db #(virtual core_pc_if)::get(this, "", "vif", cfg.agent_cfg.vif)) begin
      `uvm_fatal("CFG", "Virtual interface not found in config_db")
    end
    if (!uvm_config_db #(logic [31:0])::get(this, "", "boot_addr", cfg.boot_addr)) begin
      `uvm_fatal("CFG", "boot_addr not found in config_db")
    end
    uvm_config_db #(core_pc_env_cfg)::set(this, "env", "cfg", cfg);
    env = core_pc_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    // Let the monitor sample the cycle of the last item before the test ends
    phase.phase_done.set_drain_time(this, 20ns);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server srv = uvm_report_server::get_server();
    if (srv.get_severity_count(UVM_ERROR) + srv.get_severity_count(UVM_FATAL) == 0) begin
      `uvm_info("TEST", "TEST PASSED", UVM_NONE)
    end else begin
      `uvm_info("TEST", "TEST FAILED", UVM_NONE)
    end
  endfunction

endclass
