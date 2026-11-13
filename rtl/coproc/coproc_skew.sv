// Edge-stream skew: lane l of the output is lane l of the input delayed by l enabled steps.
module coproc_skew
  import coproc_pkg::*;
#(
  parameter int unsigned Dim = ARRAY_DIM
) (
  input  logic  clk_i,
  input  logic  en_i,
  input  data_t vec_i [Dim],
  output data_t vec_o [Dim]
);

  for (genvar l = 0; l < int'(Dim); l++) begin : gen_lane

    if (l == 0) begin : gen_passthrough
      // Lane 0 enters the array unchanged: its delay is zero.
      assign vec_o[0] = vec_i[0];
    end else begin : gen_delay
      data_t dly_q [l];

      always_ff @(posedge clk_i) begin : dly_reg
        if (en_i) begin
          dly_q[0] <= vec_i[l];
          for (int d = 1; d < l; d++) begin
            dly_q[d] <= dly_q[d-1];
          end
        end
      end

      assign vec_o[l] = dly_q[l-1];
    end

  end

endmodule
