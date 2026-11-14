// AXI4-Stream signals (TVALID, TREADY, TDATA). tdata is AXIS_MAX_DW wide; the testbench connects
// the low bits a port uses and ties the rest to 0. The side the agent plays drives its outputs
// with nonblocking assignments; the testbench connects the other side.
interface axis_if (
  input logic clk_i,
  input logic rst_ni
);

  logic [255:0] tdata;
  logic         tvalid;
  logic         tready;

  clocking cb @(posedge clk_i);
    default input #1step;
    input rst_ni, tdata, tvalid, tready;
  endclocking

  // A beat, once offered, stays offered and unchanged until it is taken.
  hold : assert property (@(posedge clk_i) disable iff (!rst_ni)
    tvalid && !tready |=> tvalid && $stable(tdata));

  known : assert property (@(posedge clk_i) disable iff (!rst_ni) !$isunknown({tvalid, tready}));

endinterface
