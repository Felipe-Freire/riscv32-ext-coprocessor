// Tightly coupled memory: an OBI target on one prim_ram_1p, with no wait state. The SoC has two:
//
//   D-TCM  behind bus_obi_demux (CORE_TGT_DTCM): loads and stores of the core, HoldRdata = 0
//   I-TCM  on the fetch path of the core, HoldRdata = 1: the fetch port takes the instruction one
//          cycle after the request and expects it held while the request is low
//          (rtl/core/README.md#ports)
//
// Protocol (soc_pkg::obi_req_t, obi_rsp_t):
//   - gnt is always 1: every request is taken in its cycle, and a new one can come in the cycle of
//     the response of the previous one, so back-to-back accesses lose no cycle;
//   - rvalid comes exactly one cycle after each request, load or store; err is always 0 (the
//     demuxes in front of the TCMs answer the addresses outside them);
//   - rdata is the loaded word with the rvalid of a load. In every other cycle it is 0, or, with
//     HoldRdata, the word of the last load (0 before the first one).
//
// The word index is addr[$clog2(SizeBytes)-1:2]: the bits above select the TCM in the demux and are
// ignored here. be selects the bytes of a store.
//
// Simulation only: bd_write and bd_read reach a word by its index without a cycle, for testbenches
// that load programs or check results (prim_ram_1p).
module mem_tcm
  import soc_pkg::*;
#(
  parameter int unsigned SizeBytes = 32'h8000,  // a power of 2, at least 8 (2 words)
  parameter bit          HoldRdata = 1'b0        // keep the last loaded word on rdata
) (
  input  logic     clk_i,
  input  logic     rst_ni,

  input  obi_req_t obi_req_i,
  output obi_rsp_t obi_rsp_o
);

  localparam int unsigned Depth = SizeBytes / 4;
  localparam int unsigned IdxW  = $clog2(Depth);

  logic [IdxW-1:0] index;
  logic [31:0]     ram_rdata, rdata;
  logic            rvalid_q, load_q;

  assign index = obi_req_i.addr[2 +: IdxW];

  prim_ram_1p #(
    .Width(32   ),
    .Depth(Depth)
  ) u_ram (
    .clk_i  (clk_i          ),
    .req_i  (obi_req_i.req  ),
    .we_i   (obi_req_i.we   ),
    .addr_i (index          ),
    .wdata_i(obi_req_i.wdata),
    .be_i   (obi_req_i.be   ),
    .rdata_o(ram_rdata      )
  );

  // The response of the access of the previous cycle; the RAM holds its read data in this one only.
  always_ff @(posedge clk_i or negedge rst_ni) begin : rsp_reg
    if (!rst_ni) begin
      rvalid_q <= 1'b0;
      load_q   <= 1'b0;
    end else begin
      rvalid_q <= obi_req_i.req;
      load_q   <= obi_req_i.req & ~obi_req_i.we;
    end
  end

  if (HoldRdata) begin : gen_hold
    logic [31:0] rdata_q;

    // The word of the last load, kept from the cycle after its response on.
    always_ff @(posedge clk_i or negedge rst_ni) begin : hold_reg
      if (!rst_ni) begin
        rdata_q <= '0;
      end else if (load_q) begin
        rdata_q <= ram_rdata;
      end
    end

    assign rdata = load_q ? ram_rdata : rdata_q;
  end else begin : gen_no_hold
    assign rdata = load_q ? ram_rdata : '0;
  end

  assign obi_rsp_o = '{gnt: 1'b1, rvalid: rvalid_q, rdata: rdata, err: 1'b0};

`ifndef SYNTHESIS
  function automatic void bd_write(input int unsigned index, input logic [31:0] data);
    u_ram.bd_write(index, data);
  endfunction

  function automatic logic [31:0] bd_read(input int unsigned index);
    return u_ram.bd_read(index);
  endfunction

  // Checked at elaboration.
  if (SizeBytes < 8 || (SizeBytes & (SizeBytes - 1)) != 0) begin : gen_bad_size
    $fatal(1, "mem_tcm: SizeBytes %0d is not a power of 2 of at least 8", SizeBytes);
  end
`endif

endmodule
