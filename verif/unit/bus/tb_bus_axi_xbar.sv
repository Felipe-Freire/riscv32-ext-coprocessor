// Testbench for bus_axi_xbar, the 2x2 AXI4 crossbar of the data bus. Two instances of the DUT run
// side by side:
//
//   u_dut_rand  Random traffic. An axi_test::axi_rand_master on each master port issues reads and
//               writes (INCR and FIXED bursts of up to 16 beats, any size, random IDs and delays)
//               to the L2 and to unmapped space on both sides of it, and an axi_test::
//               axi_rand_slave on each bank answers with random delays. The upstream
//               axi_xbar_monitor (vendor/axi/test/tb_axi_xbar_pkg.sv) checks that every AW and AR
//               reaches the bank its address maps to with the master index prepended to its ID,
//               that the W beats follow their AW, and that every B and R, those of unmapped
//               addresses included, gets back to its master with its ID.
//   u_dut_dir   Directed, against axi_sim_mem banks: data written by one master and read back by
//               the other through both banks, DECERR outside the L2 without reaching a bank, and a
//               read of bank 0 running at the same time as a write to bank 1, which is why the L2
//               has two banks.
//
// Run: make sim TB=tb_bus_axi_xbar [SEED=random] [PLUSARGS=+TXNS=<reads and writes per master>]
`include "axi/assign.svh"

module tb_bus_axi_xbar;
  import soc_pkg::*;

  localparam time CyclTime = 10ns;
  localparam time ApplTime = 2ns;   // stimuli change this long after the clock edge
  localparam time TestTime = 8ns;   // and are sampled this long after it

  localparam int unsigned BurstBeats = 16;  // the longest burst of the DMA

  logic clk, rst_n;

  clk_rst_gen #(
    .ClkPeriod   (CyclTime),
    .RstClkCycles(5       )
  ) u_clk_rst (
    .clk_o (clk  ),
    .rst_no(rst_n)
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
  // Random traffic
  // ================================================================================================

  typedef axi_test::axi_rand_master #(
    .AW               (AXI_ADDR_W  ),
    .DW               (AXI_DATA_W  ),
    .IW               (AXI_ID_MST_W),
    .UW               (AXI_USER_W  ),
    .TA               (ApplTime    ),
    .TT               (TestTime    ),
    .MAX_READ_TXNS    (8           ),
    .MAX_WRITE_TXNS   (8           ),
    .AXI_MAX_BURST_LEN(BurstBeats  ),
    .AXI_EXCLS        (1'b0        ),
    .AXI_ATOPS        (1'b0        )
  ) rand_master_t;

  typedef axi_test::axi_rand_slave #(
    .AW(AXI_ADDR_W  ),
    .DW(AXI_DATA_W  ),
    .IW(AXI_ID_SLV_W),
    .UW(AXI_USER_W  ),
    .TA(ApplTime    ),
    .TT(TestTime    )
  ) rand_slave_t;

  typedef tb_axi_xbar_pkg::axi_xbar_monitor #(
    .AxiAddrWidth     (AXI_ADDR_W                ),
    .AxiDataWidth     (AXI_DATA_W                ),
    .AxiIdWidthMasters(AXI_ID_MST_W              ),
    .AxiIdWidthSlaves (AXI_ID_SLV_W              ),
    .AxiUserWidth     (AXI_USER_W                ),
    .NoMasters        (DATA_NUM_MST              ),
    .NoSlaves         (DATA_NUM_SLV              ),
    .NoAddrRules      (DATA_XBAR_CFG.NoAddrRules ),
    .rule_t           (rule_t                    ),
    .AddrMap          (DATA_ADDR_MAP             ),
    .TimeTest         (TestTime                  )
  ) monitor_t;

  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH(AXI_ADDR_W  ),
    .AXI_DATA_WIDTH(AXI_DATA_W  ),
    .AXI_ID_WIDTH  (AXI_ID_MST_W),
    .AXI_USER_WIDTH(AXI_USER_W  )
  ) rand_mst [DATA_NUM_MST-1:0] (clk), rand_mst_mon [DATA_NUM_MST-1:0] (clk);

  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH(AXI_ADDR_W  ),
    .AXI_DATA_WIDTH(AXI_DATA_W  ),
    .AXI_ID_WIDTH  (AXI_ID_SLV_W),
    .AXI_USER_WIDTH(AXI_USER_W  )
  ) rand_slv [DATA_NUM_SLV-1:0] (clk), rand_slv_mon [DATA_NUM_SLV-1:0] (clk);

  axi_mst_req_t [DATA_NUM_MST-1:0] rand_mst_req;
  axi_mst_rsp_t [DATA_NUM_MST-1:0] rand_mst_rsp;
  axi_slv_req_t [DATA_NUM_SLV-1:0] rand_slv_req;
  axi_slv_rsp_t [DATA_NUM_SLV-1:0] rand_slv_rsp;

  for (genvar i = 0; i < DATA_NUM_MST; i++) begin : gen_rand_mst_conn
    `AXI_ASSIGN_TO_REQ(rand_mst_req[i], rand_mst[i])
    `AXI_ASSIGN_FROM_RESP(rand_mst[i], rand_mst_rsp[i])
    `AXI_ASSIGN_MONITOR(rand_mst_mon[i], rand_mst[i])
  end

  for (genvar i = 0; i < DATA_NUM_SLV; i++) begin : gen_rand_slv_conn
    `AXI_ASSIGN_FROM_REQ(rand_slv[i], rand_slv_req[i])
    `AXI_ASSIGN_TO_RESP(rand_slv_rsp[i], rand_slv[i])
    `AXI_ASSIGN_MONITOR(rand_slv_mon[i], rand_slv[i])
  end

  bus_axi_xbar u_dut_rand (
    .clk_i    (clk         ),
    .rst_ni   (rst_n       ),
    .mst_req_i(rand_mst_req),
    .mst_rsp_o(rand_mst_rsp),
    .slv_req_o(rand_slv_req),
    .slv_rsp_i(rand_slv_rsp)
  );

  int unsigned num_txns = 500;
  logic [DATA_NUM_MST-1:0] rand_done = '0;

  initial begin : plusargs
    void'($value$plusargs("TXNS=%d", num_txns));
  end

  for (genvar i = 0; i < DATA_NUM_MST; i++) begin : gen_rand_mst
    rand_master_t master;
    initial begin
      master = new(rand_mst[i]);
      // Regions are picked with equal weight: the L2 in four of six transactions, unmapped space
      // just below and just above it in the other two.
      for (int r = 0; r < 4; r++) begin
        master.add_memory_region(L2_BASE, L2_BASE + L2_SIZE - 1, axi_pkg::DEVICE_NONBUFFERABLE);
      end
      master.add_memory_region(L2_BASE - 32'h2000, L2_BASE - 1, axi_pkg::DEVICE_NONBUFFERABLE);
      master.add_memory_region(L2_BASE + L2_SIZE, L2_BASE + L2_SIZE + 32'h1FFF,
                               axi_pkg::DEVICE_NONBUFFERABLE);
      master.reset();
      @(posedge rst_n);
      master.run(num_txns, num_txns);
      rand_done[i] = 1'b1;
    end
  end

  for (genvar i = 0; i < DATA_NUM_SLV; i++) begin : gen_rand_slv
    rand_slave_t slave;
    initial begin
      slave = new(rand_slv[i]);
      slave.reset();
      @(posedge rst_n);
      slave.run();
    end
  end

  // The monitor takes arrays of virtual interfaces, bound one element at a time.
  virtual AXI_BUS_DV #(
    .AXI_ADDR_WIDTH(AXI_ADDR_W  ),
    .AXI_DATA_WIDTH(AXI_DATA_W  ),
    .AXI_ID_WIDTH  (AXI_ID_MST_W),
    .AXI_USER_WIDTH(AXI_USER_W  )
  ) rand_mst_vif [DATA_NUM_MST-1:0];

  virtual AXI_BUS_DV #(
    .AXI_ADDR_WIDTH(AXI_ADDR_W  ),
    .AXI_DATA_WIDTH(AXI_DATA_W  ),
    .AXI_ID_WIDTH  (AXI_ID_SLV_W),
    .AXI_USER_WIDTH(AXI_USER_W  )
  ) rand_slv_vif [DATA_NUM_SLV-1:0];

  for (genvar i = 0; i < DATA_NUM_MST; i++) begin : gen_rand_mst_vif
    initial rand_mst_vif[i] = rand_mst_mon[i];
  end

  for (genvar i = 0; i < DATA_NUM_SLV; i++) begin : gen_rand_slv_vif
    initial rand_slv_vif[i] = rand_slv_mon[i];
  end

  // Coverage of the random traffic: both banks see transactions and unmapped ones end in DECERR.
  int unsigned rand_bank_ax [DATA_NUM_SLV];
  int unsigned rand_decerr = 0;

  always @(posedge clk) begin : rand_coverage
    if (rst_n) begin
      for (int b = 0; b < DATA_NUM_SLV; b++) begin
        rand_bank_ax[b] += (rand_slv_req[b].aw_valid && rand_slv_rsp[b].aw_ready) +
                           (rand_slv_req[b].ar_valid && rand_slv_rsp[b].ar_ready);
      end
      for (int m = 0; m < DATA_NUM_MST; m++) begin
        rand_decerr += (rand_mst_rsp[m].b_valid && rand_mst_req[m].b_ready &&
                        rand_mst_rsp[m].b.resp == axi_pkg::RESP_DECERR) +
                       (rand_mst_rsp[m].r_valid && rand_mst_req[m].r_ready &&
                        rand_mst_rsp[m].r.last && rand_mst_rsp[m].r.resp == axi_pkg::RESP_DECERR);
      end
    end
  end

  bit rand_finished = 1'b0;
  longint unsigned rand_monitor_checks;

  initial begin : rand_check
    monitor_t monitor;
    foreach (rand_bank_ax[b]) rand_bank_ax[b] = 0;
    #0;  // let the virtual interface bindings above settle
    monitor = new(rand_mst_vif, rand_slv_vif);
    fork
      monitor.run();
    join_none
    wait (&rand_done);
    repeat (10) @(posedge clk);
    monitor.print_result();
    rand_monitor_checks = monitor.tests_conducted;
    check(monitor.tests_failed == 0,
          $sformatf("random: the crossbar monitor failed %0d checks", monitor.tests_failed));
    check(monitor.tests_conducted == monitor.tests_expected,
          $sformatf("random: %0d monitor checks expected, %0d done", monitor.tests_expected,
                    monitor.tests_conducted));
    for (int b = 0; b < DATA_NUM_SLV; b++) begin
      check(rand_bank_ax[b] > 0, $sformatf("random: bank %0d saw no transaction", b));
    end
    check(rand_decerr > 0, "random: no transaction to unmapped space ended in DECERR");
    rand_finished = 1'b1;
  end

  // ================================================================================================
  // Directed tests
  // ================================================================================================

  typedef logic [AXI_DATA_W-1:0] beat_t;

  axi_mst_req_t [DATA_NUM_MST-1:0] dir_mst_req;
  axi_mst_rsp_t [DATA_NUM_MST-1:0] dir_mst_rsp;
  axi_slv_req_t [DATA_NUM_SLV-1:0] dir_slv_req;
  axi_slv_rsp_t [DATA_NUM_SLV-1:0] dir_slv_rsp;

  bus_axi_xbar u_dut_dir (
    .clk_i    (clk        ),
    .rst_ni   (rst_n      ),
    .mst_req_i(dir_mst_req),
    .mst_rsp_o(dir_mst_rsp),
    .slv_req_o(dir_slv_req),
    .slv_rsp_i(dir_slv_rsp)
  );

  // L2 banks: one memory model each, uninitialized bytes read as zero.
  logic      [DATA_NUM_SLV-1:0] bank_w_valid, bank_r_valid;
  axi_addr_t [DATA_NUM_SLV-1:0] bank_w_addr,  bank_r_addr;

  for (genvar b = 0; b < DATA_NUM_SLV; b++) begin : gen_bank
    axi_sim_mem #(
      .AddrWidth        (AXI_ADDR_W   ),
      .DataWidth        (AXI_DATA_W   ),
      .IdWidth          (AXI_ID_SLV_W ),
      .UserWidth        (AXI_USER_W   ),
      .NumPorts         (1            ),
      .axi_req_t        (axi_slv_req_t),
      .axi_rsp_t        (axi_slv_rsp_t),
      .UninitializedData("zeros"      ),
      .ApplDelay        (ApplTime     ),
      .AcqDelay         (TestTime     )
    ) u_mem (
      .clk_i             (clk            ),
      .rst_ni            (rst_n          ),
      .axi_req_i         (dir_slv_req[b] ),
      .axi_rsp_o         (dir_slv_rsp[b] ),
      .mon_w_valid_o     (bank_w_valid[b]),
      .mon_w_addr_o      (bank_w_addr[b] ),
      .mon_w_data_o      (               ),
      .mon_w_id_o        (               ),
      .mon_w_user_o      (               ),
      .mon_w_beat_count_o(               ),
      .mon_w_last_o      (               ),
      .mon_r_valid_o     (bank_r_valid[b]),
      .mon_r_addr_o      (bank_r_addr[b] ),
      .mon_r_data_o      (               ),
      .mon_r_id_o        (               ),
      .mon_r_user_o      (               ),
      .mon_r_beat_count_o(               ),
      .mon_r_last_o      (               )
    );
  end

  // Every beat a bank serves lies in that bank, and the transactions reaching the banks are counted
  // (DECERR must not reach any).
  int unsigned dir_bank_ax = 0;

  always @(posedge clk) begin : dir_bank_check
    if (rst_n) begin
      for (int b = 0; b < DATA_NUM_SLV; b++) begin
        if (bank_w_valid[b]) begin
          check((bank_w_addr[b] >= DATA_ADDR_MAP[b].start_addr) &&
                (bank_w_addr[b] < DATA_ADDR_MAP[b].end_addr),
                $sformatf("bank %0d wrote 0x%08h, outside the bank", b, bank_w_addr[b]));
        end
        if (bank_r_valid[b]) begin
          check((bank_r_addr[b] >= DATA_ADDR_MAP[b].start_addr) &&
                (bank_r_addr[b] < DATA_ADDR_MAP[b].end_addr),
                $sformatf("bank %0d read 0x%08h, outside the bank", b, bank_r_addr[b]));
        end
        dir_bank_ax += (dir_slv_req[b].aw_valid && dir_slv_rsp[b].aw_ready) +
                       (dir_slv_req[b].ar_valid && dir_slv_rsp[b].ar_ready);
      end
    end
  end

  // Cycle count, and the clock edges on which the DMA port moves an R beat and a W beat together.
  int unsigned cycle = 0;
  bit          overlap_on = 1'b0;
  int unsigned overlap = 0;

  always @(posedge clk) begin : dir_cycles
    cycle++;
    if (overlap_on && dir_mst_req[DATA_MST_DMA].r_ready && dir_mst_rsp[DATA_MST_DMA].r_valid &&
        dir_mst_req[DATA_MST_DMA].w_valid && dir_mst_rsp[DATA_MST_DMA].w_ready) begin
      overlap++;
    end
  end

  // ---- Channel drivers: entered and left ApplTime after a clock edge ----------------------------

  // Waits for ready while the valid it answers is up; returns ApplTime after the handshake edge.
  `define WAIT_HANDSHAKE(ready) \
    #(TestTime - ApplTime); \
    while (!(ready)) begin \
      @(posedge clk); \
      #(TestTime); \
    end \
    @(posedge clk); \
    #(ApplTime);

  task automatic send_aw(input int unsigned m, input axi_mst_aw_chan_t aw);
    dir_mst_req[m].aw       = aw;
    dir_mst_req[m].aw_valid = 1'b1;
    `WAIT_HANDSHAKE(dir_mst_rsp[m].aw_ready)
    dir_mst_req[m].aw_valid = 1'b0;
  endtask

  task automatic send_ar(input int unsigned m, input axi_mst_ar_chan_t ar);
    dir_mst_req[m].ar       = ar;
    dir_mst_req[m].ar_valid = 1'b1;
    `WAIT_HANDSHAKE(dir_mst_rsp[m].ar_ready)
    dir_mst_req[m].ar_valid = 1'b0;
  endtask

  task automatic send_w(input int unsigned m, input beat_t data [], input axi_strb_t strb);
    foreach (data[i]) begin
      dir_mst_req[m].w.data  = data[i];
      dir_mst_req[m].w.strb  = strb;
      dir_mst_req[m].w.last  = (i == data.size() - 1);
      dir_mst_req[m].w_valid = 1'b1;
      `WAIT_HANDSHAKE(dir_mst_rsp[m].w_ready)
    end
    dir_mst_req[m].w_valid = 1'b0;
  endtask

  task automatic recv_b(input int unsigned m, output axi_mst_b_chan_t b);
    dir_mst_req[m].b_ready = 1'b1;
    #(TestTime - ApplTime);
    while (!dir_mst_rsp[m].b_valid) begin
      @(posedge clk);
      #(TestTime);
    end
    b = dir_mst_rsp[m].b;
    @(posedge clk);
    #(ApplTime);
    dir_mst_req[m].b_ready = 1'b0;
  endtask

  task automatic recv_r(input int unsigned m, input int unsigned beats, output axi_mst_r_chan_t r []);
    r = new[beats];
    dir_mst_req[m].r_ready = 1'b1;
    foreach (r[i]) begin
      #(TestTime - ApplTime);
      while (!dir_mst_rsp[m].r_valid) begin
        @(posedge clk);
        #(TestTime);
      end
      r[i] = dir_mst_rsp[m].r;
      @(posedge clk);
      #(ApplTime);
    end
    dir_mst_req[m].r_ready = 1'b0;
  endtask

  `undef WAIT_HANDSHAKE

  // ---- Transactions -------------------------------------------------------------------------------

  // An INCR burst of full 16-byte beats, all with the same strobe.
  task automatic axi_write(input int unsigned m, input axi_addr_t addr, input axi_id_mst_t id,
                           input beat_t data [], input axi_strb_t strb,
                           output axi_pkg::resp_t resp);
    axi_mst_aw_chan_t aw;
    axi_mst_b_chan_t  b;
    aw       = '0;
    aw.id    = id;
    aw.addr  = addr;
    aw.len   = axi_pkg::len_t'(data.size() - 1);
    aw.size  = axi_pkg::size_t'($clog2(AXI_DATA_W / 8));
    aw.burst = axi_pkg::BURST_INCR;
    fork
      send_aw(m, aw);
      send_w(m, data, strb);
      recv_b(m, b);
    join
    check(b.id == id, $sformatf("master %0d write 0x%08h: B ID %0d, sent %0d", m, addr, b.id, id));
    resp = b.resp;
  endtask

  // Returns the data of each beat and the worst response; checks the R IDs and the last flag.
  task automatic axi_read(input int unsigned m, input axi_addr_t addr, input axi_id_mst_t id,
                          input int unsigned beats, output beat_t data [],
                          output axi_pkg::resp_t resp);
    axi_mst_ar_chan_t ar;
    axi_mst_r_chan_t  r [];
    ar       = '0;
    ar.id    = id;
    ar.addr  = addr;
    ar.len   = axi_pkg::len_t'(beats - 1);
    ar.size  = axi_pkg::size_t'($clog2(AXI_DATA_W / 8));
    ar.burst = axi_pkg::BURST_INCR;
    fork
      send_ar(m, ar);
      recv_r(m, beats, r);
    join
    data = new[beats];
    resp = axi_pkg::RESP_OKAY;
    foreach (r[i]) begin
      data[i] = r[i].data;
      resp    = axi_pkg::resp_precedence(r[i].resp, resp);
      check(r[i].id == id && r[i].last == (i == beats - 1),
            $sformatf("master %0d read 0x%08h beat %0d: ID %0d last %b, expected ID %0d last %b",
                      m, addr, i, r[i].id, r[i].last, id, i == beats - 1));
    end
  endtask

  function automatic void fill(output beat_t data [], input int unsigned beats,
                               input logic [15:0] tag);
    data = new[beats];
    foreach (data[i]) begin
      data[i] = {tag, 16'(4 * i + 3), tag, 16'(4 * i + 2), tag, 16'(4 * i + 1), tag, 16'(4 * i)};
    end
  endfunction

  function automatic void check_data(input string what, input beat_t got [], input beat_t exp []);
    check(got.size() == exp.size(), $sformatf("%s: %0d beats, expected %0d", what, got.size(),
                                              exp.size()));
    foreach (exp[i]) begin
      check(got[i] === exp[i], $sformatf("%s beat %0d: 0x%032h, expected 0x%032h", what, i,
                                         got[i], exp[i]));
    end
  endfunction

  // ---- Tests --------------------------------------------------------------------------------------

  localparam int unsigned Core = DATA_MST_CORE;
  localparam int unsigned Dma  = DATA_MST_DMA;

  task automatic test_data();
    beat_t          wdata [], rdata [], exp [];
    axi_pkg::resp_t resp;

    // Core: one beat with a single 32-bit lane enabled (lane 1), as the OBI bridge writes a word.
    fill(wdata, 1, 16'hC0DE);
    axi_write(Core, L2_BASE + 32'h10, '0, wdata, 16'h00F0, resp);
    check(resp == axi_pkg::RESP_OKAY, "core lane write to bank 0: response not OKAY");
    axi_read(Dma, L2_BASE + 32'h10, 2'd1, 1, rdata, resp);
    exp = new[1];
    exp[0] = {64'h0, wdata[0][63:32], 32'h0};
    check(resp == axi_pkg::RESP_OKAY, "DMA read of the core's word: response not OKAY");
    check_data("DMA reads the core's lane 1 word", rdata, exp);

    // DMA: a 16-beat burst into the B buffer (bank 0), read back by the core.
    fill(wdata, BurstBeats, 16'hB0B0);
    axi_write(Dma, L2_BASE + 32'h4000, '0, wdata, '1, resp);
    check(resp == axi_pkg::RESP_OKAY, "DMA burst write to bank 0: response not OKAY");
    axi_read(Core, L2_BASE + 32'h4000, '0, BurstBeats, rdata, resp);
    check(resp == axi_pkg::RESP_OKAY, "core burst read from bank 0: response not OKAY");
    check_data("core reads the DMA burst in bank 0", rdata, wdata);

    // Core: four beats into the C buffer (bank 1), read back by the DMA on its other read ID.
    fill(wdata, 4, 16'hCCCC);
    axi_write(Core, L2_BASE + L2_BANK_SIZE + 32'h100, '0, wdata, '1, resp);
    check(resp == axi_pkg::RESP_OKAY, "core write to bank 1: response not OKAY");
    axi_read(Dma, L2_BASE + L2_BANK_SIZE + 32'h100, 2'd0, 4, rdata, resp);
    check(resp == axi_pkg::RESP_OKAY, "DMA read from bank 1: response not OKAY");
    check_data("DMA reads the core's beats in bank 1", rdata, wdata);
  endtask

  task automatic test_decerr();
    beat_t          wdata [], rdata [];
    axi_pkg::resp_t resp;
    int unsigned    bank_ax_before;

    bank_ax_before = dir_bank_ax;
    axi_read(Dma, 32'h3000_0000, 2'd1, 4, rdata, resp);
    check(resp == axi_pkg::RESP_DECERR, "DMA read of 0x3000_0000: response not DECERR");
    fill(wdata, 2, 16'hDEAD);
    axi_write(Dma, L2_BASE - 32'h1000, 2'd0, wdata, '1, resp);
    check(resp == axi_pkg::RESP_DECERR, "DMA write below the L2: response not DECERR");
    axi_read(Core, L2_BASE + L2_SIZE, '0, 1, rdata, resp);
    check(resp == axi_pkg::RESP_DECERR, "core read just above the L2: response not DECERR");
    repeat (4) @(posedge clk);
    #(ApplTime);
    check(dir_bank_ax == bank_ax_before, "a transaction to unmapped space reached an L2 bank");
  endtask

  // The DMA reads 16 beats from bank 0 while it writes 16 beats to bank 1, then does the same one
  // after the other. Run together, the two bursts must move their beats on the same clock edges.
  int unsigned cycles_together, cycles_in_turn;

  task automatic test_concurrency();
    beat_t          wdata [], rdata [];
    axi_pkg::resp_t rresp, wresp;
    int unsigned    start;

    fill(wdata, BurstBeats, 16'hC1C1);

    start      = cycle;
    overlap    = 0;
    overlap_on = 1'b1;
    fork
      axi_read(Dma, L2_BASE + 32'h4000, 2'd0, BurstBeats, rdata, rresp);
      axi_write(Dma, L2_BASE + L2_BANK_SIZE + 32'h1000, 2'd0, wdata, '1, wresp);
    join
    overlap_on      = 1'b0;
    cycles_together = cycle - start;
    check(rresp == axi_pkg::RESP_OKAY && wresp == axi_pkg::RESP_OKAY,
          "concurrent read of bank 0 and write of bank 1: response not OKAY");

    start = cycle;
    axi_read(Dma, L2_BASE + 32'h4000, 2'd0, BurstBeats, rdata, rresp);
    axi_write(Dma, L2_BASE + L2_BANK_SIZE + 32'h1000, 2'd0, wdata, '1, wresp);
    cycles_in_turn = cycle - start;

    $display("read bank 0 + write bank 1, %0d beats each: %0d cycles together (%0d edges with an R",
             BurstBeats, cycles_together, overlap);
    $display("  and a W beat), %0d cycles one after the other", cycles_in_turn);
    check(overlap >= BurstBeats - 2,
          $sformatf("only %0d of %0d R beats moved together with a W beat", overlap, BurstBeats));
    check(cycles_together + BurstBeats - 4 <= cycles_in_turn,
          $sformatf("the concurrent bursts took %0d cycles, in turn %0d", cycles_together,
                    cycles_in_turn));
  endtask

  bit dir_finished = 1'b0;

  initial begin : directed
    dir_mst_req = '0;
    @(posedge rst_n);
    repeat (2) @(posedge clk);
    #(ApplTime);
    test_data();
    test_decerr();
    test_concurrency();
    dir_finished = 1'b1;
  end

  // ================================================================================================
  // End
  // ================================================================================================

  initial begin : report
    wait (dir_finished && rand_finished);
    if (errors == 0) begin
      $display("PASS: %0d checks, %0d by the crossbar monitor on %0d random reads and writes",
               checks, rand_monitor_checks, 2 * DATA_NUM_MST * num_txns);
    end else begin
      $fatal(1, "%0d of %0d checks failed", errors, checks);
    end
    $finish;
  end

endmodule
