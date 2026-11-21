// Core data-port demux: sends each OBI access of the core to its target by address (CORE_ADDR_MAP,
// decoded by common_cells addr_decode, the decoder of the crossbars) and returns the response of
// that target:
//
//   CORE_TGT_DTCM  D-TCM, OBI
//   CORE_TGT_DATA  L2, through the OBI -> AXI4 bridge
//   CORE_TGT_CTRL  peripheral registers, through the OBI -> AXI4-Lite bridge
//
// An address in no window (Boot ROM and I-TCM included: the core cannot load from them) reaches no
// target. The demux grants it at once and answers with err in the next cycle, which the core takes
// as an access fault.
//
// One access is outstanding at a time. A new one is accepted when none is outstanding or in the
// cycle the outstanding one answers, which is when the core sends it, so back-to-back accesses lose
// no cycle. Responses therefore come in order, and a register of the target of the outstanding
// access selects which one to return.
module bus_obi_demux
  import soc_pkg::*;
(
  input  logic                        clk_i,
  input  logic                        rst_ni,

  // From the core data port
  input  obi_req_t                    obi_req_i,
  output obi_rsp_t                    obi_rsp_o,

  // To the targets, indexed by CORE_TGT_*
  output obi_req_t [CORE_NUM_TGT-1:0] tgt_req_o,
  input  obi_rsp_t [CORE_NUM_TGT-1:0] tgt_rsp_i
);

  localparam int unsigned IdxW = cf_math_pkg::idx_width(CORE_NUM_TGT);

  typedef logic [IdxW-1:0] idx_t;

  idx_t req_idx, rsp_idx_q;
  logic dec_valid;
  logic pending_q, rsp_err_q;  // an access is outstanding; it went to no target
  logic accept, gnt, rsp_valid;

  addr_decode #(
    .NoIndices(CORE_NUM_TGT),
    .NoRules  (CORE_NUM_TGT),
    .addr_t   (axi_addr_t  ),
    .rule_t   (rule_t      )
  ) u_decode (
    .addr_i          (obi_req_i.addr),
    .addr_map_i      (CORE_ADDR_MAP ),
    .idx_o           (req_idx       ),
    .dec_valid_o     (dec_valid     ),
    .dec_error_o     (              ),
    .en_default_idx_i(1'b0          ),
    .default_idx_i   ('0            )
  );

  // The outstanding access answers from its target, or from here one cycle after its grant.
  assign rsp_valid = pending_q & (rsp_err_q | tgt_rsp_i[rsp_idx_q].rvalid);
  assign accept    = ~pending_q | rsp_valid;

  // The payload goes to every target; only the selected one sees req.
  always_comb begin : route_req
    for (int unsigned t = 0; t < CORE_NUM_TGT; t++) begin
      tgt_req_o[t]     = obi_req_i;
      tgt_req_o[t].req = obi_req_i.req & accept & dec_valid & (req_idx == idx_t'(t));
    end
  end

  assign gnt = obi_req_i.req & accept & (dec_valid ? tgt_rsp_i[req_idx].gnt : 1'b1);

  always_ff @(posedge clk_i or negedge rst_ni) begin : outstanding_reg
    if (!rst_ni) begin
      pending_q <= 1'b0;
      rsp_err_q <= 1'b0;
      rsp_idx_q <= '0;
    end else if (gnt) begin
      pending_q <= 1'b1;
      rsp_err_q <= ~dec_valid;
      rsp_idx_q <= req_idx;
    end else if (rsp_valid) begin
      pending_q <= 1'b0;
    end
  end

  assign obi_rsp_o = '{
    gnt:    gnt,
    rvalid: rsp_valid,
    rdata:  tgt_rsp_i[rsp_idx_q].rdata,
    err:    rsp_err_q | tgt_rsp_i[rsp_idx_q].err
  };

endmodule
