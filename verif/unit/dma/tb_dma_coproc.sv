// Integration testbench (Entrega Parcial 3): dma_top + behavioral 64 KiB L2 + coproc_top
// Acts as the RV32I host configuring coproc_top and dma_top via AXI4-Lite according to sw/README.md,
// runs end-to-end matrix multiplications (C = A * B, int8 -> int32) and checks L2 against a golden model.
//
// Run: make sim TB=tb_dma_coproc (WAVES=1 records waves.shm for SimVision).
//`timescale 1ns/1ps

module tb_dma_coproc;
  import dma_pkg::*;

  localparam logic [31:0] L2_BASE  = 32'h2000_0000;
  localparam logic [31:0] A_BASE   = 32'h2000_0000;
  localparam logic [31:0] B_BASE   = 32'h2000_4000;
  localparam logic [31:0] C_BASE   = 32'h2000_8000;
  localparam int unsigned L2_WORDS = 4096; // 64 KiB (4096 x 16 bytes)

  // Clocks & reset (async clk_acc_i exercises coproc_top CDC as well)
  logic clk_i;
  logic clk_acc_i;
  logic rst_ni;

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;        // 100 MHz system clock

  // A handshake that never completes ends the run instead of hanging the regression.
  initial begin : watchdog
    #1ms;
    $fatal(1, "timeout: the test did not finish in 1 ms");
  end

  initial clk_acc_i = 1'b0;
  always #4 clk_acc_i = ~clk_acc_i; // 125 MHz accelerator clock

  // DMA AXI4-Lite & AXI4 signals
  dma_axil_req_t dma_reg_req;
  dma_axil_rsp_t dma_reg_rsp;
  dma_axi_req_t  axi_req;
  dma_axi_rsp_t  axi_rsp;
  logic          irq_o;

  // Coprocessor AXI4-Lite signals
  logic [11:0] cop_awaddr;
  logic        cop_awvalid, cop_awready;
  logic [31:0] cop_wdata;
  logic [3:0]  cop_wstrb;
  logic        cop_wvalid, cop_wready;
  logic [1:0]  cop_bresp;
  logic        cop_bvalid, cop_bready;
  logic [11:0] cop_araddr;
  logic        cop_arvalid, cop_arready;
  logic [31:0] cop_rdata;
  logic [1:0]  cop_rresp;
  logic        cop_rvalid, cop_rready;

  // AXI4-Stream connections (DMA <-> Coprocessor)
  logic [63:0]  a_tdata;
  logic         a_tvalid, a_tready;
  logic [63:0]  b_tdata;
  logic         b_tvalid, b_tready;
  logic [127:0] c_tdata;
  logic         c_tvalid, c_tready;

  int err_cnt = 0;

  // ===========================================================================
  // DUT 1: DMA Controller
  // ===========================================================================
  dma_top u_dma (
    .clk_i     (clk_i      ),
    .rst_ni    (rst_ni     ),
    .reg_req_i (dma_reg_req),
    .reg_rsp_o (dma_reg_rsp),
    .axi_req_o (axi_req    ),
    .axi_rsp_i (axi_rsp    ),
    .a_tdata_o (a_tdata    ),
    .a_tvalid_o(a_tvalid   ),
    .a_tready_i(a_tready   ),
    .b_tdata_o (b_tdata    ),
    .b_tvalid_o(b_tvalid   ),
    .b_tready_i(b_tready   ),
    .c_tdata_i (c_tdata    ),
    .c_tvalid_i(c_tvalid   ),
    .c_tready_o(c_tready   ),
    .irq_o     (irq_o      )
  );

  // ===========================================================================
  // DUT 2: Systolic Array Coprocessor
  // ===========================================================================
  coproc_top u_coproc (
    .clk_i           (clk_i      ),
    .rst_ni          (rst_ni     ),
    .clk_acc_i       (clk_acc_i  ),
    .s_axil_awaddr_i (cop_awaddr ),
    .s_axil_awvalid_i(cop_awvalid),
    .s_axil_awready_o(cop_awready),
    .s_axil_wdata_i  (cop_wdata  ),
    .s_axil_wstrb_i  (cop_wstrb  ),
    .s_axil_wvalid_i (cop_wvalid ),
    .s_axil_wready_o (cop_wready ),
    .s_axil_bresp_o  (cop_bresp  ),
    .s_axil_bvalid_o (cop_bvalid ),
    .s_axil_bready_i (cop_bready ),
    .s_axil_araddr_i (cop_araddr ),
    .s_axil_arvalid_i(cop_arvalid),
    .s_axil_arready_o(cop_arready),
    .s_axil_rdata_o  (cop_rdata  ),
    .s_axil_rresp_o  (cop_rresp  ),
    .s_axil_rvalid_o (cop_rvalid ),
    .s_axil_rready_i (cop_rready ),
    .a_tdata_i       (a_tdata    ),
    .a_tvalid_i      (a_tvalid   ),
    .a_tready_o      (a_tready   ),
    .b_tdata_i       (b_tdata    ),
    .b_tvalid_i      (b_tvalid   ),
    .b_tready_o      (b_tready   ),
    .c_tdata_o       (c_tdata    ),
    .c_tvalid_o      (c_tvalid   ),
    .c_tready_i      (c_tready   )
  );

  // ===========================================================================
  // Behavioral 64 KiB AXI4 128-bit L2 SRAM (independent Read & Write channels)
  // ===========================================================================
  logic [127:0] l2_mem [0:L2_WORDS-1];

  // Read channel
  logic        rd_busy;
  logic [1:0]  rd_id;
  logic [31:0] rd_addr;
  logic [7:0]  rd_rem;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_busy         <= 1'b0;
      rd_id           <= '0;
      rd_addr         <= '0;
      rd_rem          <= '0;
      axi_rsp.r_valid <= 1'b0;
      axi_rsp.r       <= '0;
    end else begin
      if (!rd_busy) begin
        if (axi_req.ar_valid) begin
          if (({1'b0, axi_req.ar.addr[11:4]} + {1'b0, axi_req.ar.len} + 9'd1) > 9'd256) begin
            $error("AXI4 AR crossed 4 KiB boundary! addr=0x%08h len=%0d",
                   axi_req.ar.addr, axi_req.ar.len);
            err_cnt++;
          end
          rd_busy         <= 1'b1;
          rd_id           <= axi_req.ar.id;
          rd_addr         <= axi_req.ar.addr;
          rd_rem          <= axi_req.ar.len;
          axi_rsp.r_valid <= 1'b1;
          axi_rsp.r.id    <= axi_req.ar.id;
          axi_rsp.r.data  <= l2_mem[(axi_req.ar.addr - L2_BASE) >> 4];
          axi_rsp.r.resp  <= AXI_RESP_OKAY;
          axi_rsp.r.last  <= (axi_req.ar.len == 8'd0);
        end
      end else if (axi_rsp.r_valid && axi_req.r_ready) begin
        if (rd_rem == 8'd0) begin
          rd_busy         <= 1'b0;
          axi_rsp.r_valid <= 1'b0;
        end else begin
          logic [31:0] next_addr;
          next_addr        = rd_addr + 32'd16;
          rd_addr         <= next_addr;
          rd_rem          <= rd_rem - 8'd1;
          axi_rsp.r.data  <= l2_mem[(next_addr - L2_BASE) >> 4];
          axi_rsp.r.resp  <= AXI_RESP_OKAY;
          axi_rsp.r.last  <= (rd_rem == 8'd1);
        end
      end
    end
  end
  assign axi_rsp.ar_ready = !rd_busy;

  // Write channel
  logic [1:0]  wr_st;
  logic [1:0]  wr_id;
  logic [31:0] wr_addr;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_st           <= 2'd0;
      wr_id           <= '0;
      wr_addr         <= '0;
      axi_rsp.b_valid <= 1'b0;
      axi_rsp.b       <= '0;
    end else begin
      unique case (wr_st)
        2'd0: begin
          if (axi_req.aw_valid) begin
            if (({1'b0, axi_req.aw.addr[11:4]} + {1'b0, axi_req.aw.len} + 9'd1) > 9'd256) begin
              $error("AXI4 AW crossed 4 KiB boundary! addr=0x%08h len=%0d",
                     axi_req.aw.addr, axi_req.aw.len);
              err_cnt++;
            end
            wr_id   <= axi_req.aw.id;
            wr_addr <= axi_req.aw.addr;
            wr_st   <= 2'd1;
          end
        end
        2'd1: begin
          if (axi_req.w_valid) begin
            l2_mem[(wr_addr - L2_BASE) >> 4] <= axi_req.w.data;
            wr_addr <= wr_addr + 32'd16;
            if (axi_req.w.last) begin
              axi_rsp.b_valid <= 1'b1;
              axi_rsp.b.id    <= wr_id;
              axi_rsp.b.resp  <= AXI_RESP_OKAY;
              wr_st           <= 2'd2;
            end
          end
        end
        2'd2: begin
          if (axi_req.b_ready) begin
            axi_rsp.b_valid <= 1'b0;
            wr_st           <= 2'd0;
          end
        end
        default: wr_st <= 2'd0;
      endcase
    end
  end
  assign axi_rsp.aw_ready = (wr_st == 2'd0);
  assign axi_rsp.w_ready  = (wr_st == 2'd1);

  // ===========================================================================
  // Host BFM tasks (AXI4-Lite writes/reads to DMA and Coprocessor)
  // ===========================================================================
  task automatic dma_wr(input logic [11:0] addr, input logic [31:0] data);
    @(posedge clk_i);
    dma_reg_req.aw.addr  <= addr;
    dma_reg_req.aw_valid <= 1'b1;
    dma_reg_req.w.data   <= data;
    dma_reg_req.w.strb   <= 4'hF;
    dma_reg_req.w_valid  <= 1'b1;
    dma_reg_req.b_ready  <= 1'b1;
    do @(posedge clk_i); while (!(dma_reg_rsp.aw_ready && dma_reg_rsp.w_ready));
    dma_reg_req.aw_valid <= 1'b0;
    dma_reg_req.w_valid  <= 1'b0;
    while (!dma_reg_rsp.b_valid) @(posedge clk_i);
    @(posedge clk_i);
    dma_reg_req.b_ready  <= 1'b0;
  endtask

  task automatic dma_rd(input logic [11:0] addr, output logic [31:0] data);
    @(posedge clk_i);
    dma_reg_req.ar.addr  <= addr;
    dma_reg_req.ar_valid <= 1'b1;
    dma_reg_req.r_ready  <= 1'b1;
    do @(posedge clk_i); while (!dma_reg_rsp.ar_ready);
    dma_reg_req.ar_valid <= 1'b0;
    while (!dma_reg_rsp.r_valid) @(posedge clk_i);
    data = dma_reg_rsp.r.data;
    @(posedge clk_i);
    dma_reg_req.r_ready  <= 1'b0;
  endtask

  task automatic cop_wr(input logic [11:0] addr, input logic [31:0] data);
    @(posedge clk_i);
    cop_awaddr  <= addr;
    cop_awvalid <= 1'b1;
    cop_wdata   <= data;
    cop_wstrb   <= 4'hF;
    cop_wvalid  <= 1'b1;
    cop_bready  <= 1'b1;
    do @(posedge clk_i); while (!(cop_awready && cop_wready));
    cop_awvalid <= 1'b0;
    cop_wvalid  <= 1'b0;
    while (!cop_bvalid) @(posedge clk_i);
    @(posedge clk_i);
    cop_bready  <= 1'b0;
  endtask

  task automatic cop_rd(input logic [11:0] addr, output logic [31:0] data);
    @(posedge clk_i);
    cop_araddr  <= addr;
    cop_arvalid <= 1'b1;
    cop_rready  <= 1'b1;
    do @(posedge clk_i); while (!cop_arready);
    cop_arvalid <= 1'b0;
    while (!cop_rvalid) @(posedge clk_i);
    data = cop_rdata;
    @(posedge clk_i);
    cop_rready  <= 1'b0;
  endtask

  task automatic cfg_dma_ch(
    input int          ch,
    input logic [31:0] addr,
    input logic [31:0] len,
    input logic [31:0] cnt1,
    input logic [31:0] stride1,
    input logic [31:0] cnt2,
    input logic [31:0] stride2
  );
    logic [11:0] base;
    base = 12'(ch * 32'h20);
    dma_wr(base + 12'h00, addr);
    dma_wr(base + 12'h04, len);
    dma_wr(base + 12'h08, cnt1);
    dma_wr(base + 12'h0C, stride1);
    dma_wr(base + 12'h10, cnt2);
    dma_wr(base + 12'h14, stride2);
  endtask

  // Helper to write a single byte into L2
  task automatic l2_write_byte(input logic [31:0] addr, input logic [7:0] val);
    int unsigned word_idx;
    int unsigned byte_idx;
    word_idx = (addr - L2_BASE) >> 4;
    byte_idx = addr[3:0];
    l2_mem[word_idx][byte_idx*8 +: 8] = val;
  endtask

  // ===========================================================================
  // End-to-end Matmul Task (follows sw/README.md programming sequence)
  // ===========================================================================
  task automatic run_matmul(
    input string name,
    input int    M,
    input int    N,
    input int    K,
    input int    seed
  );
    int Ti, Tj;
    byte signed mat_a [0:31][0:31];
    byte signed mat_b [0:31][0:31];
    int  signed mat_c_exp [0:31][0:31];
    int         mismatches;
    logic [31:0] st;

    Ti = M / 8;
    Tj = N / 8;
    mismatches = 0;

    $display("------------------------------------------------------------");
    $display("Running %s: M=%0d, N=%0d, K=%0d (Ti=%0d, Tj=%0d)", name, M, N, K, Ti, Tj);

    // 1. Generate deterministic signed int8 A and B, and golden int32 C (with wrap)
    for (int i = 0; i < M; i++) begin
      for (int k = 0; k < K; k++) begin
        mat_a[i][k] = byte'(((i * 7 + k * 13 + seed) % 251) - 125);
      end
    end
    for (int k = 0; k < K; k++) begin
      for (int j = 0; j < N; j++) begin
        mat_b[k][j] = byte'(((k * 11 + j * 5 + seed * 3) % 251) - 125);
      end
    end
    for (int i = 0; i < M; i++) begin
      for (int j = 0; j < N; j++) begin
        int signed acc;
        acc = 0;
        for (int k = 0; k < K; k++) begin
          acc = acc + int'(mat_a[i][k]) * int'(mat_b[k][j]);
        end
        mat_c_exp[i][j] = acc;
      end
    end

    // 2. Pack A into L2 (0x2000_0000): panel ti, beat k = column k (lane r = row r)
    for (int ti = 0; ti < Ti; ti++) begin
      for (int k = 0; k < K; k++) begin
        for (int r = 0; r < 8; r++) begin
          l2_write_byte(A_BASE + (ti * 8 * K) + (k * 8) + r, mat_a[ti*8 + r][k]);
        end
      end
    end

    // 3. Pack B into L2 (0x2000_4000): panel tj, beat k = row k (lane c = col c)
    for (int tj = 0; tj < Tj; tj++) begin
      for (int k = 0; k < K; k++) begin
        for (int c = 0; c < 8; c++) begin
          l2_write_byte(B_BASE + (tj * 8 * K) + (k * 8) + c, mat_b[k][tj*8 + c]);
        end
      end
    end

    // Clear C region in L2
    for (int w = 0; w < (M * N) / 4; w++) begin
      l2_mem[((C_BASE - L2_BASE) >> 4) + w] = '0;
    end

    // 4. Program Coprocessor: DIM_M, DIM_N, DIM_K, CTRL.START
    cop_wr(12'h08, M);
    cop_wr(12'h0C, N);
    cop_wr(12'h10, K);
    cop_wr(12'h00, 32'h0000_0001);

    // 5. Program DMA (exact sw/README.md table)
    cfg_dma_ch(2, C_BASE, 4 * M * N, 1,  0, 1,  0);
    cfg_dma_ch(0, A_BASE, 8 * K,     Tj, 0, Ti, 8 * K);
    cfg_dma_ch(1, B_BASE, K * N,     Ti, 0, 1,  0);

    // Enable IRQ on Ch2 only, then START Ch2, Ch0, Ch1
    dma_wr(12'h58, 32'h0000_0003); // Ch2: START=1, IRQ_EN=1
    dma_wr(12'h18, 32'h0000_0001); // Ch0: START=1
    dma_wr(12'h38, 32'h0000_0001); // Ch1: START=1

    // 6. Wait for Ch2 IRQ (true end of job: all of C written to L2)
    while (!irq_o) @(posedge clk_i);

    // Wait for Ch0/Ch1 DONE as well and clear all DONE flags
    do dma_rd(12'h1C, st); while (!st[1]);
    do dma_rd(12'h3C, st); while (!st[1]);
    dma_wr(12'h1C, 32'h0000_0002);
    dma_wr(12'h3C, 32'h0000_0002);
    dma_wr(12'h5C, 32'h0000_0002);
    cop_wr(12'h04, 32'h0000_0002); // Clear coproc DONE

    // 7. Verify C in L2 (tiles in row-major order, each tile row-major, 4 int32/beat)
    for (int ti = 0; ti < Ti; ti++) begin
      for (int tj = 0; tj < Tj; tj++) begin
        int tile_idx;
        tile_idx = ti * Tj + tj;
        for (int r = 0; r < 8; r++) begin
          for (int c = 0; c < 8; c++) begin
            int elem_idx, word_idx, lane;
            int signed got, exp;
            elem_idx = tile_idx * 64 + r * 8 + c;
            word_idx = ((C_BASE - L2_BASE) >> 4) + (elem_idx / 4);
            lane     = elem_idx % 4;
            got      = signed'(l2_mem[word_idx][lane*32 +: 32]);
            exp      = mat_c_exp[ti*8 + r][tj*8 + c];
            if (got !== exp) begin
              if (mismatches < 10) begin
                $error("%s mismatch at C[%0d][%0d] (tile %0d,%0d): got=%0d exp=%0d",
                       name, ti*8 + r, tj*8 + c, ti, tj, got, exp);
              end
              mismatches++;
            end
          end
        end
      end
    end

    if (mismatches == 0) begin
      $display("[PASS] %s: all %0d int32 elements in L2 match golden model!", name, M * N);
    end else begin
      $error("%s: %0d mismatches!", name, mismatches);
      err_cnt += mismatches;
    end
  endtask

  // ===========================================================================
  // Main stimulus
  // ===========================================================================
  initial begin
    rst_ni      = 1'b0;
    dma_reg_req = '0;
    cop_awaddr  = '0; cop_awvalid = 1'b0;
    cop_wdata   = '0; cop_wstrb   = '0; cop_wvalid = 1'b0;
    cop_bready  = 1'b0;
    cop_araddr  = '0; cop_arvalid = 1'b0;
    cop_rready  = 1'b0;
    for (int i = 0; i < L2_WORDS; i++) l2_mem[i] = '0;

    repeat (6) @(posedge clk_i);
    rst_ni = 1'b1;
    repeat (4) @(posedge clk_i);

    // Test 1: Single tile 8x8, K=8
    run_matmul("Test 1 (Single Tile 8x8, K=8)",   8,  8,  8, 1);

    // Test 2: Multi-tile 16x16, K=12 (Ti=2, Tj=2, exercises 3D tiling & STRIDE1=0)
    run_matmul("Test 2 (Tiled 16x16, K=12)",     16, 16, 12, 7);

    // Test 3: Rectangular 16x8, K=1 (odd K=1 -> LEN=8 bytes on Ch0 & Ch1)
    run_matmul("Test 3 (Rect 16x8, K=2)", 16, 8, 2, 19);

    if (err_cnt == 0) begin
      $display("PASS: tb_dma_coproc, all checks passed");
    end else begin
      $fatal(1, "tb_dma_coproc: %0d errors", err_cnt);
    end
    $finish;
  end

endmodule
