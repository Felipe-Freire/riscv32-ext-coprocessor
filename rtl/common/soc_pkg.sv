// SoC package: the memory map of rtl/top/README.md, the address rules and configurations of the
// crossbars, and the request/response types of the buses (AXI4 data bus, AXI4-Lite control bus,
// OBI data port of the core). The AXI types come from the macros of vendor/axi (axi/typedef.svh),
// so they have the field layout the PULP crossbars and dma_top expect.
//
// Naming: on the data bus, "mst" and "slv" name the device on that side of the crossbar, not the
// crossbar port. The masters (core bridge, DMA) use axi_mst_* with AXI_ID_MST_W ID bits; the slaves
// (L2 banks) use axi_slv_*, whose IDs are wider because the crossbar prepends the master index.
`include "axi/typedef.svh"

package soc_pkg;

  // ---- Memory map (rtl/top/README.md#memory-map) -------------------------------------------------

  parameter logic [31:0] BOOT_ROM_BASE = 32'h0000_0000;
  parameter logic [31:0] BOOT_ROM_SIZE = 32'h0000_1000;  // 4 KiB
  parameter logic [31:0] ITCM_BASE     = 32'h1000_0000;
  parameter logic [31:0] ITCM_SIZE     = 32'h0000_8000;  // 32 KiB
  parameter logic [31:0] DTCM_BASE     = 32'h1001_0000;
  parameter logic [31:0] DTCM_SIZE     = 32'h0000_8000;  // 32 KiB
  parameter logic [31:0] L2_BASE       = 32'h2000_0000;
  parameter logic [31:0] L2_SIZE       = 32'h0001_0000;  // 64 KiB
  parameter int unsigned L2_NUM_BANKS  = 2;
  parameter logic [31:0] L2_BANK_SIZE  = L2_SIZE / L2_NUM_BANKS;  // 32 KiB: address bit 15 picks the bank
  parameter logic [31:0] TIMER_BASE    = 32'h4000_0000;
  parameter logic [31:0] DMA_BASE      = 32'h4000_1000;
  parameter logic [31:0] COPROC_BASE   = 32'h4000_2000;
  parameter logic [31:0] PERIPH_SIZE   = 32'h0000_1000;  // 4 KiB register window per peripheral

  // Control bus window of the core data port. It holds every peripheral, so adding one changes only
  // CTRL_ADDR_MAP; an address in the window that no peripheral decodes gets DECERR.
  parameter logic [31:0] CTRL_BASE     = 32'h4000_0000;
  parameter logic [31:0] CTRL_SIZE     = 32'h1000_0000;  // 256 MiB

  // ---- Bus widths ---------------------------------------------------------------------------------

  parameter int unsigned AXI_ADDR_W   = 32;
  parameter int unsigned AXI_DATA_W   = 128;
  parameter int unsigned AXI_USER_W   = 1;   // unused, tied to 0
  parameter int unsigned AXIL_ADDR_W  = 32;
  parameter int unsigned AXIL_DATA_W  = 32;

  // ---- Data bus: AXI4 crossbar, masters (core bridge, DMA) x slaves (L2 banks) ------------------

  parameter int unsigned DATA_NUM_MST      = 2;
  parameter int unsigned DATA_MST_CORE     = 0;
  parameter int unsigned DATA_MST_DMA      = 1;
  parameter int unsigned DATA_NUM_SLV      = L2_NUM_BANKS;
  parameter int unsigned DATA_SLV_L2_BANK0 = 0;
  parameter int unsigned DATA_SLV_L2_BANK1 = 1;

  // ID width at the masters: the DMA uses two bits (dma_pkg::AXI_ID_W, one ID per read channel).
  parameter int unsigned AXI_ID_MST_W = 2;
  // ID width at the slaves: the crossbar prepends the index of the master the transaction came from.
  parameter int unsigned AXI_ID_SLV_W = AXI_ID_MST_W + $clog2(DATA_NUM_MST);

  // ---- Control bus: AXI4-Lite crossbar, the core bridge x the peripherals' registers -----------

  parameter int unsigned CTRL_NUM_SLV    = 3;
  parameter int unsigned CTRL_SLV_TIMER  = 0;
  parameter int unsigned CTRL_SLV_DMA    = 1;
  parameter int unsigned CTRL_SLV_COPROC = 2;

  // ---- Core data port: the targets of the OBI demux --------------------------------------------
  // An address outside these three windows (Boot ROM and I-TCM included: the core cannot load from
  // them) gets an error response from the demux itself.

  parameter int unsigned CORE_NUM_TGT  = 3;
  parameter int unsigned CORE_TGT_DTCM = 0;  // D-TCM, OBI
  parameter int unsigned CORE_TGT_DATA = 1;  // L2 through the OBI -> AXI4 bridge
  parameter int unsigned CORE_TGT_CTRL = 2;  // peripherals through the OBI -> AXI4-Lite bridge

  // ---- Types --------------------------------------------------------------------------------------

  typedef logic [AXI_ADDR_W-1:0]   axi_addr_t;
  typedef logic [AXI_DATA_W-1:0]   axi_data_t;
  typedef logic [AXI_DATA_W/8-1:0] axi_strb_t;
  typedef logic [AXI_USER_W-1:0]   axi_user_t;
  typedef logic [AXI_ID_MST_W-1:0] axi_id_mst_t;
  typedef logic [AXI_ID_SLV_W-1:0] axi_id_slv_t;

  // axi_mst_{aw,w,b,ar,r}_chan_t, axi_mst_req_t, axi_mst_rsp_t: core bridge and DMA.
  `AXI_TYPEDEF_ALL_CT(axi_mst, axi_mst_req_t, axi_mst_rsp_t, axi_addr_t, axi_id_mst_t, axi_data_t,
                      axi_strb_t, axi_user_t)
  // axi_slv_{aw,w,b,ar,r}_chan_t, axi_slv_req_t, axi_slv_rsp_t: L2 banks.
  `AXI_TYPEDEF_ALL_CT(axi_slv, axi_slv_req_t, axi_slv_rsp_t, axi_addr_t, axi_id_slv_t, axi_data_t,
                      axi_strb_t, axi_user_t)

  typedef logic [AXIL_ADDR_W-1:0]   axil_addr_t;
  typedef logic [AXIL_DATA_W-1:0]   axil_data_t;
  typedef logic [AXIL_DATA_W/8-1:0] axil_strb_t;

  // axil_{aw,w,b,ar,r}_chan_t, axil_req_t, axil_rsp_t: control bus, every peripheral.
  `AXI_LITE_TYPEDEF_ALL_CT(axil, axil_req_t, axil_rsp_t, axil_addr_t, axil_data_t, axil_strb_t)

  // Core data port (rtl/core/README.md#ports). The request fields are valid with req and held until
  // gnt; the response (rvalid, with rdata for a load and err for an access fault) comes in a later
  // cycle, one per granted request.
  typedef struct packed {
    logic        req;
    logic [31:0] addr;
    logic        we;
    logic [3:0]  be;
    logic [31:0] wdata;
  } obi_req_t;

  typedef struct packed {
    logic        gnt;
    logic        rvalid;
    logic [31:0] rdata;
    logic        err;
  } obi_rsp_t;

  // ---- Address rules -------------------------------------------------------------------------------
  // end_addr is exclusive. Every boundary is 4 KiB aligned: the crossbars route a burst by its first
  // address, and an AXI4 burst never crosses 4 KiB, so a burst always stays inside one rule.

  typedef axi_pkg::xbar_rule_32_t rule_t;

  // Data bus: one bank each. Only the DMA can address outside the L2, and it gets DECERR.
  parameter rule_t [DATA_NUM_SLV-1:0] DATA_ADDR_MAP = '{
    '{idx: DATA_SLV_L2_BANK1, start_addr: L2_BASE + L2_BANK_SIZE, end_addr: L2_BASE + L2_SIZE},
    '{idx: DATA_SLV_L2_BANK0, start_addr: L2_BASE,                end_addr: L2_BASE + L2_BANK_SIZE}
  };

  // Control bus: one register window per peripheral.
  parameter rule_t [CTRL_NUM_SLV-1:0] CTRL_ADDR_MAP = '{
    '{idx: CTRL_SLV_COPROC, start_addr: COPROC_BASE, end_addr: COPROC_BASE + PERIPH_SIZE},
    '{idx: CTRL_SLV_DMA,    start_addr: DMA_BASE,    end_addr: DMA_BASE + PERIPH_SIZE},
    '{idx: CTRL_SLV_TIMER,  start_addr: TIMER_BASE,  end_addr: TIMER_BASE + PERIPH_SIZE}
  };

  // Core data port demux.
  parameter rule_t [CORE_NUM_TGT-1:0] CORE_ADDR_MAP = '{
    '{idx: CORE_TGT_CTRL, start_addr: CTRL_BASE, end_addr: CTRL_BASE + CTRL_SIZE},
    '{idx: CORE_TGT_DATA, start_addr: L2_BASE,   end_addr: L2_BASE + L2_SIZE},
    '{idx: CORE_TGT_DTCM, start_addr: DTCM_BASE, end_addr: DTCM_BASE + DTCM_SIZE}
  };

  // ---- Crossbar configurations (vendor/axi/doc/axi_xbar.md) ----------------------------------------

  // Spill registers on AW and AR on both sides of the data crossbar. To be revisited with synthesis.
  parameter axi_pkg::xbar_latency_e DATA_XBAR_LATENCY = axi_pkg::CUT_ALL_AX;

  // Spill registers on every channel at the core side of the control crossbar, so the grant the core
  // waits for never depends combinationally on a peripheral. A register access is not latency
  // critical.
  parameter axi_pkg::xbar_latency_e CTRL_XBAR_LATENCY = axi_pkg::CUT_SLV_PORTS;

  // Open transactions: the DMA has at most one burst per read channel (2) plus one write in flight
  // and the core at most one access, so 4 per master and 4 per L2 bank never stall the crossbar.
  parameter axi_pkg::xbar_cfg_t DATA_XBAR_CFG = '{
    NoSlvPorts:         DATA_NUM_MST,
    NoMstPorts:         DATA_NUM_SLV,
    MaxMstTrans:        4,
    MaxSlvTrans:        4,
    FallThrough:        1'b0,
    LatencyMode:        DATA_XBAR_LATENCY,
    PipelineStages:     0,
    AxiIdWidthSlvPorts: AXI_ID_MST_W,
    AxiIdUsedSlvPorts:  AXI_ID_MST_W,
    UniqueIds:          1'b0,
    AxiAddrWidth:       AXI_ADDR_W,
    AxiDataWidth:       AXI_DATA_W,
    NoAddrRules:        DATA_NUM_SLV
  };

  // The ID fields are not used by AXI4-Lite.
  parameter axi_pkg::xbar_cfg_t CTRL_XBAR_CFG = '{
    NoSlvPorts:         1,
    NoMstPorts:         CTRL_NUM_SLV,
    MaxMstTrans:        2,
    MaxSlvTrans:        2,
    FallThrough:        1'b0,
    LatencyMode:        CTRL_XBAR_LATENCY,
    PipelineStages:     0,
    AxiIdWidthSlvPorts: 0,
    AxiIdUsedSlvPorts:  0,
    UniqueIds:          1'b0,
    AxiAddrWidth:       AXIL_ADDR_W,
    AxiDataWidth:       AXIL_DATA_W,
    NoAddrRules:        CTRL_NUM_SLV
  };

endpackage
