// Testbench Unitário do Acelerador (coproc_core)
// Emula o comportamento do DMA nos streams A, B e C.
module tb_coproc_unit #(
  parameter int unsigned Dim        = 4,
  parameter int unsigned CDataWidth = Dim * coproc_pkg::ACC_W
) (
  output int total_errors,
  output int total_checks
);
  import coproc_pkg::*;

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
  assign total_errors = errors;
  assign total_checks = checks;

  // Instancia diretamente o núcleo do acelerador (sem AXI-Lite e sem CDC)
  coproc_core #(
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

  data_t mat_a [MaxM][MaxK];
  data_t mat_b [MaxK][MaxN];
  acc_t  mat_c [MaxM][MaxN];

  // Modelo de referência comportamental
  task automatic compute_reference(int m, int n, int k);
    for (int r = 0; r < m; r++) begin
      for (int c = 0; c < n; c++) begin
        mat_c[r][c] = '0;
        for (int kk = 0; kk < k; kk++) begin
          mat_c[r][c] = mat_c[r][c] + acc_t'(mat_a[r][kk] * mat_b[kk][c]);
        end
      end
    end
  endtask

  task automatic randomize_matrices(int m, int n, int k);
    foreach (mat_a[r, kk]) mat_a[r][kk] = data_t'($urandom());
    foreach (mat_b[kk, c]) mat_b[kk][c] = data_t'($urandom());
    compute_reference(m, n, k);
  endtask

  // Dados manuais determinísticos para inspeção visual na onda e no log
  task automatic load_manual_matrices(int m, int n, int k);
    for (int r = 0; r < m; r++) begin
      for (int kk = 0; kk < k; kk++) begin
        mat_a[r][kk] = data_t'(r + kk + 1);
      end
    end
    for (int kk = 0; kk < k; kk++) begin
      for (int c = 0; c < n; c++) begin
        mat_b[kk][c] = (kk == c) ? data_t'(2) : data_t'(1);
      end
    end
    compute_reference(m, n, k);
  endtask

  // Driver DMA Canal A
  task automatic drive_a(int m, int n, int k, bit random_stalls = 1'b1);
    logic [AbW-1:0] beat;
    for (int ti = 0; ti < m / int'(Dim); ti++) begin
      for (int tj = 0; tj < n / int'(Dim); tj++) begin
        for (int kk = 0; kk < k; kk++) begin
          beat = '0;
          for (int r = 0; r < int'(Dim); r++) begin
            beat[r*DATA_W +: DATA_W] = mat_a[int'(Dim)*ti + r][kk];
          end
          while (random_stalls && ($urandom_range(3) == 0)) begin
            a_tvalid = 1'b0;
            @(posedge clk);
            #1;
          end
          a_tdata  = beat;
          a_tvalid = 1'b1;
          do begin
            @(negedge clk);
          end while (!a_tready);
          @(posedge clk);
          #1;
          a_tvalid = 1'b0;
        end
      end
    end
  endtask

  // Driver DMA Canal B
  task automatic drive_b(int m, int n, int k, bit random_stalls = 1'b1);
    logic [AbW-1:0] beat;
    for (int ti = 0; ti < m / int'(Dim); ti++) begin
      for (int tj = 0; tj < n / int'(Dim); tj++) begin
        for (int kk = 0; kk < k; kk++) begin
          beat = '0;
          for (int c = 0; c < int'(Dim); c++) begin
            beat[c*DATA_W +: DATA_W] = mat_b[kk][int'(Dim)*tj + c];
          end
          while (random_stalls && ($urandom_range(3) == 0)) begin
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

  // Monitor DMA Canal C
  task automatic check_c(int m, int n, int k, bit random_stalls = 1'b1, bit verbose = 1'b0);
    int   row, col_base;
    acc_t got, exp;
    for (int ti = 0; ti < m / int'(Dim); ti++) begin
      for (int tj = 0; tj < n / int'(Dim); tj++) begin
        for (int beat = 0; beat < int'(BeatsPerTile); beat++) begin
          row      = beat / int'(BeatsPerRow);
          col_base = (beat % int'(BeatsPerRow)) * int'(WordsPerBeat);
          while (random_stalls && ($urandom_range(3) == 0)) begin
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
            if (verbose) begin
              $display("  [Array %0dx%0d] C[%0d][%0d] = %0d (Esperado: %0d)",
                       Dim, Dim, int'(Dim)*ti + row, int'(Dim)*tj + col_base + w, got, exp);
            end
            if (got !== exp) begin
              errors++;
              if (errors <= 10) begin
                $display("FAIL [Array %0dx%0d]: M=%0d N=%0d K=%0d C[%0d][%0d]=%0d expected=%0d",
                         Dim, Dim, m, n, k, int'(Dim)*ti + row, int'(Dim)*tj + col_base + w, got, exp);
              end
            end
          end
          @(posedge clk);
          #1;
          c_tready = 1'b0;
        end
      end
    end
  endtask

  task automatic run_case(int m, int n, int k, bit manual_mode = 1'b0);
    if (manual_mode) begin
      $display("--- Teste Manual Deterministico [Array %0dx%0d | M=%0d, N=%0d, K=%0d] ---", Dim, Dim, m, n, k);
      load_manual_matrices(m, n, k);
    end else begin
      randomize_matrices(m, n, k);
    end

    dim_m = dim_t'(m);
    dim_n = dim_t'(n);
    dim_k = dim_t'(k);
    start = 1'b1;
    @(posedge clk);
    #1;
    start = 1'b0;

    fork
      drive_a(m, n, k, !manual_mode);
      drive_b(m, n, k, !manual_mode);
      check_c(m, n, k, !manual_mode, manual_mode);
    join

    checks += 2;
    if (!done) begin
      errors++;
      $display("FAIL [Array %0dx%0d]: M=%0d N=%0d K=%0d sem pulso done_o", Dim, Dim, m, n, k);
    end
    if (busy) begin
      errors++;
      $display("FAIL [Array %0dx%0d]: M=%0d N=%0d K=%0d busy_o alto apos termino", Dim, Dim, m, n, k);
    end

    @(posedge clk);
    #1;
  endtask

  task automatic run_suite();
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

    // 1. Injeção manual determinística (prova acumulação de K=3 produtos parciais)
    run_case(int'(Dim), int'(Dim), 3, 1'b1);

    // 2. Testes aleatórios de regressão (tiling e back-pressure no DMA)
    run_case(int'(Dim), int'(Dim), 1, 1'b0);
    run_case(int'(Dim), int'(Dim), int'(MaxK), 1'b0);
    run_case(2 * int'(Dim), int'(Dim), 3, 1'b0);
    run_case(int'(Dim), 2 * int'(Dim), 5, 1'b0);
    run_case(2 * int'(Dim), 2 * int'(Dim), int'(MaxK), 1'b0);
    run_case(int'(MaxM), int'(MaxN), 2, 1'b0);
  endtask

endmodule


// Top-Level do Testbench Unitário (Executa 2x2 e 4x4)
module tb_accelerator_top;
  int err_2x2, chk_2x2;
  int err_4x4, chk_4x4;

  tb_coproc_unit #(.Dim(2)) u_tb_2x2 (
    .total_errors(err_2x2),
    .total_checks(chk_2x2)
  );

  tb_coproc_unit #(.Dim(4)) u_tb_4x4 (
    .total_errors(err_4x4),
    .total_checks(chk_4x4)
  );

  initial begin
    $dumpfile("tb_accelerator_unit.vcd");
    $dumpvars(0, tb_accelerator_top);
    $display(" TESTBENCH UNITARIO DO ACELERADOR (coproc_core: 2x2 e 4x4)");

    u_tb_2x2.run_suite();
    u_tb_4x4.run_suite();

    $display(" RESUMO FINAL:");
    $display("  Array 2x2 -> Checks: %0d | Erros: %0d", chk_2x2, err_2x2);
    $display("  Array 4x4 -> Checks: %0d | Erros: %0d", chk_4x4, err_4x4);
    if ((err_2x2 + err_4x4) == 0)
      $display(" STATUS: PASS (%0d checks totais sem erros)", chk_2x2 + chk_4x4);
    else
      $display(" STATUS: FAIL (%0d erros encontrados)", err_2x2 + err_4x4);
    $finish;
  end
endmodule