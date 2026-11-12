// Dim x Dim output-stationary systolic array: one 8x8 tile of C = A*B.
//
// PE (r,c) holds C[r][c] for the whole tile. A enters from the west, one element per PE row, and
// travels east; B enters from the north, one element per PE column, and travels south. Each
// coproc_pe registers both operands on the way, so an element that enters the edge at step t
// reaches PE (r,c) at step t + c (A) or t + r (B). With the edges fed skewed, the two meet:
//
//   a_i[r] at step t carries A[r][t-r]   ->  PE (r,c) sees A[r][t-r-c]
//   b_i[c] at step t carries B[t-c][c]   ->  PE (r,c) sees B[t-r-c][c]
//
// so every step PE (r,c) multiplies A[r][k] by B[k][c] for the same k = t-r-c, and over K steps
// it accumulates the full dot product. The skew and drain logic that shapes the edge streams
// lives outside this module, as does the tile sequencer that drives en_i and clr_i.
//
// Timing: a tile is K steps of data followed by 2*(Dim-1) steps of zeros, which drain the last
// operands through the array; PE (Dim-1,Dim-1) takes its last step at K + 2*(Dim-1) - 1. acc_o is
// the raw accumulator output, so it is only final for every PE once that drain has run.
//
// clr_i is pulsed with the first step of a tile and travels through the array on the same
// diagonal as the operands, so each PE drops the previous tile's sum on the step its own tile
// starts, r+c steps after the edge.
module coproc_pe_array
  import coproc_pkg::*;
#(
  parameter int unsigned Dim = ARRAY_DIM
) (
  input  logic  clk_i,
  input  logic  rst_ni,
  input  logic  en_i,
  input  logic  clr_i,
  input  data_t a_i [Dim],
  input  data_t b_i [Dim],
  output acc_t  acc_o [Dim][Dim]
);

  // Operands handed from each PE to its east and south neighbour.
  data_t a_fwd [Dim][Dim];
  data_t b_fwd [Dim][Dim];
  // Tile start as seen by each PE. clr_pe[0][0] is the edge input itself; every other PE takes
  // it from a neighbour, one step later, so the delay to PE (r,c) is exactly r+c. This pipeline
  // is the only control state in the array, and the only state that is reset.
  logic  clr_pe [Dim][Dim];

  for (genvar r = 0; r < int'(Dim); r++) begin : gen_row
    for (genvar c = 0; c < int'(Dim); c++) begin : gen_col

      // Operands of this PE: the array edge on the first row / column, the neighbour otherwise.
      data_t a_in, b_in;

      if (c == 0) begin : gen_a_edge
        assign a_in = a_i[r];
      end else begin : gen_a_fwd
        assign a_in = a_fwd[r][c-1];
      end

      if (r == 0) begin : gen_b_edge
        assign b_in = b_i[c];
      end else begin : gen_b_fwd
        assign b_in = b_fwd[r-1][c];
      end

      // The clr pulse enters at PE (0,0) and is registered on from there. Along the top row it
      // comes from the west, everywhere else from the north; both paths give the same r+c delay.
      if (r == 0 && c == 0) begin : gen_clr_edge
        assign clr_pe[0][0] = clr_i;
      end else begin : gen_clr_pipe
        logic clr_in, clr_q;

        if (r == 0) begin : gen_clr_west
          assign clr_in = clr_pe[0][c-1];
        end else begin : gen_clr_north
          assign clr_in = clr_pe[r-1][c];
        end

        always_ff @(posedge clk_i or negedge rst_ni) begin : clr_reg
          if (!rst_ni) begin
            clr_q <= 1'b0;
          end else if (en_i) begin
            clr_q <= clr_in;
          end
        end

        assign clr_pe[r][c] = clr_q;
      end

      coproc_pe u_pe (
        .clk_i(clk_i),
        .en_i (en_i),
        .clr_i(clr_pe[r][c]),
        .a_i  (a_in),
        .b_i  (b_in),
        .a_o  (a_fwd[r][c]),
        .b_o  (b_fwd[r][c]),
        .acc_o(acc_o[r][c])
      );

    end
  end

  // The east and south edges of the array are not read: the operands leave the array there.

endmodule
