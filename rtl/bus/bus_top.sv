// Interconnect top: every bus between the core data port, the DMA, the memories and the peripheral
// registers. Memories and peripherals stay outside; their ports are indexed by soc_pkg.
//
//   core data port (OBI) -> bus_obi_demux -+-> D-TCM (OBI)
//                                          +-> bus_obi2axi -------> bus_axi_xbar -> L2 banks (AXI4)
//                                          |   DMA (AXI4) ------->  (2 x 2)
//                                          +-> axi_lite_from_mem -> axi_lite_xbar -> peripherals
//                                              (AXI4-Lite)          (1 x 3)          (AXI4-Lite)
//
// An address the core sends outside the D-TCM, the L2 and the control window gets err from the
// demux; one in the control window that no peripheral decodes gets DECERR from the control
// crossbar, and so does one of the DMA outside the L2 from the data crossbar.
module bus_top
  import soc_pkg::*;
(
  input  logic                            clk_i,
  input  logic                            rst_ni,

  // Core data port
  input  obi_req_t                        core_req_i,
  output obi_rsp_t                        core_rsp_o,

  // D-TCM
  output obi_req_t                        dtcm_req_o,
  input  obi_rsp_t                        dtcm_rsp_i,

  // DMA master port
  input  axi_mst_req_t                    dma_req_i,
  output axi_mst_rsp_t                    dma_rsp_o,

  // L2 banks, indexed by DATA_SLV_*
  output axi_slv_req_t [DATA_NUM_SLV-1:0] l2_req_o,
  input  axi_slv_rsp_t [DATA_NUM_SLV-1:0] l2_rsp_i,

  // Peripheral registers, indexed by CTRL_SLV_*
  output axil_req_t    [CTRL_NUM_SLV-1:0] periph_req_o,
  input  axil_rsp_t    [CTRL_NUM_SLV-1:0] periph_rsp_i
);

  obi_req_t     [CORE_NUM_TGT-1:0] tgt_req;
  obi_rsp_t     [CORE_NUM_TGT-1:0] tgt_rsp;
  axi_mst_req_t [DATA_NUM_MST-1:0] data_req;
  axi_mst_rsp_t [DATA_NUM_MST-1:0] data_rsp;
  axil_req_t    [0:0]              ctrl_req;
  axil_rsp_t    [0:0]              ctrl_rsp;

  // ---- Core data port -----------------------------------------------------------------------------

  bus_obi_demux u_demux (
    .clk_i    (clk_i     ),
    .rst_ni   (rst_ni    ),
    .obi_req_i(core_req_i),
    .obi_rsp_o(core_rsp_o),
    .tgt_req_o(tgt_req   ),
    .tgt_rsp_i(tgt_rsp   )
  );

  assign dtcm_req_o             = tgt_req[CORE_TGT_DTCM];
  assign tgt_rsp[CORE_TGT_DTCM] = dtcm_rsp_i;

  // ---- Data bus: the core bridge and the DMA to the L2 banks ---------------------------------------

  bus_obi2axi u_obi2axi (
    .clk_i    (clk_i                  ),
    .rst_ni   (rst_ni                 ),
    .obi_req_i(tgt_req[CORE_TGT_DATA] ),
    .obi_rsp_o(tgt_rsp[CORE_TGT_DATA] ),
    .axi_req_o(data_req[DATA_MST_CORE]),
    .axi_rsp_i(data_rsp[DATA_MST_CORE])
  );

  assign data_req[DATA_MST_DMA] = dma_req_i;
  assign dma_rsp_o              = data_rsp[DATA_MST_DMA];

  bus_axi_xbar u_data_xbar (
    .clk_i    (clk_i   ),
    .rst_ni   (rst_ni  ),
    .mst_req_i(data_req),
    .mst_rsp_o(data_rsp),
    .slv_req_o(l2_req_o),
    .slv_rsp_i(l2_rsp_i)
  );

  // ---- Control bus: the core to the peripheral registers -------------------------------------------

  // The 32-bit word goes as the core sends it: the peripherals decode the register from addr[11:2]
  // and take the byte enables as strobes. Room for two requests, for the same reason as the data
  // bridge: the next access is granted in the cycle the previous one answers.
  logic       ctrl_gnt, ctrl_rvalid, ctrl_err;
  axil_data_t ctrl_rdata;

  axi_lite_from_mem #(
    .MemAddrWidth(32         ),
    .AxiAddrWidth(AXIL_ADDR_W),
    .DataWidth   (AXIL_DATA_W),
    .MaxRequests (2          ),
    .AxiProt     (3'b000     ),
    .axi_req_t   (axil_req_t ),
    .axi_rsp_t   (axil_rsp_t )
  ) u_obi2axil (
    .clk_i          (clk_i                       ),
    .rst_ni         (rst_ni                      ),
    .mem_req_i      (tgt_req[CORE_TGT_CTRL].req  ),
    .mem_addr_i     (tgt_req[CORE_TGT_CTRL].addr ),
    .mem_we_i       (tgt_req[CORE_TGT_CTRL].we   ),
    .mem_wdata_i    (tgt_req[CORE_TGT_CTRL].wdata),
    .mem_be_i       (tgt_req[CORE_TGT_CTRL].be   ),
    .mem_gnt_o      (ctrl_gnt                    ),
    .mem_rsp_valid_o(ctrl_rvalid                 ),
    .mem_rsp_rdata_o(ctrl_rdata                  ),
    .mem_rsp_error_o(ctrl_err                    ),
    .axi_req_o      (ctrl_req[0]                 ),
    .axi_rsp_i      (ctrl_rsp[0]                 )
  );

  assign tgt_rsp[CORE_TGT_CTRL] = '{gnt: ctrl_gnt, rvalid: ctrl_rvalid, rdata: ctrl_rdata,
                                    err: ctrl_err};

  axi_lite_xbar #(
    .Cfg       (CTRL_XBAR_CFG ),
    .aw_chan_t (axil_aw_chan_t),
    .w_chan_t  (axil_w_chan_t ),
    .b_chan_t  (axil_b_chan_t ),
    .ar_chan_t (axil_ar_chan_t),
    .r_chan_t  (axil_r_chan_t ),
    .axi_req_t (axil_req_t    ),
    .axi_resp_t(axil_rsp_t    ),
    .rule_t    (rule_t        )
  ) u_ctrl_xbar (
    .clk_i                (clk_i        ),
    .rst_ni               (rst_ni       ),
    .test_i               (1'b0         ),
    .slv_ports_req_i      (ctrl_req     ),
    .slv_ports_resp_o     (ctrl_rsp     ),
    .mst_ports_req_o      (periph_req_o ),
    .mst_ports_resp_i     (periph_rsp_i ),
    .addr_map_i           (CTRL_ADDR_MAP),
    .en_default_mst_port_i('0           ),
    .default_mst_port_i   ('0           )
  );

endmodule
