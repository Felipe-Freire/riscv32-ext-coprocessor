class coproc_env_cfg extends uvm_object;

  axil_agent_cfg       axil_cfg;
  axis_agent_cfg       a_cfg;   // A stream, master
  axis_agent_cfg       b_cfg;   // B stream, master
  axis_agent_cfg       c_cfg;   // C stream, slave
  virtual coproc_tb_if tb_vif;  // clocks and reset

  bit          has_coverage = 1'b1;
  // The scoreboard fails the test if fewer jobs than this have been checked.
  int unsigned min_jobs = 1;

  `uvm_object_utils(coproc_env_cfg)

  function new(string name = "coproc_env_cfg");
    super.new(name);
  endfunction

endclass
