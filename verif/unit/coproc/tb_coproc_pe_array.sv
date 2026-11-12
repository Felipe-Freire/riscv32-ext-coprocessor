// coproc_pe_array: random tiles against a behavioural matrix product, with the edge streams
// skewed the way the block expects them (a_i[r] delayed by r, b_i[c] delayed by c) and the drain
// steps that push the last operands through the array. Two tiles are run back to back so that
// clr_i is exercised on a non-empty array. The PE and the MAC are covered through the array.
module tb_coproc_pe_array;
  import coproc_pkg::*;

  localparam int unsigned Dim  = 4;   // smaller than the 8x8 array, same structure
  localparam int unsigned MaxK = 16;

  logic  clk = 1'b0;
  logic  rst_n, en, clr;
  data_t a [Dim], b [Dim];
  acc_t  acc [Dim][Dim];

  int errors = 0, checks = 0;

  coproc_pe_array #(
    .Dim(Dim)
  ) dut (
    .clk_i (clk  ),
    .rst_ni(rst_n),
    .en_i  (en   ),
    .clr_i (clr  ),
    .a_i   (a    ),
    .b_i   (b    ),
    .acc_o (acc  )
  );

  always #5 clk = ~clk;

  // Operands of the tile being run, and the expected result.
  data_t mat_a [Dim][MaxK];
  data_t mat_b [MaxK][Dim];
  acc_t  expected [Dim][Dim];

  // One step of the array: drive the edges, then let one clock edge consume them.
  task automatic step(data_t a_edge [Dim], data_t b_edge [Dim], logic clr_step);
    a   = a_edge;
    b   = b_edge;
    clr = clr_step;
    en  = 1'b1;
    @(posedge clk);
    #1;
  endtask

  // Random A (Dim x k_len) and B (k_len x Dim), plus the product they should produce.
  task automatic randomize_tile(int k_len);
    foreach (mat_a[r, k]) mat_a[r][k] = data_t'($urandom());
    foreach (mat_b[k, c]) mat_b[k][c] = data_t'($urandom());
    for (int r = 0; r < int'(Dim); r++) begin
      for (int c = 0; c < int'(Dim); c++) begin
        expected[r][c] = '0;
        for (int k = 0; k < k_len; k++) begin
          expected[r][c] = expected[r][c] + acc_t'(mat_a[r][k] * mat_b[k][c]);
        end
      end
    end
  endtask

  // k_len steps of data followed by 2*(Dim-1) steps of zeros, which drain the array.
  task automatic run_tile(int k_len);
    data_t a_edge [Dim], b_edge [Dim];
    for (int t = 0; t < k_len + 2 * (int'(Dim) - 1); t++) begin
      for (int r = 0; r < int'(Dim); r++) begin
        a_edge[r] = (t - r >= 0 && t - r < k_len) ? mat_a[r][t-r] : '0;
      end
      for (int c = 0; c < int'(Dim); c++) begin
        b_edge[c] = (t - c >= 0 && t - c < k_len) ? mat_b[t-c][c] : '0;
      end
      step(a_edge, b_edge, t == 0);
    end
    en = 1'b0;
    #1;
  endtask

  task automatic check_tile(int k_len);
    for (int r = 0; r < int'(Dim); r++) begin
      for (int c = 0; c < int'(Dim); c++) begin
        checks++;
        if (acc[r][c] !== expected[r][c]) begin
          errors++;
          if (errors <= 10) begin
            $display("FAIL: K=%0d acc[%0d][%0d]=%0d expected=%0d",
                     k_len, r, c, acc[r][c], expected[r][c]);
          end
        end
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    en    = 1'b0;
    clr   = 1'b0;
    a     = '{default: '0};
    b     = '{default: '0};
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    #1;

    // Every K from 1 to MaxK, twice in a row: the second tile starts on an array that still
    // holds the first tile's accumulators, so it only passes if clr_i reaches every PE on the
    // right step.
    for (int k_len = 1; k_len <= int'(MaxK); k_len++) begin
      repeat (2) begin
        randomize_tile(k_len);
        run_tile(k_len);
        check_tile(k_len);
      end
    end

    if (errors == 0) $display("PASS: %0d checks", checks);
    else             $display("FAIL: %0d of %0d checks", errors, checks);
    $finish;
  end

endmodule
