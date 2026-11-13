// coproc_top: random M x K by K x N products against a behavioural reference, driven through the
// three streams the SoC uses. The A and B drivers and the C monitor back off at random, so the
// sequencer is exercised with empty input streams and with a stalled output stream. The skew,
// the drain and the tile sequencing are covered through the block; the array has its own
// testbench.
//
// Stream convention in this testbench: signals are driven 1 ns after a rising edge and sampled
// on the falling edge, where the combinational ready and valid of the cycle have settled; a beat
// whose handshake holds at that falling edge transfers on the next rising edge.
module tb_coproc_top;
  import coproc_pkg::*;

  localparam int unsigned Dim        = 4;    // smaller than the 8x8 array, same structure
  localparam int unsigned CDataWidth = 128;

  localparam int unsigned AbW          = Dim * DATA_W;
  localparam int unsigned WordsPerBeat = CDataWidth / ACC_W;
  localparam int unsigned BeatsPerRow  = Dim / WordsPerBeat;
  localparam int unsigned BeatsPerTile = Dim * BeatsPerRow;

  localparam int unsigned MaxM = 4 * Dim;
  localparam int unsigned MaxN = 4 * Dim;
  localparam int unsigned MaxK = 12;

  logic clk = 1'b0;
  logic rst_n;

  logic start, busy, done;
  dim_t dim_m, dim_n, dim_k;

  logic [AbW-1:0]        a_tdata, b_tdata;
  logic                  a_tvalid, b_tvalid;
  logic                  a_tready, b_tready;
  logic [CDataWidth-1:0] c_tdata;
  logic                  c_tvalid, c_tready;

  int errors = 0, checks = 0;

  coproc_top #(
    .Dim       (Dim       ),
    .CDataWidth(CDataWidth)
  ) dut (
    .clk_i     (clk     ),
    .rst_ni    (rst_n   ),
    .start_i   (start   ),
    .dim_m_i   (dim_m   ),
    .dim_n_i   (dim_n   ),
    .dim_k_i   (dim_k   ),
    .busy_o    (busy    ),
    .done_o    (done    ),
    .a_tdata_i (a_tdata ),
    .a_tvalid_i(a_tvalid),
    .a_tready_o(a_tready),
    .b_tdata_i (b_tdata ),
    .b_tvalid_i(b_tvalid),
    .b_tready_o(b_tready),
    .c_tdata_o (c_tdata ),
    .c_tvalid_o(c_tvalid),
    .c_tready_i(c_tready)
  );

  always #5 clk = ~clk;

  // The matrices of the run in progress and the product they should produce.
  data_t mat_a [MaxM][MaxK];
  data_t mat_b [MaxK][MaxN];
  acc_t  mat_c [MaxM][MaxN];

  task automatic randomize_matrices(int m, int n, int k);
    foreach (mat_a[r, kk]) mat_a[r][kk] = data_t'($urandom());
    foreach (mat_b[kk, c]) mat_b[kk][c] = data_t'($urandom());
    for (int r = 0; r < m; r++) begin
      for (int c = 0; c < n; c++) begin
        mat_c[r][c] = '0;
        for (int kk = 0; kk < k; kk++) begin
          mat_c[r][c] = mat_c[r][c] + acc_t'(mat_a[r][kk] * mat_b[kk][c]);
        end
      end
    end
  endtask

  // A driver: for every tile, in row-major tile order, the K beats of that tile row's A panel.
  // One beat is A[Dim*ti+r][k] for every r, element r in byte lane r.
  task automatic drive_a(int m, int n, int k);
    logic [AbW-1:0] beat;
    for (int ti = 0; ti < m / int'(Dim); ti++) begin
      for (int tj = 0; tj < n / int'(Dim); tj++) begin
        for (int kk = 0; kk < k; kk++) begin
          beat = '0;
          for (int r = 0; r < int'(Dim); r++) begin
            beat[r*DATA_W +: DATA_W] = mat_a[int'(Dim)*ti + r][kk];
          end
          while ($urandom_range(3) == 0) begin  // random gaps in the stream
            a_tvalid = 1'b0;
            @(posedge clk);
            #1;
          end
          a_tdata  = beat;
          a_tvalid = 1'b1;
          do begin
            @(negedge clk);
          end while (!a_tready);
          @(posedge clk);  // the beat transfers here
          #1;
          a_tvalid = 1'b0;
        end
      end
    end
  endtask

  // B driver: the K beats of the tile column's B panel, one beat B[k][Dim*tj+c] for every c.
  task automatic drive_b(int m, int n, int k);
    logic [AbW-1:0] beat;
    for (int ti = 0; ti < m / int'(Dim); ti++) begin
      for (int tj = 0; tj < n / int'(Dim); tj++) begin
        for (int kk = 0; kk < k; kk++) begin
          beat = '0;
          for (int c = 0; c < int'(Dim); c++) begin
            beat[c*DATA_W +: DATA_W] = mat_b[kk][int'(Dim)*tj + c];
          end
          while ($urandom_range(3) == 0) begin
            b_tvalid = 1'b0;
            @(posedge clk);
            #1;
          end
          b_tdata  = beat;
          b_tvalid = 1'b1;
          do begin
            @(negedge clk);
          end while (!b_tready);
          @(posedge clk);
          #1;
          b_tvalid = 1'b0;
        end
      end
    end
  endtask

  // C monitor: every beat is checked against the reference as it arrives, in the order the block
  // sends the tiles and the rows inside a tile.
  task automatic check_c(int m, int n, int k);
    int   row, col_base;
    acc_t got, exp;
    for (int ti = 0; ti < m / int'(Dim); ti++) begin
      for (int tj = 0; tj < n / int'(Dim); tj++) begin
        for (int beat = 0; beat < int'(BeatsPerTile); beat++) begin
          row      = beat / int'(BeatsPerRow);
          col_base = (beat % int'(BeatsPerRow)) * int'(WordsPerBeat);
          while ($urandom_range(3) == 0) begin  // random back-pressure
            c_tready = 1'b0;
            @(posedge clk);
            #1;
          end
          c_tready = 1'b1;
          do begin
            @(negedge clk);
          end while (!c_tvalid);
          for (int w = 0; w < int'(WordsPerBeat); w++) begin
            got = acc_t'(c_tdata[w*ACC_W +: ACC_W]);
            exp = mat_c[int'(Dim)*ti + row][int'(Dim)*tj + col_base + w];
            checks++;
            if (got !== exp) begin
              errors++;
              if (errors <= 10) begin
                $display("FAIL: M=%0d N=%0d K=%0d C[%0d][%0d]=%0d expected=%0d",
                         m, n, k, int'(Dim)*ti + row, int'(Dim)*tj + col_base + w, got, exp);
              end
            end
          end
          @(posedge clk);  // the beat transfers here
          #1;
          c_tready = 1'b0;
        end
      end
    end
  endtask

  task automatic run(int m, int n, int k);
    randomize_matrices(m, n, k);

    dim_m = dim_t'(m);
    dim_n = dim_t'(n);
    dim_k = dim_t'(k);
    start = 1'b1;
    @(posedge clk);  // start is taken here
    #1;
    start = 1'b0;

    fork
      drive_a(m, n, k);
      drive_b(m, n, k);
      check_c(m, n, k);
    join

    // The last C beat has just transferred: done_o is set by that same edge and busy_o has
    // dropped with it.
    checks += 2;
    if (!done) begin
      errors++;
      $display("FAIL: M=%0d N=%0d K=%0d no done pulse on the last C beat", m, n, k);
    end
    if (busy) begin
      errors++;
      $display("FAIL: M=%0d N=%0d K=%0d still busy after the last C beat", m, n, k);
    end

    @(posedge clk);
    #1;
  endtask

  initial begin
    rst_n    = 1'b0;
    start    = 1'b0;
    a_tvalid = 1'b0;
    b_tvalid = 1'b0;
    c_tready = 1'b0;
    a_tdata  = '0;
    b_tdata  = '0;
    dim_m    = '0;
    dim_n    = '0;
    dim_k    = '0;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;

    // One tile, the smallest run, then larger tile grids. Every run starts on an array that
    // still holds the previous run's accumulators, so the clr path is exercised throughout.
    run(int'(Dim), int'(Dim), 1);
    run(int'(Dim), int'(Dim), int'(MaxK));
    run(2 * int'(Dim), int'(Dim), 3);
    run(int'(Dim), 2 * int'(Dim), 5);
    run(2 * int'(Dim), 2 * int'(Dim), int'(MaxK));
    run(int'(MaxM), int'(MaxN), 2);

    if (errors == 0) $display("PASS: %0d checks", checks);
    else             $display("FAIL: %0d of %0d checks", errors, checks);
    $finish;
  end

endmodule
