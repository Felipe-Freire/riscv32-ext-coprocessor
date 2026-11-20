// Block testbench for dma_top against a behavioral AXI4 L2: stream unpacking, backpressure,
// the three channels together (sw/README.md pattern) with irq_o, and AXI error isolation.
// Run: make sim TB=tb_dma_top
//`timescale 1ns/1ps

module tb_dma_top;
  import dma_pkg::*;

  localparam logic [31:0] L2_BASE  = 32'h2000_0000;
  localparam int unsigned L2_WORDS = 4096; // 4096 * 16 bytes = 64 KiB

  logic                   clk_i;
  logic                   rst_ni;
  dma_axil_req_t          reg_req_i;
  dma_axil_rsp_t          reg_rsp_o;
  dma_axi_req_t           axi_req_o;
  dma_axi_rsp_t           axi_rsp_i;
  logic [AB_STREAM_W-1:0] a_tdata_o;
  logic                   a_tvalid_o;
  logic                   a_tready_i;
  logic [AB_STREAM_W-1:0] b_tdata_o;
  logic                   b_tvalid_o;
  logic                   b_tready_i;
  logic [C_STREAM_W-1:0]  c_tdata_i;
  logic                   c_tvalid_i;
  logic                   c_tready_o;
  logic                   irq_o;

  int err_cnt = 0;

  dma_top dut (
    .clk_i     (clk_i     ),
    .rst_ni    (rst_ni    ),
    .reg_req_i (reg_req_i ),
    .reg_rsp_o (reg_rsp_o ),
    .axi_req_o (axi_req_o ),
    .axi_rsp_i (axi_rsp_i ),
    .a_tdata_o (a_tdata_o ),
    .a_tvalid_o(a_tvalid_o),
    .a_tready_i(a_tready_i),
    .b_tdata_o (b_tdata_o ),
    .b_tvalid_o(b_tvalid_o),
    .b_tready_i(b_tready_i),
    .c_tdata_i (c_tdata_i ),
    .c_tvalid_i(c_tvalid_i),
    .c_tready_o(c_tready_o),
    .irq_o     (irq_o     )
  );

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  // A handshake that never completes ends the run instead of hanging the regression.
  initial begin : watchdog
    #1ms;
    $fatal(1, "timeout: the test did not finish in 1 ms");
  end

  // ===========================================================================
  // Behavioral 64 KiB AXI4 128-bit L2 SRAM slave (independent Read & Write)
  // ===========================================================================
  logic [127:0] l2_mem [0:L2_WORDS-1];
  logic         inject_rd_err = 1'b0;
  logic         inject_wr_err = 1'b0;
  logic [1:0]   inject_rd_id  = 2'd0;

  // Read slave state
  logic        rd_busy;
  logic [1:0]  rd_id;
  logic [31:0] rd_addr;
  logic [7:0]  rd_rem;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_busy          <= 1'b0;
      rd_id            <= '0;
      rd_addr          <= '0;
      rd_rem           <= '0;
      axi_rsp_i.r_valid <= 1'b0;
      axi_rsp_i.r       <= '0;
    end else begin
      if (!rd_busy) begin
        if (axi_req_o.ar_valid) begin
          // Protocol check: never cross 4 KiB boundary
          if (({1'b0, axi_req_o.ar.addr[11:4]} + {1'b0, axi_req_o.ar.len} + 9'd1) > 9'd256) begin
            $error("AXI4 AR crossed 4 KiB boundary! addr=0x%08h len=%0d",
                   axi_req_o.ar.addr, axi_req_o.ar.len);
            err_cnt++;
          end
          rd_busy           <= 1'b1;
          rd_id             <= axi_req_o.ar.id;
          rd_addr           <= axi_req_o.ar.addr;
          rd_rem            <= axi_req_o.ar.len;
          axi_rsp_i.r_valid <= 1'b1;
          axi_rsp_i.r.id    <= axi_req_o.ar.id;
          axi_rsp_i.r.data  <= l2_mem[(axi_req_o.ar.addr - L2_BASE) >> 4];
          axi_rsp_i.r.resp  <= (inject_rd_err && (axi_req_o.ar.id == inject_rd_id)) ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
          axi_rsp_i.r.last  <= (axi_req_o.ar.len == 8'd0);
        end
      end else if (axi_rsp_i.r_valid && axi_req_o.r_ready) begin
        if (rd_rem == 8'd0) begin
          rd_busy           <= 1'b0;
          axi_rsp_i.r_valid <= 1'b0;
        end else begin
          logic [31:0] next_addr;
          next_addr          = rd_addr + 32'd16;
          rd_addr           <= next_addr;
          rd_rem            <= rd_rem - 8'd1;
          axi_rsp_i.r.data  <= l2_mem[(next_addr - L2_BASE) >> 4];
          axi_rsp_i.r.resp  <= (inject_rd_err && (rd_id == inject_rd_id)) ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
          axi_rsp_i.r.last  <= (rd_rem == 8'd1);
        end
      end
    end
  end
  assign axi_rsp_i.ar_ready = !rd_busy;

  // Write slave state
  logic [1:0]  wr_st; // 0=IDLE, 1=DATA, 2=RESP
  logic [1:0]  wr_id;
  logic [31:0] wr_addr;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_st             <= 2'd0;
      wr_id             <= '0;
      wr_addr           <= '0;
      axi_rsp_i.b_valid <= 1'b0;
      axi_rsp_i.b       <= '0;
    end else begin
      unique case (wr_st)
        2'd0: begin
          if (axi_req_o.aw_valid) begin
            if (({1'b0, axi_req_o.aw.addr[11:4]} + {1'b0, axi_req_o.aw.len} + 9'd1) > 9'd256) begin
              $error("AXI4 AW crossed 4 KiB boundary! addr=0x%08h len=%0d",
                     axi_req_o.aw.addr, axi_req_o.aw.len);
              err_cnt++;
            end
            wr_id   <= axi_req_o.aw.id;
            wr_addr <= axi_req_o.aw.addr;
            wr_st   <= 2'd1;
          end
        end
        2'd1: begin
          if (axi_req_o.w_valid) begin
            if (!inject_wr_err) begin
              l2_mem[(wr_addr - L2_BASE) >> 4] <= axi_req_o.w.data;
            end
            wr_addr <= wr_addr + 32'd16;
            if (axi_req_o.w.last) begin
              axi_rsp_i.b_valid <= 1'b1;
              axi_rsp_i.b.id    <= wr_id;
              axi_rsp_i.b.resp  <= inject_wr_err ? AXI_RESP_DECERR : AXI_RESP_OKAY;
              wr_st             <= 2'd2;
            end
          end
        end
        2'd2: begin
          if (axi_req_o.b_ready) begin
            axi_rsp_i.b_valid <= 1'b0;
            wr_st             <= 2'd0;
          end
        end
        default: wr_st <= 2'd0;
      endcase
    end
  end
  assign axi_rsp_i.aw_ready = (wr_st == 2'd0);
  assign axi_rsp_i.w_ready  = (wr_st == 2'd1);

  // ===========================================================================
  // Helpers (AXI4-Lite & checks)
  // ===========================================================================
  task automatic check(input string msg, input logic cond);
    if (!cond) begin
      $error("%s", msg);
      err_cnt++;
    end else begin
      $display("[PASS] %s", msg);
    end
  endtask

  task automatic reg_wr(input logic [11:0] addr, input logic [31:0] data);
    @(posedge clk_i);
    reg_req_i.aw.addr  <= addr;
    reg_req_i.aw_valid <= 1'b1;
    reg_req_i.w.data   <= data;
    reg_req_i.w.strb   <= 4'hF;
    reg_req_i.w_valid  <= 1'b1;
    reg_req_i.b_ready  <= 1'b1;
    do @(posedge clk_i); while (!(reg_rsp_o.aw_ready && reg_rsp_o.w_ready));
    reg_req_i.aw_valid <= 1'b0;
    reg_req_i.w_valid  <= 1'b0;
    while (!reg_rsp_o.b_valid) @(posedge clk_i);
    @(posedge clk_i);
    reg_req_i.b_ready  <= 1'b0;
  endtask

  task automatic reg_rd(input logic [11:0] addr, output logic [31:0] data);
    @(posedge clk_i);
    reg_req_i.ar.addr  <= addr;
    reg_req_i.ar_valid <= 1'b1;
    reg_req_i.r_ready  <= 1'b1;
    do @(posedge clk_i); while (!reg_rsp_o.ar_ready);
    reg_req_i.ar_valid <= 1'b0;
    while (!reg_rsp_o.r_valid) @(posedge clk_i);
    data = reg_rsp_o.r.data;
    @(posedge clk_i);
    reg_req_i.r_ready  <= 1'b0;
  endtask

  task automatic cfg_channel(
    input int          ch,
    input logic [31:0] addr,
    input logic [31:0] len,
    input logic [31:0] cnt1,
    input logic [31:0] stride1,
    input logic [31:0] cnt2,
    input logic [31:0] stride2
  );
    logic [11:0] b;
    b = 12'(ch * 32'h20);
    reg_wr(b + 12'h00, addr);
    reg_wr(b + 12'h04, len);
    reg_wr(b + 12'h08, cnt1);
    reg_wr(b + 12'h0C, stride1);
    reg_wr(b + 12'h10, cnt2);
    reg_wr(b + 12'h14, stride2);
  endtask

  // Stream capture queues
  logic [63:0] a_q[$];
  logic [63:0] b_q[$];

  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (a_tvalid_o && a_tready_i) a_q.push_back(a_tdata_o);
      if (b_tvalid_o && b_tready_i) b_q.push_back(b_tdata_o);
    end
  end

  // ===========================================================================
  // Main test sequence (5 scenarios)
  // ===========================================================================
  initial begin
    logic [31:0] st;

    rst_ni     = 1'b0;
    reg_req_i  = '0;
    a_tready_i = 1'b1;
    b_tready_i = 1'b1;
    c_tdata_i  = '0;
    c_tvalid_i = 1'b0;
    for (int i = 0; i < L2_WORDS; i++) l2_mem[i] = '0;

    repeat (4) @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);

    // -------------------------------------------------------------------------
    // Scenario 1: 128->64 unpacking (low half first) + odd LEN=8 (K=1)
    // -------------------------------------------------------------------------
    $display("--- Scenario 1: 128->64 unpacking & LEN=8 ---");
    l2_mem[0] = {64'hAAAA_0001_0000_0001, 64'hBBBB_0001_0000_0000};
    l2_mem[1] = {64'hAAAA_0002_0000_0003, 64'hBBBB_0002_0000_0002};
    a_q.delete();

    cfg_channel(0, 32'h2000_0000, 32'd32, 32'd1, 32'd0, 32'd1, 32'd0);
    reg_wr(12'h18, 32'h0000_0001); // START Ch0
    do reg_rd(12'h1C, st); while (!st[1]);
    reg_wr(12'h1C, 32'h0000_0002); // W1C DONE

    check("S1: Ch0 produced 4 beats of 64b", a_q.size() == 4);
    check("S1: Low half sent first (beat 0)", a_q[0] == 64'hBBBB_0001_0000_0000);
    check("S1: High half sent second (beat 1)", a_q[1] == 64'hAAAA_0001_0000_0001);

    // Odd LEN=8 bytes (single 64-bit beat)
    a_q.delete();
    cfg_channel(0, 32'h2000_0000, 32'd8, 32'd1, 32'd0, 32'd1, 32'd0);
    reg_wr(12'h18, 32'h0000_0001);
    do reg_rd(12'h1C, st); while (!st[1]);
    reg_wr(12'h1C, 32'h0000_0002);
    check("S1: LEN=8 produced exactly 1 beat (low half)", (a_q.size() == 1) && (a_q[0] == 64'hBBBB_0001_0000_0000));

    // -------------------------------------------------------------------------
    // Scenario 2: Stream backpressure on Ch0
    // -------------------------------------------------------------------------
    $display("--- Scenario 2: Stream backpressure ---");
    a_q.delete();
    cfg_channel(0, 32'h2000_0000, 32'd32, 32'd1, 32'd0, 32'd1, 32'd0);
    a_tready_i <= 1'b0;
    reg_wr(12'h18, 32'h0000_0001);
    repeat (10) @(posedge clk_i);
    reg_rd(12'h1C, st);
    check("S2: DONE stays 0 while stream is stalled", st[1] == 1'b0);

    // Release with intermittent stalls
    for (int i = 0; i < 12; i++) begin
      a_tready_i <= (i % 2 == 0);
      @(posedge clk_i);
    end
    a_tready_i <= 1'b1;
    do reg_rd(12'h1C, st); while (!st[1]);
    reg_wr(12'h1C, 32'h0000_0002);
    check("S2: All 4 beats received intact under backpressure",
          (a_q.size() == 4) && (a_q[3] == 64'hAAAA_0002_0000_0003));

    // -------------------------------------------------------------------------
    // Scenario 3 & 4: Concurrent sw/README pattern (Ti=2, Tj=2, K=8) + IRQ
    //   Ch2 (C): 0x2000_8000, LEN=64B (4 beats of 128b), CNT1=1, CNT2=1, IRQ_EN=1
    //   Ch0 (A): 0x2000_0000, LEN=64B, CNT1=2 (STRIDE1=0), CNT2=2 (STRIDE2=64)
    //   Ch1 (B): 0x2000_4000, LEN=64B, CNT1=2 (STRIDE1=0), CNT2=1 (STRIDE2=0)
    // -------------------------------------------------------------------------
    $display("--- Scenario 3 & 4: Concurrent Ch0 + Ch1 + Ch2 (sw/README) ---");
    for (int i = 0; i < 8; i++) begin
      l2_mem[i]        = {64'(32'hA000 + i*2 + 1), 64'(32'hA000 + i*2)};
      l2_mem[1024 + i] = {64'(32'hB000 + i*2 + 1), 64'(32'hB000 + i*2)};
    end
    a_q.delete();
    b_q.delete();

    cfg_channel(2, 32'h2000_8000, 32'd64, 32'd1, 32'd0, 32'd1, 32'd0);
    cfg_channel(0, 32'h2000_0000, 32'd64, 32'd2, 32'd0, 32'd2, 32'd64);
    cfg_channel(1, 32'h2000_4000, 32'd64, 32'd2, 32'd0, 32'd1, 32'd0);

    // Start Ch2 first (with IRQ_EN=1), then Ch0 and Ch1
    reg_wr(12'h58, 32'h0000_0003);
    reg_wr(12'h18, 32'h0000_0001);
    reg_wr(12'h38, 32'h0000_0001);

    // Drive 4 beats of 128b into C stream concurrently
    for (int i = 0; i < 4; i++) begin
      @(posedge clk_i);
      c_tdata_i  <= {64'(32'hC100 + i), 64'(32'hC000 + i)};
      c_tvalid_i <= 1'b1;
      do @(posedge clk_i); while (!c_tready_o);
      c_tvalid_i <= 1'b0;
    end

    // Wait for Ch2 IRQ
    while (!irq_o) @(posedge clk_i);
    check("S3/4: irq_o asserted on Ch2 completion", irq_o == 1'b1);

    // Wait for Ch0 and Ch1 to finish too
    do reg_rd(12'h1C, st); while (!st[1]);
    do reg_rd(12'h3C, st); while (!st[1]);

    check("S3/4: Ch0 sent 32 beats (4 panels x 8 beats)", a_q.size() == 32);
    check("S3/4: Ch1 sent 16 beats (2 repeats x 8 beats)", b_q.size() == 16);
    check("S3/4: Ch2 wrote all 4 beats to L2 Bank 1 (0x2000_8000)",
          (l2_mem[2048] == {64'hC100, 64'hC000}) && (l2_mem[2051] == {64'hC103, 64'hC003}));

    // Clear all DONE bits
    reg_wr(12'h1C, 32'h0000_0002);
    reg_wr(12'h3C, 32'h0000_0002);
    reg_wr(12'h5C, 32'h0000_0002);
    @(posedge clk_i);
    check("S3/4: irq_o cleared after W1C", irq_o == 1'b0);

    // -------------------------------------------------------------------------
    // Scenario 5: AXI4 error injection (Ch0 fails, Ch1 still succeeds)
    // -------------------------------------------------------------------------
    $display("--- Scenario 5: AXI4 error isolation ---");
    a_q.delete();
    b_q.delete();
    inject_rd_err = 1'b1;
    inject_rd_id  = 2'd0; // Inject SLVERR only on Ch0

    cfg_channel(0, 32'h2000_0000, 32'd32, 32'd1, 32'd0, 32'd1, 32'd0);
    cfg_channel(1, 32'h2000_4000, 32'd32, 32'd1, 32'd0, 32'd1, 32'd0);
    reg_wr(12'h18, 32'h0000_0003); // Ch0 START + IRQ_EN
    reg_wr(12'h38, 32'h0000_0001); // Ch1 START

    while (!irq_o) @(posedge clk_i);
    reg_rd(12'h1C, st);
    check("S5: Ch0 stopped with ERR=1, BUSY=0, DONE=0", st == 32'h0000_0004);
    do reg_rd(12'h3C, st); while (!st[1]);
    check("S5: Ch1 unaffected and completed with DONE=1", (st == 32'h0000_0002) && (b_q.size() == 4));
    inject_rd_err = 1'b0;

    if (err_cnt == 0) begin
      $display("PASS: tb_dma_top, all checks passed");
    end else begin
      $fatal(1, "tb_dma_top: %0d errors", err_cnt);
    end
    $finish;
  end

endmodule
