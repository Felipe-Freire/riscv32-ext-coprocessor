// Processing element: one coproc_mac plus the two registers that forward the operands on.
module coproc_pe
  import coproc_pkg::*;
(
  input  logic  clk_i,
  input  logic  en_i,
  input  logic  clr_i,
  input  data_t a_i,
  input  data_t b_i,
  output data_t a_o,
  output data_t b_o,
  output acc_t  acc_o
);

  data_t a_q, b_q;

  coproc_mac u_mac (
    .clk_i(clk_i),
    .en_i (en_i ),
    .clr_i(clr_i),
    .a_i  (a_i  ),
    .b_i  (b_i  ),
    .acc_o(acc_o)
  );

  always_ff @(posedge clk_i) begin : fwd_reg
    if (en_i) begin
      a_q <= a_i;
      b_q <= b_i;
    end
  end

  assign a_o = a_q;
  assign b_o = b_q;

endmodule
