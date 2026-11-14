package coproc_env_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axil_agent_pkg::*;
  import axis_agent_pkg::*;
  import coproc_model_pkg::*;

  `include "coproc_env_cfg.svh"
  `include "coproc_reg_block.svh"
  `include "coproc_job_info.svh"
  `include "coproc_scoreboard.svh"
  `include "coproc_coverage.svh"
  `include "coproc_vseqr.svh"
  `include "coproc_env.svh"

endpackage
