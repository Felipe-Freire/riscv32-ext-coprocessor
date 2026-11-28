// mem_l2_bank: one L2 bank (32 KiB of 128-bit words) as the data crossbar sees it, with whichever
// primitives MEM_TECH compiles (generic by default, the OpenRAM macros with MEM_TECH=openram45).
//
// A monitor on the AXI port checks every response against a reference of the bank, filled with
// the same random words as the bank (bd_write) and updated by every W beat in the order the bank
// takes them:
//   1. reads: an axi_test::axi_rand_master issues random INCR bursts of up to 16 beats, any size,
//      up to 8 in flight; every byte of every R beat is checked;
//   2. writes: the same with random strobes; at the end bd_read of every word against the reference;
//   3. reads and writes at once: the protocol under contention (every burst answered OKAY, r_last
//      on the last beat) and the contents at the end (the data of a read that races a write to the
//      same bytes is not checked: its order against the write is the bank's choice);
//   4. bandwidth: streams of 16-beat bursts of full words, back to back, with no wait on the
//      master side: reads alone, writes alone and both at once, in beats per cycle, and the
//      latency from AR to the first R beat. The bank has one RAM port, so reads and writes share
//      one beat per cycle.
// +TXNS=<n> sets the bursts of each random phase (default 2000).

`include "axi/assign.svh"

module tb_mem_l2_bank;
  import soc_pkg::*;

  localparam time CyclTime = 10ns;
  localparam time ApplTime = 2ns;   // stimuli change this long after the clock edge
  localparam time TestTime = 8ns;   // and are sampled this long after it

  localparam int unsigned SizeBytes  = L2_BANK_SIZE;
  localparam int unsigned WordBytes  = AXI_DATA_W / 8;
  localparam int unsigned Depth      = SizeBytes / WordBytes;
  localparam logic [31:0] Base       = L2_BASE;  // bank 0
  localparam int unsigned NumIds     = 2 ** AXI_ID_SLV_W;
  localparam int unsigned StreamLen  = 16;       // beats per burst of the bandwidth phase
  localparam int unsigned StreamTxns = 64;

  logic clk, rst_n;

  clk_rst_gen #(
    .ClkPeriod   (CyclTime),
    .RstClkCycles(5       )
  ) u_clk_rst (
    .clk_o (clk  ),
    .rst_no(rst_n)
  );

  axi_slv_req_t req;
  axi_slv_rsp_t rsp;

  mem_l2_bank u_dut (
    .clk_i    (clk  ),
    .rst_ni   (rst_n),
    .axi_req_i(req  ),
    .axi_rsp_o(rsp  )
  );

  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH(AXI_ADDR_W  ),
    .AXI_DATA_WIDTH(AXI_DATA_W  ),
    .AXI_ID_WIDTH  (AXI_ID_SLV_W),
    .AXI_USER_WIDTH(AXI_USER_W  )
  ) bus (clk);

  `AXI_ASSIGN_TO_REQ(req, bus)
  `AXI_ASSIGN_FROM_RESP(bus, rsp)

  // The masters of the crossbar keep several bursts in flight and do not stall much.
  typedef axi_test::axi_rand_master #(
    .AW                  (AXI_ADDR_W  ),
    .DW                  (AXI_DATA_W  ),
    .IW                  (AXI_ID_SLV_W),
    .UW                  (AXI_USER_W  ),
    .TA                  (ApplTime    ),
    .TT                  (TestTime    ),
    .MAX_READ_TXNS       (8           ),
    .MAX_WRITE_TXNS      (8           ),
    .AX_MIN_WAIT_CYCLES  (0           ),
    .AX_MAX_WAIT_CYCLES  (2           ),
    .W_MIN_WAIT_CYCLES   (0           ),
    .W_MAX_WAIT_CYCLES   (1           ),
    .RESP_MIN_WAIT_CYCLES(0           ),
    .RESP_MAX_WAIT_CYCLES(2           ),
    .AXI_MAX_BURST_LEN   (16          ),
    .AXI_EXCLS           (1'b0        ),
    .AXI_ATOPS           (1'b0        ),
    .AXI_BURST_FIXED     (1'b0        ),  // the bank takes INCR bursts only
    .AXI_BURST_INCR      (1'b1        ),
    .AXI_BURST_WRAP      (1'b0        )
  ) master_t;

  int unsigned checks = 0;
  int unsigned errors = 0;

  function automatic void check(input bit cond, input string msg);
    checks++;
    if (!cond) begin
      errors++;
      $error("%s", msg);
    end
  endfunction

  // ================================================================================================
  // Reference and monitor
  // ================================================================================================

  typedef struct {
    axi_addr_t       addr;
    axi_pkg::len_t   len;
    axi_pkg::size_t  size;
    axi_pkg::burst_t burst;
    int unsigned     beat;
  } burst_t;

  typedef struct {
    axi_data_t data;
    axi_strb_t strb;
    logic      last;
  } w_beat_t;

  logic [7:0] model [SizeBytes];
  burst_t     ar_q [NumIds][$];
  burst_t     aw_q [$];
  w_beat_t    w_q [$];
  bit         check_read_data = 1'b1;
  longint     cycle = 0;  // edges since reset: the monitor counts each one before its handshakes
  longint     r_beats = 0, w_beats = 0, b_resps = 0;
  longint     first_r_cycle = -1, last_r_cycle = 0, last_w_cycle = 0;

  function automatic int unsigned offset(input axi_addr_t addr);
    return addr & (SizeBytes - 1);
  endfunction

  // The address of byte lane 0 of beat i of a burst.
  function automatic axi_addr_t word_addr(input burst_t b, input int unsigned i);
    return axi_pkg::beat_addr(b.addr, b.size, b.len, b.burst, i) & ~axi_addr_t'(WordBytes - 1);
  endfunction

  // Every handshake, sampled at the edge, before the DUT and the master change anything.
  always @(posedge clk) begin : monitor
    if (rst_n) begin
      cycle++;
      if (bus.ar_valid && bus.ar_ready) begin
        ar_q[bus.ar_id].push_back('{addr: bus.ar_addr, len: bus.ar_len, size: bus.ar_size,
                                    burst: bus.ar_burst, beat: 0});
      end
      if (bus.aw_valid && bus.aw_ready) begin
        aw_q.push_back('{addr: bus.aw_addr, len: bus.aw_len, size: bus.aw_size, burst: bus.aw_burst,
                         beat: 0});
      end
      if (bus.w_valid && bus.w_ready) begin
        w_q.push_back('{data: bus.w_data, strb: bus.w_strb, last: bus.w_last});
        w_beats++;
        last_w_cycle = cycle;
      end

      // W beats apply to the bursts of AW in order (AXI4 has no write interleaving).
      while (aw_q.size() > 0 && w_q.size() > 0) begin
        automatic burst_t    b  = aw_q[0];
        automatic w_beat_t   w  = w_q.pop_front();
        automatic axi_addr_t wa = word_addr(b, b.beat);
        for (int unsigned j = 0; j < WordBytes; j++) begin
          if (w.strb[j]) model[offset(wa + j)] = w.data[8*j +: 8];
        end
        check(w.last == (b.beat == b.len), $sformatf("w_last %b on beat %0d of %0d", w.last, b.beat,
                                                     b.len + 1));
        if (b.beat == b.len) void'(aw_q.pop_front());
        else aw_q[0].beat++;
      end

      if (bus.b_valid && bus.b_ready) begin
        check(bus.b_resp == axi_pkg::RESP_OKAY, $sformatf("b_resp %0d", bus.b_resp));
        b_resps++;
      end

      if (bus.r_valid && bus.r_ready) begin
        r_beats++;
        last_r_cycle = cycle;
        if (first_r_cycle < 0) first_r_cycle = cycle;
        if (ar_q[bus.r_id].size() == 0) begin
          check(1'b0, $sformatf("R beat with ID %0d and no read burst of that ID", bus.r_id));
        end else begin
          automatic burst_t b = ar_q[bus.r_id][0];
          check(bus.r_resp == axi_pkg::RESP_OKAY, $sformatf("r_resp %0d", bus.r_resp));
          check(bus.r_last == (b.beat == b.len), $sformatf("r_last %b on beat %0d of %0d",
                                                           bus.r_last, b.beat, b.len + 1));
          if (check_read_data) begin
            automatic int unsigned lo = axi_pkg::beat_lower_byte(b.addr, b.size, b.len, b.burst,
                                                                 WordBytes, b.beat);
            automatic int unsigned hi = axi_pkg::beat_upper_byte(b.addr, b.size, b.len, b.burst,
                                                                 WordBytes, b.beat);
            automatic axi_addr_t   wa = word_addr(b, b.beat);
            for (int unsigned j = lo; j <= hi; j++) begin
              check(bus.r_data[8*j +: 8] === model[offset(wa + j)],
                    $sformatf("read of byte %h returned %h, expected %h", wa + j, bus.r_data[8*j +: 8],
                              model[offset(wa + j)]));
            end
          end
          if (b.beat == b.len) void'(ar_q[bus.r_id].pop_front());
          else ar_q[bus.r_id][0].beat++;
        end
      end
    end
  end

  // bd_read of every word against the reference.
  task automatic check_contents(input string phase);
    int unsigned bad = 0;
    for (int unsigned i = 0; i < Depth; i++) begin
      axi_data_t word = u_dut.bd_read(i);
      for (int unsigned j = 0; j < WordBytes; j++) begin
        if (word[8*j +: 8] !== model[i * WordBytes + j]) bad++;
      end
    end
    check(bad == 0, $sformatf("%s: %0d bytes of the bank differ from the reference", phase, bad));
  endtask

  task automatic check_idle(input string phase);
    int unsigned pending = aw_q.size() + w_q.size();
    for (int unsigned i = 0; i < NumIds; i++) pending += ar_q[i].size();
    check(pending == 0, $sformatf("%s: %0d bursts or beats unanswered", phase, pending));
  endtask

  // ================================================================================================
  // Bandwidth: streams of full-word bursts with no wait on the master side
  // ================================================================================================

  // StreamTxns bursts of StreamLen full words on AR, reads of the lower half of the bank, and/or on
  // AW and W, writes of the upper half, back to back. Call it just after an edge. Returns the
  // cycles from the first request to the last data beat, the beats moved each way, and the cycles
  // from the first request to the first R beat. The handshakes are those the monitor counts: each
  // driver tests ready at the edge, before the DUT updates it.
  task automatic stream(input bit reads, input bit writes, output longint cycles,
                        output longint rd_beats, output longint wr_beats, output longint latency);
    longint t0, r0, w0, b0;
    #1;  // the monitor has counted this edge
    t0 = cycle;
    r0 = r_beats;
    w0 = w_beats;
    b0 = b_resps;
    first_r_cycle = -1;
    last_r_cycle  = t0;
    last_w_cycle  = t0;
    bus.r_ready <= #(ApplTime - 1ns) 1'b1;
    bus.b_ready <= #(ApplTime - 1ns) 1'b1;
    fork
      if (reads) begin : ar_stream
        for (int unsigned k = 0; k < StreamTxns; k++) begin
          bus.ar_id    <= #(ApplTime - 1ns) '0;
          bus.ar_addr  <= #(ApplTime - 1ns) Base + k * StreamLen * WordBytes;
          bus.ar_len   <= #(ApplTime - 1ns) StreamLen - 1;
          bus.ar_size  <= #(ApplTime - 1ns) $clog2(WordBytes);
          bus.ar_burst <= #(ApplTime - 1ns) axi_pkg::BURST_INCR;
          bus.ar_valid <= #(ApplTime - 1ns) 1'b1;
          do @(posedge clk); while (!(bus.ar_valid && bus.ar_ready));
          #1;
        end
        bus.ar_valid <= #(ApplTime - 1ns) 1'b0;
        while (r_beats - r0 < StreamTxns * StreamLen) begin
          @(posedge clk);
          #1;
        end
      end
      if (writes) begin : aw_stream
        for (int unsigned k = 0; k < StreamTxns; k++) begin
          bus.aw_id    <= #(ApplTime - 1ns) '0;
          bus.aw_addr  <= #(ApplTime - 1ns) Base + SizeBytes / 2 + k * StreamLen * WordBytes;
          bus.aw_len   <= #(ApplTime - 1ns) StreamLen - 1;
          bus.aw_size  <= #(ApplTime - 1ns) $clog2(WordBytes);
          bus.aw_burst <= #(ApplTime - 1ns) axi_pkg::BURST_INCR;
          bus.aw_valid <= #(ApplTime - 1ns) 1'b1;
          do @(posedge clk); while (!(bus.aw_valid && bus.aw_ready));
          #1;
        end
        bus.aw_valid <= #(ApplTime - 1ns) 1'b0;
      end
      if (writes) begin : w_stream
        for (int unsigned k = 0; k < StreamTxns * StreamLen; k++) begin
          bus.w_data  <= #(ApplTime - 1ns) {AXI_DATA_W/32{$urandom()}};
          bus.w_strb  <= #(ApplTime - 1ns) '1;
          bus.w_last  <= #(ApplTime - 1ns) (k % StreamLen == StreamLen - 1);
          bus.w_valid <= #(ApplTime - 1ns) 1'b1;
          do @(posedge clk); while (!(bus.w_valid && bus.w_ready));
          #1;
        end
        bus.w_valid <= #(ApplTime - 1ns) 1'b0;
        while (b_resps - b0 < StreamTxns) begin
          @(posedge clk);
          #1;
        end
      end
    join
    cycles   = ((last_r_cycle > last_w_cycle) ? last_r_cycle : last_w_cycle) - t0;
    rd_beats = r_beats - r0;
    wr_beats = w_beats - w0;
    latency  = first_r_cycle - t0;
  endtask

  // ================================================================================================
  // Test sequence
  // ================================================================================================

  initial begin : test
    master_t     master;
    int          txns;
    longint      cyc, rd, wr, lat;
    real         rd_bw, wr_bw, mix_rd, mix_wr;

    if (!$value$plusargs("TXNS=%d", txns)) txns = 2000;
    for (int unsigned i = 0; i < Depth; i++) begin
      axi_data_t word;
      for (int unsigned j = 0; j < WordBytes; j++) begin
        model[i * WordBytes + j] = $urandom();
        word[8*j +: 8] = model[i * WordBytes + j];
      end
      u_dut.bd_write(i, word);
    end

    master = new(bus);
    master.add_memory_region(Base, Base + SizeBytes - 1, axi_pkg::DEVICE_NONBUFFERABLE);
    master.reset();
    @(posedge rst_n);
    repeat (2) @(posedge clk);

    // 1. Reads.
    master.run(txns, 0);
    check_idle("reads");
    $display("1. reads: %0d bursts, %0d beats", txns, r_beats);

    // 2. Writes.
    master.run(0, txns);
    repeat (4) @(posedge clk);
    check_idle("writes");
    check_contents("writes");
    $display("2. writes: %0d bursts, %0d beats", txns, w_beats);

    // 3. Both at once.
    check_read_data = 1'b0;
    master.run(txns, txns);
    repeat (4) @(posedge clk);
    check_idle("reads and writes");
    check_contents("reads and writes");
    $display("3. reads and writes: %0d bursts each", txns);

    // 4. Bandwidth. The read streams cover the lower half of the bank and the write streams the
    // upper half, so the read data stays checked when both run.
    master.reset();
    check_read_data = 1'b1;
    @(posedge clk);
    stream(1'b1, 1'b0, cyc, rd, wr, lat);
    rd_bw = real'(rd) / cyc;
    $display("4. read stream: %0d beats in %0d cycles, %.2f beats per cycle, %0d cycles from AR to R",
             rd, cyc, rd_bw, lat);
    @(posedge clk);
    stream(1'b0, 1'b1, cyc, rd, wr, lat);
    wr_bw = real'(wr) / cyc;
    $display("   write stream: %0d beats in %0d cycles, %.2f beats per cycle", wr, cyc, wr_bw);
    @(posedge clk);
    stream(1'b1, 1'b1, cyc, rd, wr, lat);
    mix_rd = real'(rd) / cyc;
    mix_wr = real'(wr) / cyc;
    $display("   both streams: %0d read and %0d write beats in %0d cycles, %.2f + %.2f beats per cycle",
             rd, wr, cyc, mix_rd, mix_wr);
    repeat (4) @(posedge clk);
    check_idle("bandwidth");
    check_contents("bandwidth");
    // One beat per cycle in total, less the start and the drain of the streams.
    check(rd_bw > 0.9, $sformatf("read stream at %.2f beats per cycle", rd_bw));
    check(wr_bw > 0.9, $sformatf("write stream at %.2f beats per cycle", wr_bw));
    check(mix_rd + mix_wr > 0.9, $sformatf("both streams at %.2f beats per cycle", mix_rd + mix_wr));

    $display("%0d checks, %0d errors", checks, errors);
    if (errors != 0) $fatal(1, "%0d errors", errors);
    $display("PASS: the L2 bank answers every burst and matches the reference");
    $finish;
  end

  initial begin : timeout
    #100ms;
    $fatal(1, "timeout");
  end

endmodule
