// AXI4-Stream agent: master (drives TVALID / TDATA from sequences) or slave (drives TREADY with
// random back-pressure). Reused by the coprocessor and the DMA environments; passive in the SoC.
package axis_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Widest stream in the SoC is 128 bits (C); the interface leaves room for wider ones.
  parameter int unsigned AXIS_MAX_DW = 256;

  `include "axis_item.svh"
  `include "axis_agent_cfg.svh"
  `include "axis_master_driver.svh"
  `include "axis_slave_driver.svh"
  `include "axis_monitor.svh"
  `include "axis_agent.svh"
  `include "axis_seq_lib.svh"

endpackage
