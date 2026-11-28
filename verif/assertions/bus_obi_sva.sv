// OBI protocol checker, bound to the two OBI ports of bus_obi_demux that no vendor module checks:
// the core data port and the D-TCM port. (The bridges of the other two targets, axi_from_mem and
// axi_lite_from_mem, assert the same request rules on their inputs.)
//
//   - req stays up until gnt, and addr, we, be and wdata hold while it waits;
//   - every rvalid answers an access granted before it;
//   - at most MaxOutstanding accesses are granted and not answered at the start of a cycle.
//
// The binds are left out at gate level, where the netlist need not keep the demux.
module bus_obi_sva
  import soc_pkg::*;
#(
  parameter int unsigned MaxOutstanding = 1,
  parameter string       Port           = "obi"
) (
  input logic     clk_i,
  input logic     rst_ni,
  input obi_req_t req,
  input obi_rsp_t rsp
);

  default clocking cb @(posedge clk_i); endclocking
  default disable iff (!rst_ni);

  int unsigned outstanding_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin : outstanding_cnt
    if (!rst_ni) begin
      outstanding_q <= 0;
    end else begin
      outstanding_q <= outstanding_q + (req.req && rsp.gnt) - rsp.rvalid;
    end
  end

  a_req_held: assert property (req.req && !rsp.gnt |=> req.req)
    else $error("%s: req dropped before gnt", Port);

  a_payload_stable: assert property (req.req && !rsp.gnt |=>
                                     $stable({req.addr, req.we, req.be, req.wdata}))
    else $error("%s: addr, we, be or wdata changed while waiting for gnt", Port);

  a_rsp_requested: assert property (rsp.rvalid |-> outstanding_q != 0)
    else $error("%s: rvalid with no access outstanding", Port);

  a_outstanding: assert property (outstanding_q <= MaxOutstanding)
    else $error("%s: %0d accesses outstanding, at most %0d", Port, outstanding_q, MaxOutstanding);

endmodule

`ifndef GLS
bind bus_obi_demux bus_obi_sva #(.Port("core data port")) u_core_sva (
  .clk_i (clk_i    ),
  .rst_ni(rst_ni   ),
  .req   (obi_req_i),
  .rsp   (obi_rsp_o)
);

bind bus_obi_demux bus_obi_sva #(.Port("D-TCM port")) u_dtcm_sva (
  .clk_i (clk_i                            ),
  .rst_ni(rst_ni                           ),
  .req   (tgt_req_o[soc_pkg::CORE_TGT_DTCM]),
  .rsp   (tgt_rsp_i[soc_pkg::CORE_TGT_DTCM])
);
`endif
