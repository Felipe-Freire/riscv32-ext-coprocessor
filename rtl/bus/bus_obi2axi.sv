// OBI -> AXI4 bridge of the core data port: one OBI access becomes one single-beat AXI4 transaction
// on the 128-bit data bus. The protocol conversion is vendor/axi axi_from_mem (req/gnt/rvalid to
// AW/W/B and AR/R, one response per granted request, in order, SLVERR and DECERR as err); this
// module only moves the 32-bit word to its lane of the 16-byte beat and back:
//
//   - AW/AR address: the access address with bits 3:0 cleared. Every transaction is one full-width
//     beat (16 bytes, len 0) with ID 0, cache and prot 0, like the ones of the DMA.
//   - W: the store word on all four lanes and the byte enables shifted to lane addr[3:2]. The core
//     already puts a byte or halfword on its bytes of the word and sets be from addr[1:0]
//     (rv32_store_align), so the strobe selects exactly the bytes of the access.
//   - R: the lane of the access, the whole word holding it, as the core expects (rv32_load_align
//     extracts the byte or halfword).
//
// The core has at most one access outstanding, but it can raise the next request in the cycle the
// response of the previous one arrives. With room for two requests the bridge grants it in that
// cycle; with one it would hold the grant a cycle. The lane of each granted request waits in a FIFO
// that moves with the response FIFO inside axi_from_mem (same depth, push on gnt, pop on rvalid).
module bus_obi2axi
  import soc_pkg::*;
(
  input  logic         clk_i,
  input  logic         rst_ni,

  // From the core data port (through the demux)
  input  obi_req_t     obi_req_i,
  output obi_rsp_t     obi_rsp_o,

  // To the data crossbar
  output axi_mst_req_t axi_req_o,
  input  axi_mst_rsp_t axi_rsp_i
);

  localparam int unsigned MaxRequests = 2;
  localparam int unsigned NumLanes    = AXI_DATA_W / 32;
  localparam int unsigned LaneW       = $clog2(NumLanes);
  localparam int unsigned BeatOffW    = $clog2(AXI_DATA_W / 8);  // byte offset in a beat

  typedef logic [LaneW-1:0] lane_t;

  lane_t     req_lane, rsp_lane;
  axi_addr_t beat_addr;
  axi_data_t beat_wdata, beat_rdata;
  axi_strb_t beat_strb;
  logic      gnt, rsp_valid, rsp_err;

  assign req_lane   = obi_req_i.addr[BeatOffW-1:2];
  assign beat_addr  = {obi_req_i.addr[AXI_ADDR_W-1:BeatOffW], BeatOffW'(0)};
  assign beat_wdata = {NumLanes{obi_req_i.wdata}};
  assign beat_strb  = axi_strb_t'(obi_req_i.be) << {req_lane, 2'b00};

  axi_from_mem #(
    .MemAddrWidth(AXI_ADDR_W   ),
    .AxiAddrWidth(AXI_ADDR_W   ),
    .DataWidth   (AXI_DATA_W   ),
    .MaxRequests (MaxRequests  ),
    .AxiProt     (3'b000       ),
    .axi_req_t   (axi_mst_req_t),
    .axi_rsp_t   (axi_mst_rsp_t)
  ) u_axi_from_mem (
    .clk_i          (clk_i         ),
    .rst_ni         (rst_ni        ),
    .mem_req_i      (obi_req_i.req ),
    .mem_addr_i     (beat_addr     ),
    .mem_we_i       (obi_req_i.we  ),
    .mem_wdata_i    (beat_wdata    ),
    .mem_be_i       (beat_strb     ),
    .mem_gnt_o      (gnt           ),
    .mem_rsp_valid_o(rsp_valid     ),
    .mem_rsp_rdata_o(beat_rdata    ),
    .mem_rsp_error_o(rsp_err       ),
    .slv_aw_cache_i (4'b0000       ),
    .slv_ar_cache_i (4'b0000       ),
    .axi_req_o      (axi_req_o     ),
    .axi_rsp_i      (axi_rsp_i     )
  );

  // Never overflows: axi_from_mem holds gnt while its own FIFO of the same depth is full.
  fifo_v3 #(
    .FALL_THROUGH(1'b0       ),
    .DEPTH       (MaxRequests),
    .dtype       (lane_t     )
  ) u_lane_fifo (
    .clk_i     (clk_i    ),
    .rst_ni    (rst_ni   ),
    .flush_i   (1'b0     ),
    .testmode_i(1'b0     ),
    .full_o    (         ),
    .empty_o   (         ),
    .usage_o   (         ),
    .data_i    (req_lane ),
    .push_i    (gnt      ),
    .data_o    (rsp_lane ),
    .pop_i     (rsp_valid)
  );

  assign obi_rsp_o = '{
    gnt:    gnt,
    rvalid: rsp_valid,
    rdata:  beat_rdata[rsp_lane*32 +: 32],
    err:    rsp_err
  };

endmodule
