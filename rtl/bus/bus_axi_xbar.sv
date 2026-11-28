// Data bus crossbar: the AXI4 128-bit interconnect between the masters (the core's OBI -> AXI4
// bridge and the DMA) and the two L2 banks. It is the vendor/axi axi_xbar with the configuration
// and address map of soc_pkg:
//
//   - A transaction goes to the bank its first address falls in (L2 address bit 15). AR and AW are
//     routed independently, so the DMA reads A and B from bank 0 while it writes C to bank 1.
//   - An address outside the L2 gets DECERR from the crossbar's internal error slave. Only the DMA
//     can produce one: the core's demux sends nothing but L2 addresses here.
//   - Towards a bank the crossbar prepends the master index to the ID (AXI_ID_MST_W ->
//     AXI_ID_SLV_W bits), and strips it from the B and R it returns.
//   - Two masters on the same bank are served round robin, per channel.
//   - No atomic operations: neither master issues them, and leaving them out saves their filters.
module bus_axi_xbar
  import soc_pkg::*;
(
  input  logic                            clk_i,
  input  logic                            rst_ni,

  // From the masters, indexed by DATA_MST_*
  input  axi_mst_req_t [DATA_NUM_MST-1:0] mst_req_i,
  output axi_mst_rsp_t [DATA_NUM_MST-1:0] mst_rsp_o,

  // To the L2 banks, indexed by DATA_SLV_*
  output axi_slv_req_t [DATA_NUM_SLV-1:0] slv_req_o,
  input  axi_slv_rsp_t [DATA_NUM_SLV-1:0] slv_rsp_i
);

  // The vendor names the ports after the crossbar side: its slave ports face the masters.
  axi_xbar #(
    .Cfg          (DATA_XBAR_CFG    ),
    .ATOPs        (1'b0             ),
    .slv_aw_chan_t(axi_mst_aw_chan_t),
    .mst_aw_chan_t(axi_slv_aw_chan_t),
    .w_chan_t     (axi_mst_w_chan_t ),
    .slv_b_chan_t (axi_mst_b_chan_t ),
    .mst_b_chan_t (axi_slv_b_chan_t ),
    .slv_ar_chan_t(axi_mst_ar_chan_t),
    .mst_ar_chan_t(axi_slv_ar_chan_t),
    .slv_r_chan_t (axi_mst_r_chan_t ),
    .mst_r_chan_t (axi_slv_r_chan_t ),
    .slv_req_t    (axi_mst_req_t    ),
    .slv_resp_t   (axi_mst_rsp_t    ),
    .mst_req_t    (axi_slv_req_t    ),
    .mst_resp_t   (axi_slv_rsp_t    ),
    .rule_t       (rule_t           )
  ) u_xbar (
    .clk_i                (clk_i        ),
    .rst_ni               (rst_ni       ),
    .test_i               (1'b0         ),
    .slv_ports_req_i      (mst_req_i    ),
    .slv_ports_resp_o     (mst_rsp_o    ),
    .mst_ports_req_o      (slv_req_o    ),
    .mst_ports_resp_i     (slv_rsp_i    ),
    .addr_map_i           (DATA_ADDR_MAP),
    .en_default_mst_port_i('0           ),
    .default_mst_port_i   ('0           )
  );

endmodule
