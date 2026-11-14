package coproc_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axil_agent_pkg::*;
  import axis_agent_pkg::*;
  import coproc_env_pkg::*;
  import coproc_seq_pkg::*;

  `include "coproc_base_test.svh"
  `include "coproc_regs_test.svh"
  `include "coproc_matmul_directed_test.svh"
  `include "coproc_matmul_rand_test.svh"
  `include "coproc_cdc_test.svh"
  `include "coproc_reset_test.svh"

endpackage
