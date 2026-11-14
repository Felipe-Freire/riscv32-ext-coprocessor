// Builds the environment, starts the clocks, resets the block and runs main(), which the tests
// override. Plusargs: +JOBS=<n> sets the number of random jobs where a test uses it. A test that
// has not ended after 100 ms of simulated time fails (+UVM_TIMEOUT overrides it).

class coproc_base_test extends uvm_test;

  coproc_env_cfg       cfg;
  coproc_env           env;
  virtual coproc_tb_if tb_vif;

  `uvm_component_utils(coproc_base_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(100ms, 1);
    cfg          = coproc_env_cfg::type_id::create("cfg");
    cfg.axil_cfg = axil_agent_cfg::type_id::create("axil_cfg");
    cfg.a_cfg    = axis_agent_cfg::type_id::create("a_cfg");
    cfg.b_cfg    = axis_agent_cfg::type_id::create("b_cfg");
    cfg.c_cfg    = axis_agent_cfg::type_id::create("c_cfg");

    cfg.a_cfg.mode       = AxisMaster;
    cfg.a_cfg.data_width = coproc_pkg::ARRAY_DIM * coproc_pkg::DATA_W;
    cfg.b_cfg.mode       = AxisMaster;
    cfg.b_cfg.data_width = coproc_pkg::ARRAY_DIM * coproc_pkg::DATA_W;
    cfg.c_cfg.mode       = AxisSlave;
    cfg.c_cfg.data_width = 128;

    if (!uvm_config_db #(virtual coproc_tb_if)::get(this, "", "tb_vif", tb_vif) ||
        !uvm_config_db #(virtual axil_if)::get(this, "", "axil_vif", cfg.axil_cfg.vif) ||
        !uvm_config_db #(virtual axis_if)::get(this, "", "a_vif", cfg.a_cfg.vif) ||
        !uvm_config_db #(virtual axis_if)::get(this, "", "b_vif", cfg.b_cfg.vif) ||
        !uvm_config_db #(virtual axis_if)::get(this, "", "c_vif", cfg.c_cfg.vif)) begin
      `uvm_fatal("CFG", "A virtual interface is missing from config_db")
    end
    cfg.tb_vif = tb_vif;

    configure();
    uvm_config_db #(coproc_env_cfg)::set(this, "env", "cfg", cfg);
    env = coproc_env::type_id::create("env", this);
  endfunction

  // Tests adjust cfg and the clocks here, before anything is built from them.
  virtual function void configure();
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    `uvm_info("TEST", $sformatf("clk_i %0.2f ns, clk_acc_i %0.2f ns, phase %0.2f ns",
                                tb_vif.sys_period, tb_vif.acc_period, tb_vif.acc_phase), UVM_LOW)
    tb_vif.clocks_on = 1'b1;
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    tb_vif.reset(10);
    main();
    repeat (20) @(posedge tb_vif.clk_sys);
    phase.drop_objection(this);
  endtask

  virtual task main();
  endtask

  function int unsigned plusarg_jobs(int unsigned dflt);
    int unsigned n;
    return $value$plusargs("JOBS=%d", n) ? n : dflt;
  endfunction

  function void report_phase(uvm_phase phase);
    uvm_report_server srv = uvm_report_server::get_server();
    if (srv.get_severity_count(UVM_ERROR) + srv.get_severity_count(UVM_FATAL) == 0) begin
      `uvm_info("TEST", "TEST PASSED", UVM_NONE)
    end else begin
      `uvm_info("TEST", "TEST FAILED", UVM_NONE)
    end
  endfunction

endclass
