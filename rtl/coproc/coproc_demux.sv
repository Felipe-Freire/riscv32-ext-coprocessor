// One-hot fan-out: in_i is driven onto output sel_i and zero onto the others.
module coproc_demux
  import coproc_pkg::*;
#(
  parameter int unsigned Dim = ARRAY_DIM,
  localparam int unsigned SelWidth = (Dim > 1) ? $clog2(Dim) : 1
) (
  input  logic [SelWidth-1:0] sel_i,
  input  data_t               in_i,
  output data_t               out_o [Dim]
);

  always_comb begin : fanout
    out_o = '{default: '0};
    out_o[sel_i] = in_i;
  end

endmodule
