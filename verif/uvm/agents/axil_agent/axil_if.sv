// AXI4-Lite signals, 32-bit address and data. The testbench connects the slave's outputs; the
// agent drives the master's outputs with nonblocking assignments and samples through cb. A slave
// with a narrower address takes the low bits of awaddr / araddr.
//
// The protocol assertions cover both sides: a valid stays up with a stable payload until its
// handshake, and no handshake signal is X out of reset.
interface axil_if (
  input logic clk_i,
  input logic rst_ni
);

  logic [31:0] awaddr;
  logic        awvalid;
  logic        awready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid;
  logic        wready;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;
  logic [31:0] araddr;
  logic        arvalid;
  logic        arready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic        rready;

  clocking cb @(posedge clk_i);
    default input #1step;
    input rst_ni, awaddr, awvalid, awready, wdata, wstrb, wvalid, wready, bresp, bvalid, bready,
          araddr, arvalid, arready, rdata, rresp, rvalid, rready;
  endclocking

  property p_hold(valid, ready, payload);
    @(posedge clk_i) disable iff (!rst_ni) valid && !ready |=> valid && $stable(payload);
  endproperty

  aw_hold : assert property (p_hold(awvalid, awready, awaddr));
  w_hold  : assert property (p_hold(wvalid, wready, {wdata, wstrb}));
  b_hold  : assert property (p_hold(bvalid, bready, bresp));
  ar_hold : assert property (p_hold(arvalid, arready, araddr));
  r_hold  : assert property (p_hold(rvalid, rready, {rdata, rresp}));

  known : assert property (@(posedge clk_i) disable iff (!rst_ni)
    !$isunknown({awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid,
                 rready}));

endinterface
