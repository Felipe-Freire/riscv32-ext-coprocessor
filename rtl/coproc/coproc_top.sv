// Coprocessor top: the systolic array as one block, ready to instantiate in soc_top.
module coproc_top
  import coproc_pkg::*;
#(
  parameter int unsigned Dim        = ARRAY_DIM,
  // C stream width. Must be a multiple of ACC_W and divide the Dim accumulators of a tile row.
  parameter int unsigned CDataWidth = 128,
  // A and B stream width: one int8 element per PE row / column.
  localparam int unsigned ABDataWidth = Dim * DATA_W,
  // Steps of zeros after the K data steps of a tile: the longest path through skew plus array.
  localparam int unsigned DrainSteps  = 2 * (Dim - 1),
  // C beats: WordsPerBeat accumulators each, BeatsPerRow beats per tile row.
  localparam int unsigned WordsPerBeat = CDataWidth / ACC_W,
  localparam int unsigned BeatsPerRow  = Dim / WordsPerBeat,
  localparam int unsigned BeatsPerTile = Dim * BeatsPerRow,
  localparam int unsigned DrainCntW    = (DrainSteps > 1) ? $clog2(DrainSteps) : 1,
  localparam int unsigned BeatCntW     = (BeatsPerTile > 1) ? $clog2(BeatsPerTile) : 1,
  localparam int unsigned TileShift    = $clog2(Dim)
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic start_i,
  input  dim_t dim_m_i,
  input  dim_t dim_n_i,
  input  dim_t dim_k_i,
  output logic busy_o,
  output logic done_o,

  // A stream: one beat is A[tile row][k], one int8 per PE row, element r in byte lane r.
  input  logic [ABDataWidth-1:0] a_tdata_i,
  input  logic                   a_tvalid_i,
  output logic                   a_tready_o,

  // B stream: one beat is B[k][tile column], one int8 per PE column, element c in byte lane c.
  input  logic [ABDataWidth-1:0] b_tdata_i,
  input  logic                   b_tvalid_i,
  output logic                   b_tready_o,

  // C stream: a tile row-major, WordsPerBeat int32 accumulators per beat, lowest column first.
  output logic [CDataWidth-1:0] c_tdata_o,
  output logic                  c_tvalid_o,
  input  logic                  c_tready_i
);

  typedef enum logic [1:0] {
    StIdle,   // waiting for start_i
    StLoad,   // K data steps of a tile, one A and one B beat per step
    StDrain,  // DrainSteps steps of zeros, pushing the last operands through the array
    StOut     // sending the tile's accumulators on the C stream
  } state_e;

  state_e state_q, state_d;
  dim_t k_q, m_tiles_q, n_tiles_q;

  // Step and beat counters of the tile being computed, and its position in C.
  dim_t                  k_cnt_q, k_cnt_d;
  logic [DrainCntW-1:0]  drain_cnt_q, drain_cnt_d;
  logic [BeatCntW-1:0]   beat_cnt_q, beat_cnt_d;
  dim_t                  ti_q, ti_d, tj_q, tj_d;
  logic                  done_q, done_d;

  logic  load_step, beat_ack;
  logic  arr_en, arr_clr;
  data_t a_edge [Dim], b_edge [Dim];
  data_t a_skew [Dim], b_skew [Dim];
  acc_t  acc [Dim][Dim];

  logic last_k, last_drain, last_beat, last_tile;

  // Stream handshakes

  // A and B advance together: a step happens only when both have a beat. tready may depend on
  // the other stream's tvalid, so the two are joined without a buffer.
  assign load_step  = (state_q == StLoad) && a_tvalid_i && b_tvalid_i;
  assign a_tready_o = (state_q == StLoad) && b_tvalid_i;
  assign b_tready_o = (state_q == StLoad) && a_tvalid_i;

  assign c_tvalid_o = (state_q == StOut);
  assign beat_ack   = c_tvalid_o && c_tready_i;

  // Array control and edge streams

  // The array (and the skew lines in front of it) only advance on a data step or a drain step;
  // while a tile is being sent out, the accumulators have to hold.
  assign arr_en  = load_step || (state_q == StDrain);
  // The first data step of a tile clears the accumulators. coproc_pe_array pipelines the pulse
  // along the operand diagonal, so each PE drops the previous tile on its own first step.
  assign arr_clr = load_step && (k_cnt_q == '0);

  // Outside StLoad the edges are fed zeros: those are the drain steps, and they also flush the
  // skew delay lines before the next tile.
  always_comb begin : edge_mux
    for (int l = 0; l < int'(Dim); l++) begin
      a_edge[l] = (state_q == StLoad) ? data_t'(a_tdata_i[l*DATA_W +: DATA_W]) : '0;
      b_edge[l] = (state_q == StLoad) ? data_t'(b_tdata_i[l*DATA_W +: DATA_W]) : '0;
    end
  end

  coproc_skew #(
    .Dim(Dim)
  ) u_skew_a (
    .clk_i(clk_i ),
    .en_i (arr_en),
    .vec_i(a_edge),
    .vec_o(a_skew)
  );

  coproc_skew #(
    .Dim(Dim)
  ) u_skew_b (
    .clk_i(clk_i ),
    .en_i (arr_en),
    .vec_i(b_edge),
    .vec_o(b_skew)
  );

  coproc_pe_array #(
    .Dim(Dim)
  ) u_pe_array (
    .clk_i (clk_i  ),
    .rst_ni(rst_ni ),
    .en_i  (arr_en ),
    .clr_i (arr_clr),
    .a_i   (a_skew ),
    .b_i   (b_skew ),
    .acc_o (acc    )
  );

  // C beat mux: beat b of a tile holds row b/BeatsPerRow, columns starting at its position in
  // that row, lowest column in the lowest bits.

  always_comb begin : c_beat_mux
    automatic int unsigned row, col_base;
    row       = int'(beat_cnt_q) / BeatsPerRow;
    col_base  = (int'(beat_cnt_q) % BeatsPerRow) * WordsPerBeat;
    c_tdata_o = '0;
    for (int w = 0; w < int'(WordsPerBeat); w++) begin
      c_tdata_o[w*ACC_W +: ACC_W] = acc[row][col_base + w];
    end
  end

  // Tile sequencer

  assign last_k     = (k_cnt_q == k_q - 1);
  assign last_drain = (drain_cnt_q == DrainCntW'(DrainSteps - 1));
  assign last_beat  = (beat_cnt_q == BeatCntW'(BeatsPerTile - 1));
  assign last_tile  = (ti_q == m_tiles_q - 1) && (tj_q == n_tiles_q - 1);

  always_comb begin : fsm
    state_d     = state_q;
    k_cnt_d     = k_cnt_q;
    drain_cnt_d = drain_cnt_q;
    beat_cnt_d  = beat_cnt_q;
    ti_d        = ti_q;
    tj_d        = tj_q;
    done_d      = 1'b0;

    unique case (state_q)
      StIdle: begin
        if (start_i) begin
          ti_d    = '0;
          tj_d    = '0;
          k_cnt_d = '0;
          state_d = StLoad;
        end
      end

      StLoad: begin
        if (load_step) begin
          if (last_k) begin
            k_cnt_d     = '0;
            drain_cnt_d = '0;
            state_d     = StDrain;
          end else begin
            k_cnt_d = k_cnt_q + 1'b1;
          end
        end
      end

      StDrain: begin
        if (last_drain) begin
          beat_cnt_d = '0;
          state_d    = StOut;
        end else begin
          drain_cnt_d = drain_cnt_q + 1'b1;
        end
      end

      StOut: begin
        if (beat_ack) begin
          if (last_beat) begin
            beat_cnt_d = '0;
            if (last_tile) begin
              done_d  = 1'b1;
              state_d = StIdle;
            end else begin
              // Next tile in row-major tile order.
              if (tj_q == n_tiles_q - 1) begin
                tj_d = '0;
                ti_d = ti_q + 1'b1;
              end else begin
                tj_d = tj_q + 1'b1;
              end
              k_cnt_d = '0;
              state_d = StLoad;
            end
          end else begin
            beat_cnt_d = beat_cnt_q + 1'b1;
          end
        end
      end

      default: state_d = StIdle;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : ctrl_reg
    if (!rst_ni) begin
      state_q     <= StIdle;
      k_cnt_q     <= '0;
      drain_cnt_q <= '0;
      beat_cnt_q  <= '0;
      ti_q        <= '0;
      tj_q        <= '0;
      done_q      <= 1'b0;
    end else begin
      state_q     <= state_d;
      k_cnt_q     <= k_cnt_d;
      drain_cnt_q <= drain_cnt_d;
      beat_cnt_q  <= beat_cnt_d;
      ti_q        <= ti_d;
      tj_q        <= tj_d;
      done_q      <= done_d;
    end
  end

  // Configuration, sampled with start_i and held for the whole run: not reset, it is only read
  // after a start has loaded it.
  always_ff @(posedge clk_i) begin : cfg_reg
    if ((state_q == StIdle) && start_i) begin
      k_q       <= (dim_k_i == '0) ? dim_t'(1) : dim_k_i;
      m_tiles_q <= ((dim_m_i >> TileShift) == '0) ? dim_t'(1) : (dim_m_i >> TileShift);
      n_tiles_q <= ((dim_n_i >> TileShift) == '0) ? dim_t'(1) : (dim_n_i >> TileShift);
    end
  end

  assign busy_o = (state_q != StIdle);
  assign done_o = done_q;

endmodule
