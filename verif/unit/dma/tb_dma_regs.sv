// Unit testbench for dma_regs (DMA-01, DMA-06): register map, W1C, busy write protection, irq_o.
// Run: make sim TB=tb_dma_regs
//`timescale 1ns/1ps

module tb_dma_regs;
  import dma_pkg::*;

  logic                          clk_i;
  logic                          rst_ni;
  dma_axil_req_t                 reg_req_i;
  dma_axil_rsp_t                 reg_rsp_o;
  dma_ch_cfg_t [NUM_CHANNELS-1:0] ch_cfg_o;
  logic        [NUM_CHANNELS-1:0] ch_start_o;
  logic        [NUM_CHANNELS-1:0] ch_done_i;
  logic        [NUM_CHANNELS-1:0] ch_err_i;
  logic                          irq_o;

  int err_cnt = 0;

  dma_regs dut (
    .clk_i     (clk_i     ),
    .rst_ni    (rst_ni    ),
    .reg_req_i (reg_req_i ),
    .reg_rsp_o (reg_rsp_o ),
    .ch_cfg_o  (ch_cfg_o  ),
    .ch_start_o(ch_start_o),
    .ch_done_i (ch_done_i ),
    .ch_err_i  (ch_err_i  ),
    .irq_o     (irq_o     )
  );

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  // A handshake that never completes ends the run instead of hanging the regression.
  initial begin : watchdog
    #1ms;
    $fatal(1, "timeout: the test did not finish in 1 ms");
  end

  task automatic check(input string msg, input logic cond);
    if (!cond) begin
      $error("%s", msg);
      err_cnt++;
    end else begin
      $display("[PASS] %s", msg);
    end
  endtask

  task automatic axil_write(
    input  logic [11:0] addr,
    input  logic [31:0] data,
    input  logic [3:0]  strb,
    output logic [1:0]  resp
  );
    @(posedge clk_i);
    reg_req_i.aw.addr  <= addr;
    reg_req_i.aw_valid <= 1'b1;
    reg_req_i.w.data   <= data;
    reg_req_i.w.strb   <= strb;
    reg_req_i.w_valid  <= 1'b1;
    reg_req_i.b_ready  <= 1'b1;
    do @(posedge clk_i); while (!(reg_rsp_o.aw_ready && reg_rsp_o.w_ready));
    reg_req_i.aw_valid <= 1'b0;
    reg_req_i.w_valid  <= 1'b0;
    while (!reg_rsp_o.b_valid) @(posedge clk_i);
    resp = reg_rsp_o.b.resp;
    @(posedge clk_i);
    reg_req_i.b_ready  <= 1'b0;
  endtask

  task automatic axil_read(
    input  logic [11:0] addr,
    output logic [31:0] data,
    output logic [1:0]  resp
  );
    @(posedge clk_i);
    reg_req_i.ar.addr  <= addr;
    reg_req_i.ar_valid <= 1'b1;
    reg_req_i.r_ready  <= 1'b1;
    do @(posedge clk_i); while (!reg_rsp_o.ar_ready);
    reg_req_i.ar_valid <= 1'b0;
    while (!reg_rsp_o.r_valid) @(posedge clk_i);
    data = reg_rsp_o.r.data;
    resp = reg_rsp_o.r.resp;
    @(posedge clk_i);
    reg_req_i.r_ready  <= 1'b0;
  endtask

  initial begin
    logic [31:0] rdata;
    logic [1:0]  resp;

    rst_ni    = 1'b0;
    reg_req_i = '0;
    ch_done_i = '0;
    ch_err_i  = '0;

    repeat (3) @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);

    // 1. Write & Read across all 3 channels
    for (int c = 0; c < 3; c++) begin
      logic [11:0] base;
      base = 12'(c * 32'h20);
      axil_write(base + 12'h00, 32'h2000_0000 + (c << 14), 4'hF, resp);
      check($sformatf("Ch%0d ADDR write OKAY", c), resp == AXI_RESP_OKAY);
      axil_write(base + 12'h04, 32'h0000_0080 + c*16, 4'hF, resp);
      axil_read (base + 12'h00, rdata, resp);
      check($sformatf("Ch%0d ADDR readback", c), (resp == AXI_RESP_OKAY) && (rdata == (32'h2000_0000 + (c << 14))));
    end

    // 2. Partial WSTRB test on Ch0 LEN
    axil_write(12'h04, 32'h1234_5678, 4'b0011, resp);
    axil_read (12'h04, rdata, resp);
    check("Ch0 partial WSTRB (lower 2 bytes)", rdata == 32'h0000_5678);

    // 3. Out-of-map offset -> SLVERR
    axil_write(12'h60, 32'hDEAD_BEEF, 4'hF, resp);
    check("Out-of-map write returns SLVERR", resp == AXI_RESP_SLVERR);
    axil_read (12'h80, rdata, resp);
    check("Out-of-map read returns SLVERR", resp == AXI_RESP_SLVERR);

    // 4. START self-clearing, BUSY set, writes ignored while BUSY
    axil_write(12'h18, 32'h0000_0003, 4'hF, resp); // START=1, IRQ_EN=1 on Ch0
    axil_read (12'h18, rdata, resp);
    check("CTRL.START reads back as 0, IRQ_EN=1", rdata == 32'h0000_0002);
    axil_read (12'h1C, rdata, resp);
    check("STATUS.BUSY=1 after START", rdata == 32'h0000_0001);

    axil_write(12'h00, 32'hAAAA_0000, 4'hF, resp); // Should be ignored
    axil_read (12'h00, rdata, resp);
    check("ADDR write ignored while BUSY", rdata == 32'h2000_0000);

    // 5. DONE pulse -> BUSY=0, DONE=1, irq_o=1; W1C clears DONE and irq_o
    @(posedge clk_i);
    ch_done_i[0] <= 1'b1;
    @(posedge clk_i);
    ch_done_i[0] <= 1'b0;
    @(posedge clk_i);
    check("irq_o asserted on DONE with IRQ_EN=1", irq_o == 1'b1);
    axil_read(12'h1C, rdata, resp);
    check("STATUS.BUSY=0 and DONE=1", rdata == 32'h0000_0002);

    axil_write(12'h1C, 32'h0000_0002, 4'hF, resp); // W1C DONE
    @(posedge clk_i);
    check("irq_o deasserted after W1C DONE", irq_o == 1'b0);

    // 6. ERR pulse on Ch2 with IRQ_EN=1 -> irq_o=1; clearing IRQ_EN drops irq_o
    axil_write(12'h58, 32'h0000_0003, 4'hF, resp); // Ch2 START=1, IRQ_EN=1
    @(posedge clk_i);
    ch_err_i[2] <= 1'b1;
    @(posedge clk_i);
    ch_err_i[2] <= 1'b0;
    @(posedge clk_i);
    check("irq_o asserted on Ch2 ERR", irq_o == 1'b1);
    axil_write(12'h58, 32'h0000_0000, 4'hF, resp); // IRQ_EN=0
    @(posedge clk_i);
    check("irq_o deasserted when IRQ_EN cleared", irq_o == 1'b0);

    if (err_cnt == 0) begin
      $display("PASS: tb_dma_regs, all checks passed");
    end else begin
      $fatal(1, "tb_dma_regs: %0d errors", err_cnt);
    end
    $finish;
  end

endmodule
