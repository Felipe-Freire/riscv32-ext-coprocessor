package coproc_seq_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axil_agent_pkg::*;
  import axis_agent_pkg::*;
  import coproc_env_pkg::*;

  `include "coproc_job.svh"
  `include "coproc_base_vseq.svh"
  `include "coproc_job_vseq.svh"
  `include "coproc_regs_vseq.svh"

endpackage
