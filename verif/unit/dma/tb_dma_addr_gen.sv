
//`timescale 1ns/1ps

module tb_dma_addr_gen;
  import dma_pkg::*;

  logic        clk_i;
  logic        rst_ni;
  logic        start_i;
  logic        abort_i;
  dma_ch_cfg_t cfg_i;
  logic        cmd_valid_o;
  logic        cmd_ready_i;
  logic [31:0] cmd_addr_o;
  logic [7:0]  cmd_len_o;
  logic        cmd_last_o;

  int err_cnt = 0;

  dma_addr_gen #(
    .MaxBurstBeats(16)
  ) dut (
    .clk_i      (clk_i      ),
    .rst_ni     (rst_ni     ),
    .start_i    (start_i    ),
    .abort_i    (abort_i    ),
    .cfg_i      (cfg_i      ),
    .cmd_valid_o(cmd_valid_o),
    .cmd_ready_i(cmd_ready_i),
    .cmd_addr_o (cmd_addr_o ),
    .cmd_len_o  (cmd_len_o  ),
    .cmd_last_o (cmd_last_o )
  );

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  task automatic check(input string msg, input logic cond);
    if (!cond) begin
      $display("[FAIL] %s (t=%0t)", msg, $time);
      err_cnt++;
    end else begin
      $display("[PASS] %s", msg);
    end
  endtask

  task automatic expect_cmd(
    input string       tag,
    input logic [31:0] exp_addr,
    input logic [7:0]  exp_len,
    input logic        exp_last
  );
    while (!cmd_valid_o) @(posedge clk_i);
    check($sformatf("%s: addr=0x%08h (exp 0x%08h), len=%0d (exp %0d), last=%0b (exp %0b)",
                    tag, cmd_addr_o, exp_addr, cmd_len_o, exp_len, cmd_last_o, exp_last),
          (cmd_addr_o == exp_addr) && (cmd_len_o == exp_len) && (cmd_last_o == exp_last));
    cmd_ready_i <= 1'b1;
    @(posedge clk_i);
    cmd_ready_i <= 1'b0;
    @(posedge clk_i);
  endtask

  initial begin
    rst_ni      = 1'b0;
    start_i     = 1'b0;
    abort_i     = 1'b0;
    cfg_i       = '0;
    cmd_ready_i = 1'b0;

    repeat (3) @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);

    // -------------------------------------------------------------------------
    // Test 1: 4 KiB boundary crossing (ADDR=0x2000_0FC0, LEN=256 bytes = 16 beats)
    // Expect Burst 1: 0x2000_0FC0, 4 beats (len=3), last=0
    // Expect Burst 2: 0x2000_1000, 12 beats (len=11), last=1
    // -------------------------------------------------------------------------
    cfg_i.addr    = 32'h2000_0FC0;
    cfg_i.len     = 32'd256;
    cfg_i.cnt1    = 32'd1;
    cfg_i.stride1 = 32'd0;
    cfg_i.cnt2    = 32'd1;
    cfg_i.stride2 = 32'd0;

    start_i <= 1'b1;
    @(posedge clk_i);
    start_i <= 1'b0;

    expect_cmd("4KiB split burst 1", 32'h2000_0FC0, 8'd3,  1'b0);
    expect_cmd("4KiB split burst 2", 32'h2000_1000, 8'd11, 1'b1);
    check("Idle after 4KiB test", cmd_valid_o == 1'b0);

    // -------------------------------------------------------------------------
    // Test 2: 3D tiling (sw/README Ch0 pattern: Ti=2, Tj=2, K=8 -> LEN=64B)
    // STRIDE1=0 repeats row twice; STRIDE2=64 advances plane
    // -------------------------------------------------------------------------
    cfg_i.addr    = 32'h2000_0000;
    cfg_i.len     = 32'd64;  // 4 beats (len=3)
    cfg_i.cnt1    = 32'd2;
    cfg_i.stride1 = 32'd0;
    cfg_i.cnt2    = 32'd2;
    cfg_i.stride2 = 32'd64;

    start_i <= 1'b1;
    @(posedge clk_i);
    start_i <= 1'b0;

    expect_cmd("3D p=0 r=0", 32'h2000_0000, 8'd3, 1'b0);
    expect_cmd("3D p=0 r=1 (stride1=0)", 32'h2000_0000, 8'd3, 1'b0);
    expect_cmd("3D p=1 r=0 (stride2=64)", 32'h2000_0040, 8'd3, 1'b0);
    expect_cmd("3D p=1 r=1 (last)", 32'h2000_0040, 8'd3, 1'b1);
    check("Idle after 3D test", cmd_valid_o == 1'b0);

    // -------------------------------------------------------------------------
    // Test 3: Abort mid-transfer
    // -------------------------------------------------------------------------
    cfg_i.addr    = 32'h2000_4000;
    cfg_i.len     = 32'd64;
    cfg_i.cnt1    = 32'd4;
    cfg_i.stride1 = 32'd64;
    cfg_i.cnt2    = 32'd1;
    cfg_i.stride2 = 32'd0;

    start_i <= 1'b1;
    @(posedge clk_i);
    start_i <= 1'b0;
    expect_cmd("Abort test burst 1", 32'h2000_4000, 8'd3, 1'b0);

    abort_i <= 1'b1;
    @(posedge clk_i);
    abort_i <= 1'b0;
    @(posedge clk_i);
    check("cmd_valid_o drops immediately after abort", cmd_valid_o == 1'b0);

    $display("========================================");
    if (err_cnt == 0)
      $display("TB_DMA_ADDR_GEN: PASSED (0 errors)");
    else
      $display("TB_DMA_ADDR_GEN: FAILED (%0d errors)", err_cnt);
    $display("========================================");
    $finish;
  end

endmodule
