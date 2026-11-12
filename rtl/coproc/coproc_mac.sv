// Multiply-accumulate: acc = acc + a*b, the arithmetic core of a processing element.
module coproc_mac
  import coproc_pkg::*;
(
  input  logic  clk_i,
  input  logic  en_i,
  input  logic  clr_i,
  input  data_t a_i,
  input  data_t b_i,
  output acc_t  acc_o
);

  acc_t prod, acc_d, acc_q;

  // a_i and b_i are signed, so the product is a signed 2*DATA_W value and the cast to acc_t
  // sign-extends it.
  assign prod  = acc_t'(a_i * b_i);
  assign acc_d = (clr_i ? acc_t'(0) : acc_q) + prod;

  always_ff @(posedge clk_i) begin : acc_reg
    if (en_i) begin
      acc_q <= acc_d;
    end
  end

  assign acc_o = acc_q;

endmodule
