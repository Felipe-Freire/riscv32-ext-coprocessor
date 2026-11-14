// AXI4-Lite master agent with its register-layer adapter. Reused by every block with an
// AXI4-Lite register port (coprocessor, DMA, timer); passive in the SoC environment.
package axil_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "axil_item.svh"
  `include "axil_agent_cfg.svh"
  `include "axil_driver.svh"
  `include "axil_monitor.svh"
  `include "axil_agent.svh"
  `include "axil_seq_lib.svh"
  `include "axil_reg_adapter.svh"

endpackage
