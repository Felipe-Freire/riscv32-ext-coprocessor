// Integration testbench: bus_top + dma_top + coproc_top, the SoC without the core and the memories.
// An OBI driver on the core data port plays the core and runs the matrix multiplication sequence of
// sw/README.md, all through the interconnect:
//
//   1. DIM_M, DIM_N, DIM_K and CTRL.START of the coprocessor, over the control bus;
//   2. the three DMA channels (C, A, B), IRQ_EN on C only, START on C, A, B;
//   3. STATUS of channel 2 polled until DONE, with irq_o checked against it;
//   4. the DONE bits cleared, then every element of C loaded from bank 1 over the data bus.
//
// dma_top gets the bus types of soc_pkg; coproc_top has its AXI4-Lite signals tied to the fields of
// its peripheral port and runs clk_acc_i asynchronous to clk_i. The L2 banks are axi_sim_mem,
// loaded with A and B directly, with C poisoned before each run; the golden C is computed here and
// compared both in the bank and as the core reads it. Also checked:
//   - a read channel pointed outside the L2 (0x3000_0000, and the first byte past the L2) stops
//     with STATUS.ERR and raises irq_o until its ERR is cleared, and the next run is unaffected;
//   - at elaboration, that the widths of dma_pkg and coproc_pkg match the buses of soc_pkg.
//
// Run: make sim TB=tb_bus_dma_coproc [SEED=random] [PLUSARGS=+RAND=<random sizes>]
module tb_bus_dma_coproc;
  import soc_pkg::*;

  localparam time CyclTime    = 10ns;
  localparam time AccCyclTime = 7.3ns;  // array clock, asynchronous to clk_i
  localparam time ApplTime    = 2ns;
  localparam time TestTime    = 8ns;

  // Buffers of rtl/top/README.md#matrix-buffers-in-l2
  localparam axi_addr_t A_BASE = L2_BASE;
  localparam axi_addr_t B_BASE = L2_BASE + 32'h4000;
  localparam axi_addr_t C_BASE = L2_BASE + L2_BANK_SIZE;
  localparam int unsigned AB_BYTES = 32'h4000;
  localparam int unsigned C_BYTES  = L2_BANK_SIZE;

  // Coprocessor registers (rtl/coproc/README.md#registers)
  localparam axi_addr_t COP_CTRL   = COPROC_BASE + 32'h00;
  localparam axi_addr_t COP_STATUS = COPROC_BASE + 32'h04;
  localparam axi_addr_t COP_DIM_M  = COPROC_BASE + 32'h08;
  localparam axi_addr_t COP_DIM_N  = COPROC_BASE + 32'h0C;
  localparam axi_addr_t COP_DIM_K  = COPROC_BASE + 32'h10;

  localparam logic [7:0] Poison = 8'hA5;

  // ---- Static checks: the blocks were written against these widths -------------------------------

  if (dma_pkg::AXI_ID_W != AXI_ID_MST_W) begin : gen_check_id
    $fatal(1, "dma_pkg::AXI_ID_W = %0d, the data bus masters have %0d ID bits",
           dma_pkg::AXI_ID_W, AXI_ID_MST_W);
  end
  if (dma_pkg::AXI_ADDR_W != AXI_ADDR_W || dma_pkg::AXI_DATA_W != AXI_DATA_W) begin : gen_check_axi
    $fatal(1, "dma_pkg AXI4 port %0d/%0d bits (address/data), the data bus %0d/%0d",
           dma_pkg::AXI_ADDR_W, dma_pkg::AXI_DATA_W, AXI_ADDR_W, AXI_DATA_W);
  end
  if (dma_pkg::AXIL_DATA_W != AXIL_DATA_W || (1 << dma_pkg::AXIL_ADDR_W) != PERIPH_SIZE)
  begin : gen_check_axil
    $fatal(1, "dma_pkg register port: %0d data bits and a %0d-byte window, the control bus %0d and %0d",
           dma_pkg::AXIL_DATA_W, 1 << dma_pkg::AXIL_ADDR_W, AXIL_DATA_W, PERIPH_SIZE);
  end
  if (dma_pkg::AB_STREAM_W != coproc_pkg::ARRAY_DIM * coproc_pkg::DATA_W) begin : gen_check_ab
    $fatal(1, "A/B streams: the DMA sends %0d bits, the array takes %0d", dma_pkg::AB_STREAM_W,
           coproc_pkg::ARRAY_DIM * coproc_pkg::DATA_W);
  end

  // ---- Clocks, reset, checks ---------------------------------------------------------------------

  logic clk, clk_acc, rst_n;

  clk_rst_gen #(
    .ClkPeriod   (CyclTime),
    .RstClkCycles(5       )
  ) u_clk_rst (
    .clk_o (clk  ),
    .rst_no(rst_n)
  );

  clk_rst_gen #(
    .ClkPeriod   (AccCyclTime),
    .RstClkCycles(5          )
  ) u_clk_acc (
    .clk_o (clk_acc),
    .rst_no(       )
  );

  int unsigned checks = 0;
  int unsigned errors = 0;

  function automatic void check(input bit cond, input string msg);
    checks++;
    if (!cond) begin
      errors++;
      $error("%s", msg);
    end
  endfunction

  initial begin : watchdog
    #100ms;
    $fatal(1, "timeout: the test did not finish in 100 ms");
  end

  // ================================================================================================
  // DUT: interconnect, DMA, coprocessor, L2 banks
  // ================================================================================================

  obi_req_t     core_req;
  obi_rsp_t     core_rsp;
  obi_req_t     dtcm_req;
  axi_mst_req_t dma_req;
  axi_mst_rsp_t dma_rsp;
  axi_slv_req_t [DATA_NUM_SLV-1:0] l2_req;
  axi_slv_rsp_t [DATA_NUM_SLV-1:0] l2_rsp;
  axil_req_t    [CTRL_NUM_SLV-1:0] periph_req;
  axil_rsp_t    [CTRL_NUM_SLV-1:0] periph_rsp;

  logic irq;

  bus_top u_bus (
    .clk_i       (clk       ),
    .rst_ni      (rst_n     ),
    .core_req_i  (core_req  ),
    .core_rsp_o  (core_rsp  ),
    .dtcm_req_o  (dtcm_req  ),
    .dtcm_rsp_i  ('0        ),
    .dma_req_i   (dma_req   ),
    .dma_rsp_o   (dma_rsp   ),
    .l2_req_o    (l2_req    ),
    .l2_rsp_i    (l2_rsp    ),
    .periph_req_o(periph_req),
    .periph_rsp_i(periph_rsp)
  );

  // No timer and no D-TCM yet: nothing may reach them.
  assign periph_rsp[CTRL_SLV_TIMER] = '0;

  always @(posedge clk) begin : unused_ports
    if (rst_n) begin
      if (dtcm_req.req) check(1'b0, "an access reached the D-TCM port");
      if (periph_req[CTRL_SLV_TIMER].aw_valid || periph_req[CTRL_SLV_TIMER].ar_valid) begin
        check(1'b0, "an access reached the timer port");
      end
    end
  end

  logic [dma_pkg::AB_STREAM_W-1:0] a_tdata, b_tdata;
  logic [dma_pkg::C_STREAM_W-1:0]  c_tdata;
  logic a_tvalid, a_tready, b_tvalid, b_tready, c_tvalid, c_tready;

  dma_top #(
    .reg_req_t(axil_req_t   ),
    .reg_rsp_t(axil_rsp_t   ),
    .axi_req_t(axi_mst_req_t),
    .axi_rsp_t(axi_mst_rsp_t)
  ) u_dma (
    .clk_i     (clk                     ),
    .rst_ni    (rst_n                   ),
    .reg_req_i (periph_req[CTRL_SLV_DMA]),
    .reg_rsp_o (periph_rsp[CTRL_SLV_DMA]),
    .axi_req_o (dma_req                 ),
    .axi_rsp_i (dma_rsp                 ),
    .a_tdata_o (a_tdata                 ),
    .a_tvalid_o(a_tvalid                ),
    .a_tready_i(a_tready                ),
    .b_tdata_o (b_tdata                 ),
    .b_tvalid_o(b_tvalid                ),
    .b_tready_i(b_tready                ),
    .c_tdata_i (c_tdata                 ),
    .c_tvalid_i(c_tvalid                ),
    .c_tready_o(c_tready                ),
    .irq_o     (irq                     )
  );

  // The coprocessor register port has separate AXI4-Lite signals and a 12-bit address.
  axil_req_t cop_req;
  axil_rsp_t cop_rsp;

  assign cop_req                     = periph_req[CTRL_SLV_COPROC];
  assign periph_rsp[CTRL_SLV_COPROC] = cop_rsp;

  coproc_top #(
    .CDataWidth(dma_pkg::C_STREAM_W)
  ) u_coproc (
    .clk_i           (clk                  ),
    .rst_ni          (rst_n                ),
    .clk_acc_i       (clk_acc              ),
    .s_axil_awaddr_i (cop_req.aw.addr[11:0]),
    .s_axil_awvalid_i(cop_req.aw_valid     ),
    .s_axil_awready_o(cop_rsp.aw_ready     ),
    .s_axil_wdata_i  (cop_req.w.data       ),
    .s_axil_wstrb_i  (cop_req.w.strb       ),
    .s_axil_wvalid_i (cop_req.w_valid      ),
    .s_axil_wready_o (cop_rsp.w_ready      ),
    .s_axil_bresp_o  (cop_rsp.b.resp       ),
    .s_axil_bvalid_o (cop_rsp.b_valid      ),
    .s_axil_bready_i (cop_req.b_ready      ),
    .s_axil_araddr_i (cop_req.ar.addr[11:0]),
    .s_axil_arvalid_i(cop_req.ar_valid     ),
    .s_axil_arready_o(cop_rsp.ar_ready     ),
    .s_axil_rdata_o  (cop_rsp.r.data       ),
    .s_axil_rresp_o  (cop_rsp.r.resp       ),
    .s_axil_rvalid_o (cop_rsp.r_valid      ),
    .s_axil_rready_i (cop_req.r_ready      ),
    .a_tdata_i       (a_tdata              ),
    .a_tvalid_i      (a_tvalid             ),
    .a_tready_o      (a_tready             ),
    .b_tdata_i       (b_tdata              ),
    .b_tvalid_i      (b_tvalid             ),
    .b_tready_o      (b_tready             ),
    .c_tdata_o       (c_tdata              ),
    .c_tvalid_o      (c_tvalid             ),
    .c_tready_i      (c_tready             )
  );

  for (genvar b = 0; b < DATA_NUM_SLV; b++) begin : gen_bank
    axi_sim_mem #(
      .AddrWidth        (AXI_ADDR_W   ),
      .DataWidth        (AXI_DATA_W   ),
      .IdWidth          (AXI_ID_SLV_W ),
      .UserWidth        (AXI_USER_W   ),
      .NumPorts         (1            ),
      .axi_req_t        (axi_slv_req_t),
      .axi_rsp_t        (axi_slv_rsp_t),
      .UninitializedData("undefined"  ),
      .ApplDelay        (ApplTime     ),
      .AcqDelay         (TestTime     )
    ) u_mem (
      .clk_i             (clk      ),
      .rst_ni            (rst_n    ),
      .axi_req_i         (l2_req[b]),
      .axi_rsp_o         (l2_rsp[b]),
      .mon_w_valid_o     (         ),
      .mon_w_addr_o      (         ),
      .mon_w_data_o      (         ),
      .mon_w_id_o        (         ),
      .mon_w_user_o      (         ),
      .mon_w_beat_count_o(         ),
      .mon_w_last_o      (         ),
      .mon_r_valid_o     (         ),
      .mon_r_addr_o      (         ),
      .mon_r_data_o      (         ),
      .mon_r_id_o        (         ),
      .mon_r_user_o      (         ),
      .mon_r_beat_count_o(         ),
      .mon_r_last_o      (         )
    );
  end

  // Direct access to the banks.
  function automatic void l2_poke(input axi_addr_t addr, input logic [7:0] value);
    if (addr < L2_BASE + L2_BANK_SIZE) gen_bank[DATA_SLV_L2_BANK0].u_mem.mem[addr] = value;
    else                               gen_bank[DATA_SLV_L2_BANK1].u_mem.mem[addr] = value;
  endfunction

  function automatic logic [7:0] l2_peek(input axi_addr_t addr);
    if (addr < L2_BASE + L2_BANK_SIZE) return gen_bank[DATA_SLV_L2_BANK0].u_mem.mem[addr];
    else                               return gen_bank[DATA_SLV_L2_BANK1].u_mem.mem[addr];
  endfunction

  // ================================================================================================
  // Core: one OBI access at a time, entered and left ApplTime after a clock edge
  // ================================================================================================

  typedef logic [31:0] word_t;

  task automatic obi_access(input bit we, input axi_addr_t addr, input word_t wdata,
                            output word_t rdata, output bit err);
    core_req = '{req: 1'b1, addr: addr, we: we, be: 4'hF, wdata: wdata};
    #(TestTime - ApplTime);
    while (!core_rsp.gnt) begin
      @(posedge clk);
      #(TestTime);
    end
    @(posedge clk);
    #(ApplTime);
    core_req = '0;
    #(TestTime - ApplTime);
    while (!core_rsp.rvalid) begin
      @(posedge clk);
      #(TestTime);
    end
    rdata = core_rsp.rdata;
    err   = core_rsp.err;
    @(posedge clk);
    #(ApplTime);
  endtask

  task automatic store(input axi_addr_t addr, input word_t data);
    word_t rdata;
    bit    err;
    obi_access(1'b1, addr, data, rdata, err);
    check(!err, $sformatf("store 0x%08h: access fault", addr));
  endtask

  task automatic load(input axi_addr_t addr, output word_t data);
    bit err;
    obi_access(1'b0, addr, '0, data, err);
    check(!err, $sformatf("load 0x%08h: access fault", addr));
  endtask

  // DMA registers of channel ch (rtl/dma/README.md#registers)
  function automatic axi_addr_t dma_reg(input int unsigned ch, input logic [4:0] off);
    return DMA_BASE + ch * 32'h20 + off;
  endfunction

  task automatic dma_config(input int unsigned ch, input word_t addr, input word_t len,
                            input word_t cnt1, input word_t stride1, input word_t cnt2,
                            input word_t stride2);
    store(dma_reg(ch, dma_pkg::REG_ADDR),    addr);
    store(dma_reg(ch, dma_pkg::REG_LEN),     len);
    store(dma_reg(ch, dma_pkg::REG_CNT1),    cnt1);
    store(dma_reg(ch, dma_pkg::REG_STRIDE1), stride1);
    store(dma_reg(ch, dma_pkg::REG_CNT2),    cnt2);
    store(dma_reg(ch, dma_pkg::REG_STRIDE2), stride2);
  endtask

  // ================================================================================================
  // Matrix multiplication, the sequence of sw/README.md
  // ================================================================================================

  localparam word_t CtrlStart = 32'h1 << dma_pkg::CTRL_START_BIT;
  localparam word_t CtrlIrqEn = 32'h1 << dma_pkg::CTRL_IRQ_EN_BIT;
  localparam word_t StatBusy  = 32'h1 << dma_pkg::STAT_BUSY_BIT;
  localparam word_t StatDone  = 32'h1 << dma_pkg::STAT_DONE_BIT;
  localparam word_t StatErr   = 32'h1 << dma_pkg::STAT_ERR_BIT;

  int unsigned runs = 0;

  task automatic matmul(input int unsigned m, input int unsigned n, input int unsigned k);
    int unsigned ti, tj, cycles;
    byte         a [][];
    byte         b [][];
    int          c [][];
    word_t       st, rdata;
    longint      start;
    int unsigned bad_l2 = 0, bad_core = 0;

    ti = m / 8;
    tj = n / 8;
    check(m % 8 == 0 && n % 8 == 0 && k % 8 == 0 && m * k <= AB_BYTES && k * n <= AB_BYTES &&
          4 * m * n <= C_BYTES, $sformatf("matmul %0dx%0dx%0d does not fit the buffers", m, n, k));

    // Random int8 A and B, golden int32 C (wrapping, like the array)
    a = new[m];
    foreach (a[i]) begin
      a[i] = new[k];
      foreach (a[i][kk]) a[i][kk] = byte'($urandom);
    end
    b = new[k];
    foreach (b[kk]) begin
      b[kk] = new[n];
      foreach (b[kk][j]) b[kk][j] = byte'($urandom);
    end
    c = new[m];
    foreach (c[i]) begin
      c[i] = new[n];
      foreach (c[i][j]) begin
        c[i][j] = 0;
        for (int kk = 0; kk < k; kk++) c[i][j] += int'(a[i][kk]) * int'(b[kk][j]);
      end
    end

    // L2 in the coprocessor layout (rtl/coproc/README.md#matrix-layout); C and the 64 bytes after
    // it poisoned, so a missing or extra write shows.
    for (int i = 0; i < m; i++) begin
      for (int kk = 0; kk < k; kk++) l2_poke(A_BASE + 8 * k * (i / 8) + 8 * kk + i % 8, a[i][kk]);
    end
    for (int kk = 0; kk < k; kk++) begin
      for (int j = 0; j < n; j++) l2_poke(B_BASE + 8 * k * (j / 8) + 8 * kk + j % 8, b[kk][j]);
    end
    for (int unsigned i = 0; i < 4 * m * n + 64 && i < C_BYTES; i++) l2_poke(C_BASE + i, Poison);

    // 1. Coprocessor
    store(COP_DIM_M, m);
    store(COP_DIM_N, n);
    store(COP_DIM_K, k);
    store(COP_CTRL, 32'h1);

    // 2. DMA: C, A, B; IRQ_EN on C only; START on C, A, B
    check(!irq, "irq_o high before the DMA starts");
    dma_config(dma_pkg::CH_C, C_BASE, 4 * m * n, 1,  0, 1,  0);
    dma_config(dma_pkg::CH_A, A_BASE, 8 * k,     tj, 0, ti, 8 * k);
    dma_config(dma_pkg::CH_B, B_BASE, k * n,     ti, 0, 1,  0);
    start = $time / CyclTime;
    store(dma_reg(dma_pkg::CH_C, dma_pkg::REG_CTRL), CtrlIrqEn | CtrlStart);
    store(dma_reg(dma_pkg::CH_A, dma_pkg::REG_CTRL), CtrlStart);
    store(dma_reg(dma_pkg::CH_B, dma_pkg::REG_CTRL), CtrlStart);

    // 3. Poll channel 2; then irq_o is high, and A and B are done
    do begin
      load(dma_reg(dma_pkg::CH_C, dma_pkg::REG_STATUS), st);
      check(!(st & StatErr), $sformatf("matmul %0dx%0dx%0d: channel 2 ERR", m, n, k));
    end while (!(st & (StatDone | StatErr)));
    cycles = $time / CyclTime - start;
    check(irq, "irq_o low with channel 2 done and IRQ_EN set");
    for (int ch = 0; ch < 2; ch++) begin
      load(dma_reg(ch, dma_pkg::REG_STATUS), st);
      check(st == StatDone, $sformatf("channel %0d STATUS 0x%0h after channel 2, expected DONE", ch,
                                      st));
    end
    load(COP_STATUS, st);
    check(st == 32'h2, $sformatf("coprocessor STATUS 0x%0h after the run, expected DONE", st));

    // 4. Clear the DONE bits, then read C
    for (int ch = 0; ch < dma_pkg::NUM_CHANNELS; ch++) begin
      store(dma_reg(ch, dma_pkg::REG_STATUS), StatDone);
    end
    store(COP_STATUS, 32'h2);
    check(!irq, "irq_o still high after DONE was cleared");
    load(COP_STATUS, st);
    check(st == 32'h0, $sformatf("coprocessor STATUS 0x%0h after the clear", st));

    // C in bank 1, element by element; then the 64 bytes after it, untouched.
    for (int i = 0; i < m; i++) begin
      for (int j = 0; j < n; j++) begin
        axi_addr_t addr;
        word_t     got;
        addr = C_BASE + 256 * ((i / 8) * tj + j / 8) + 4 * (8 * (i % 8) + j % 8);
        for (int by = 0; by < 4; by++) got[8*by +: 8] = l2_peek(addr + by);
        if (got !== c[i][j]) begin
          bad_l2++;
          if (bad_l2 <= 5) begin
            check(1'b0, $sformatf("matmul %0dx%0dx%0d: C[%0d][%0d] in L2 is %0d, expected %0d",
                                  m, n, k, i, j, $signed(got), c[i][j]));
          end
        end
        load(addr, rdata);
        if (rdata !== c[i][j]) begin
          bad_core++;
          if (bad_core <= 5) begin
            check(1'b0, $sformatf("matmul %0dx%0dx%0d: core loads C[%0d][%0d] = %0d, expected %0d",
                                  m, n, k, i, j, $signed(rdata), c[i][j]));
          end
        end
      end
    end
    check(bad_l2 == 0 && bad_core == 0,
          $sformatf("matmul %0dx%0dx%0d: %0d elements wrong in L2, %0d as loaded by the core",
                    m, n, k, bad_l2, bad_core));
    for (int unsigned i = 4 * m * n; i < 4 * m * n + 64 && i < C_BYTES; i++) begin
      check(l2_peek(C_BASE + i) === Poison,
            $sformatf("matmul %0dx%0dx%0d: byte 0x%0h past C was written", m, n, k, i));
    end

    runs++;
    $display("matmul %3dx%3dx%4d: %6d cycles from the DMA start to channel 2 DONE, C checked",
             m, n, k, cycles);
  endtask

  // ================================================================================================
  // DMA error: read channels pointed outside the L2
  // ================================================================================================

  // Channel A at 0x3000_0000 (no window), channel B at the first byte past the L2. Both get DECERR
  // from the data crossbar, stop with ERR and hold irq_o (IRQ_EN set) until their ERR is cleared.
  // The error beats are dropped, so nothing reaches the coprocessor.
  task automatic dma_error();
    word_t st;
    dma_config(dma_pkg::CH_A, 32'h3000_0000,     64, 1, 0, 1, 0);
    dma_config(dma_pkg::CH_B, L2_BASE + L2_SIZE, 64, 1, 0, 1, 0);
    store(dma_reg(dma_pkg::CH_A, dma_pkg::REG_CTRL), CtrlIrqEn | CtrlStart);
    store(dma_reg(dma_pkg::CH_B, dma_pkg::REG_CTRL), CtrlIrqEn | CtrlStart);
    for (int ch = 0; ch < 2; ch++) begin
      do load(dma_reg(ch, dma_pkg::REG_STATUS), st); while (st & StatBusy);
      check(st == StatErr, $sformatf("channel %0d outside the L2: STATUS 0x%0h, expected ERR", ch,
                                     st));
    end
    check(irq, "irq_o low with two channels in ERR");
    store(dma_reg(dma_pkg::CH_A, dma_pkg::REG_STATUS), StatErr);
    check(irq, "irq_o low with channel B still in ERR");
    store(dma_reg(dma_pkg::CH_B, dma_pkg::REG_STATUS), StatErr);
    check(!irq, "irq_o high with every ERR cleared");
    for (int ch = 0; ch < 2; ch++) begin
      load(dma_reg(ch, dma_pkg::REG_STATUS), st);
      check(st == '0, $sformatf("channel %0d STATUS 0x%0h after the clear", ch, st));
    end
    $display("DMA reads outside the L2: ERR on both channels, irq_o until both were cleared");
  endtask

  // ================================================================================================
  // Main
  // ================================================================================================

  int unsigned num_rand = 2;

  initial begin : main
    core_req = '0;
    void'($value$plusargs("RAND=%d", num_rand));
    @(posedge rst_n);
    repeat (2) @(posedge clk);
    #(ApplTime);

    matmul(8, 8, 8);         // one tile
    matmul(16, 24, 16);      // 2 x 3 tiles, A panels sent three times
    dma_error();
    matmul(32, 32, 64);      // after the error: nothing left behind
    matmul(8, 8, 2048);      // the longest K the A and B buffers hold
    matmul(64, 128, 128);    // C fills bank 1, B its buffer
    repeat (num_rand) begin
      int unsigned m, n, k, kmax;
      m    = 8 * $urandom_range(1, 8);
      n    = 8 * $urandom_range(1, C_BYTES / (4 * 8 * m));
      kmax = AB_BYTES / (m > n ? m : n);
      k    = 8 * $urandom_range(1, (kmax < 256 ? kmax : 256) / 8);
      matmul(m, n, k);
    end

    if (errors == 0) begin
      $display("PASS: %0d checks, %0d matrix multiplications through bus_top", checks, runs);
    end else begin
      $fatal(1, "%0d of %0d checks failed", errors, checks);
    end
    $finish;
  end

endmodule
