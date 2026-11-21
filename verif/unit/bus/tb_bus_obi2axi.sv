// Testbench for bus_obi2axi, the OBI -> AXI4 bridge of the core data port. An OBI driver issues
// loads and stores the way the core does (byte enables and store data of rv32_store_align, address
// aligned to the access size) to an axi_sim_mem behind an axi_delayer, which stalls every AXI
// channel for 0 to 15 cycles, so grants and responses come at varying times.
//
//   - Every AW, W and AR the bridge sends is checked against the OBI request it carries: one
//     16-byte beat at the address with bits 3:0 cleared, ID 0, the store word on every lane and the
//     byte enables shifted to lane addr[3:2].
//   - Every response is checked against a byte model of the memory: the word holding the access for
//     a load, and err for an access to a beat the memory answers with SLVERR or DECERR.
//   - Directed: stores of every size at every position of a beat, with the other bytes of the beat
//     untouched; loads of every size at every position; error responses mixed with OKAY ones; loads
//     and stores back to back, two outstanding.
//   - Random: loads and stores of every size over three windows of the address space (bottom and top
//     of the L2, top of the address space), one at a time like the core or back to back.
//
// Run: make sim TB=tb_bus_obi2axi [SEED=random] [PLUSARGS=+OPS=<random accesses>]

module tb_bus_obi2axi;
  import soc_pkg::*;

  localparam time CyclTime = 10ns;
  localparam time ApplTime = 2ns;   // stimuli change this long after the clock edge
  localparam time TestTime = 8ns;   // and are sampled this long after it

  localparam int unsigned    BeatBytes   = AXI_DATA_W / 8;
  localparam axi_pkg::size_t BeatSize    = axi_pkg::size_t'($clog2(BeatBytes));
  localparam int unsigned    MaxRequests = 2;  // bus_obi2axi: requests granted before a response
  localparam int unsigned    WinBytes    = 256;

  // Random accesses go to three windows; the directed ones use the first. Two beats answer with an
  // error, the way an L2 bank (SLVERR) or the crossbar (DECERR) would.
  localparam axi_addr_t Win [3] = '{L2_BASE, L2_BASE + L2_SIZE - WinBytes, 32'hFFFF_FF00};
  localparam axi_addr_t BeatA   = L2_BASE + 32'h40;
  localparam axi_addr_t BeatB   = L2_BASE + 32'h50;
  localparam axi_addr_t ErrSlv  = L2_BASE + 32'h80;
  localparam axi_addr_t ErrDec  = L2_BASE + L2_SIZE - WinBytes + 32'h30;

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
  // DUT, random stalls, memory
  // ================================================================================================

  obi_req_t     obi_req;
  obi_rsp_t     obi_rsp;
  axi_mst_req_t axi_req, mem_req;
  axi_mst_rsp_t axi_rsp, mem_rsp;

  bus_obi2axi u_dut (
    .clk_i    (clk    ),
    .rst_ni   (rst_n  ),
    .obi_req_i(obi_req),
    .obi_rsp_o(obi_rsp),
    .axi_req_o(axi_req),
    .axi_rsp_i(axi_rsp)
  );

  // AW, W and AR wait before they reach the memory, B and R before they reach the bridge. The wait
  // comes before the handshake, so the bridge and the memory see each handshake on the same edge.
  axi_delayer #(
    .aw_chan_t        (axi_mst_aw_chan_t),
    .w_chan_t         (axi_mst_w_chan_t ),
    .b_chan_t         (axi_mst_b_chan_t ),
    .ar_chan_t        (axi_mst_ar_chan_t),
    .r_chan_t         (axi_mst_r_chan_t ),
    .axi_req_t        (axi_mst_req_t    ),
    .axi_resp_t       (axi_mst_rsp_t    ),
    .StallRandomInput (1'b1             ),
    .StallRandomOutput(1'b1             ),
    .FixedDelayInput  (0                ),
    .FixedDelayOutput (0                )
  ) u_delay (
    .clk_i     (clk    ),
    .rst_ni    (rst_n  ),
    .slv_req_i (axi_req),
    .slv_resp_o(axi_rsp),
    .mst_req_o (mem_req),
    .mst_resp_i(mem_rsp)
  );

  // Bytes the test never wrote read as X, which fails the data check.
  axi_sim_mem #(
    .AddrWidth        (AXI_ADDR_W   ),
    .DataWidth        (AXI_DATA_W   ),
    .IdWidth          (AXI_ID_MST_W ),
    .UserWidth        (AXI_USER_W   ),
    .NumPorts         (1            ),
    .axi_req_t        (axi_mst_req_t),
    .axi_rsp_t        (axi_mst_rsp_t),
    .UninitializedData("undefined"  ),
    .ApplDelay        (ApplTime     ),
    .AcqDelay         (TestTime     )
  ) u_mem (
    .clk_i             (clk    ),
    .rst_ni            (rst_n  ),
    .axi_req_i         (mem_req),
    .axi_rsp_o         (mem_rsp),
    .mon_w_valid_o     (       ),
    .mon_w_addr_o      (       ),
    .mon_w_data_o      (       ),
    .mon_w_id_o        (       ),
    .mon_w_user_o      (       ),
    .mon_w_beat_count_o(       ),
    .mon_w_last_o      (       ),
    .mon_r_valid_o     (       ),
    .mon_r_addr_o      (       ),
    .mon_r_data_o      (       ),
    .mon_r_id_o        (       ),
    .mon_r_user_o      (       ),
    .mon_r_beat_count_o(       ),
    .mon_r_last_o      (       )
  );

  // ================================================================================================
  // Model
  // ================================================================================================

  typedef logic [31:0] word_t;

  typedef struct {
    bit         we;
    axi_addr_t  addr;
    logic [3:0] be;
    word_t      wdata;
    bit         exp_err;    // filled in at the grant
    word_t      exp_rdata;
  } access_t;

  logic [7:0]     model    [axi_addr_t];  // the memory as the accesses granted so far left it
  axi_pkg::resp_t beat_err [axi_addr_t];  // beats the memory answers with an error
  access_t        pending  [$];           // granted, waiting for their response

  function automatic axi_addr_t beat_of(input axi_addr_t addr);
    return {addr[AXI_ADDR_W-1:4], 4'b0000};
  endfunction

  function automatic void preload(input axi_addr_t base, input int unsigned bytes);
    for (int unsigned i = 0; i < bytes; i++) begin
      logic [7:0] b;
      b = 8'($urandom);
      model[base + i]     = b;
      u_mem.mem[base + i] = b;
    end
  endfunction

  function automatic void set_beat_err(input axi_addr_t beat, input axi_pkg::resp_t resp);
    beat_err[beat] = resp;
    for (int unsigned i = 0; i < BeatBytes; i++) begin
      u_mem.rerr[beat + i] = resp;
      u_mem.werr[beat + i] = resp;
    end
  endfunction

  // An access as the core sends it (rv32_store_align); size 0, 1, 2 is a byte, halfword, word, and
  // the address is aligned to it. A load carries byte enables and store data too, both ignored.
  function automatic access_t make_access(input bit we, input axi_addr_t addr,
                                          input int unsigned size, input word_t value);
    access_t a;
    a.we   = we;
    a.addr = addr;
    unique case (size)
      0:       begin a.be = 4'b0001 << addr[1:0]; a.wdata = {4{value[7:0]}};  end
      1:       begin a.be = 4'b0011 << addr[1:0]; a.wdata = {2{value[15:0]}}; end
      default: begin a.be = 4'b1111;              a.wdata = value;            end
    endcase
    return a;
  endfunction

  // At the grant: a store updates the model (the memory writes an error beat too), a load takes the
  // word that holds it. The bridge keeps responses in order, so the response checker sees the
  // memory as it was at the grant.
  function automatic void model_grant(ref access_t a);
    axi_addr_t word;
    word      = {a.addr[AXI_ADDR_W-1:2], 2'b00};
    a.exp_err = beat_err.exists(beat_of(a.addr));
    for (int unsigned i = 0; i < 4; i++) begin
      if (a.we && a.be[i]) begin
        model[word + i] = a.wdata[8*i +: 8];
      end
      a.exp_rdata[8*i +: 8] = model.exists(word + i) ? model[word + i] : 8'hxx;
    end
  endfunction

  // ================================================================================================
  // OBI driver: entered and left ApplTime after a clock edge
  // ================================================================================================

  // Raises the request and holds it until the grant. Returns on the cycle after the grant, so a
  // second call follows with no gap, as the core does when the response is already in.
  task automatic obi_issue(input access_t a);
    obi_req = '{req: 1'b1, addr: a.addr, we: a.we, be: a.be, wdata: a.wdata};
    #(TestTime - ApplTime);
    while (!obi_rsp.gnt) begin
      @(posedge clk);
      #(TestTime);
    end
    model_grant(a);
    pending.push_back(a);
    @(posedge clk);
    #(ApplTime);
    obi_req = '0;
  endtask

  task automatic wait_responses();
    while (pending.size() != 0) begin
      @(posedge clk);
      #(ApplTime);
    end
  endtask

  // ================================================================================================
  // Checkers
  // ================================================================================================

  // Every response belongs to the oldest granted access.
  int unsigned responses = 0;
  int unsigned cov_err_ld = 0, cov_err_st = 0;  // err responses to loads and to stores

  always @(posedge clk) begin : rsp_check
    access_t a;
    if (rst_n && obi_rsp.rvalid) begin
      if (pending.size() == 0) begin
        check(1'b0, "response with no access outstanding");
      end else begin
        a = pending.pop_front();
        responses++;
        if (obi_rsp.err) begin
          if (a.we) cov_err_st++;
          else      cov_err_ld++;
        end
        check(obi_rsp.err == a.exp_err,
              $sformatf("%s 0x%08h: err %b, expected %b", a.we ? "store" : "load", a.addr,
                        obi_rsp.err, a.exp_err));
        if (!a.we && !a.exp_err) begin
          check(obi_rsp.rdata === a.exp_rdata,
                $sformatf("load 0x%08h: rdata 0x%08h, expected 0x%08h", a.addr, obi_rsp.rdata,
                          a.exp_rdata));
        end
      end
    end
  end

  // Every AW, W and AR carries the OBI request held at that moment (the request stays until the
  // grant, which comes with the last of its handshakes).
  int unsigned num_aw = 0, num_w = 0, num_ar = 0;

  always @(posedge clk) begin : axi_check
    axi_strb_t exp_strb;
    if (rst_n) begin
      exp_strb = axi_strb_t'(obi_req.be) << (4 * obi_req.addr[3:2]);
      if (axi_req.aw_valid && axi_rsp.aw_ready) begin
        num_aw++;
        check(obi_req.req && obi_req.we, "AW without a store request");
        check(axi_req.aw.addr == beat_of(obi_req.addr) && axi_req.aw.len == '0 &&
              axi_req.aw.size == BeatSize && axi_req.aw.id == '0 && axi_req.aw.atop == '0 &&
              axi_req.aw.lock == 1'b0,
              $sformatf("store 0x%08h: AW addr 0x%08h len %0d size %0d id %0d atop %0h lock %b",
                        obi_req.addr, axi_req.aw.addr, axi_req.aw.len, axi_req.aw.size,
                        axi_req.aw.id, axi_req.aw.atop, axi_req.aw.lock));
      end
      if (axi_req.w_valid && axi_rsp.w_ready) begin
        num_w++;
        check(obi_req.req && obi_req.we, "W without a store request");
        check(axi_req.w.last && axi_req.w.strb == exp_strb &&
              axi_req.w.data == {(AXI_DATA_W / 32){obi_req.wdata}},
              $sformatf("store 0x%08h be %b: W strb %b data 0x%032h last %b", obi_req.addr,
                        obi_req.be, axi_req.w.strb, axi_req.w.data, axi_req.w.last));
      end
      if (axi_req.ar_valid && axi_rsp.ar_ready) begin
        num_ar++;
        check(obi_req.req && !obi_req.we, "AR without a load request");
        check(axi_req.ar.addr == beat_of(obi_req.addr) && axi_req.ar.len == '0 &&
              axi_req.ar.size == BeatSize && axi_req.ar.id == '0 && axi_req.ar.lock == 1'b0,
              $sformatf("load 0x%08h: AR addr 0x%08h len %0d size %0d id %0d lock %b",
                        obi_req.addr, axi_req.ar.addr, axi_req.ar.len, axi_req.ar.size,
                        axi_req.ar.id, axi_req.ar.lock));
      end
    end
  end

  // Grants, accesses in flight at the bridge and coverage of the timing cases.
  int unsigned num_store = 0, num_load = 0;
  int unsigned in_flight = 0;
  int unsigned cov_two_out = 0;   // cycles with two accesses granted and not answered
  int unsigned cov_gnt_rsp = 0;   // grants in the cycle of a response
  int unsigned cov_stall   = 0;   // cycles a request waits for its grant

  always @(posedge clk) begin : flow_check
    if (rst_n) begin
      if (obi_req.req && obi_rsp.gnt) begin
        if (obi_req.we) num_store++;
        else            num_load++;
      end
      cov_two_out += (in_flight == 2);
      cov_gnt_rsp += obi_req.req && obi_rsp.gnt && obi_rsp.rvalid;
      cov_stall   += obi_req.req && !obi_rsp.gnt;
      in_flight = in_flight + (obi_req.req && obi_rsp.gnt) - obi_rsp.rvalid;
      if (in_flight > MaxRequests) begin
        check(1'b0, $sformatf("%0d accesses granted and not answered", in_flight));
      end
    end
  end

  // ================================================================================================
  // Tests
  // ================================================================================================

  // Every size at every position of a beat, on a fresh beat each time: the bytes of the access take
  // the store data, the other bytes of the beat keep their value.
  task automatic test_store_positions();
    for (int unsigned size = 0; size < 3; size++) begin
      for (int unsigned off = 0; off < BeatBytes; off += (1 << size)) begin
        logic [7:0] exp [BeatBytes];
        word_t      value;
        preload(BeatA, BeatBytes);
        foreach (exp[i]) exp[i] = model[BeatA + i];
        value = $urandom;
        for (int unsigned i = 0; i < (1 << size); i++) exp[off + i] = value[8*i +: 8];
        obi_issue(make_access(1'b1, BeatA + off, size, value));
        wait_responses();
        foreach (exp[i]) begin
          check(u_mem.mem[BeatA + i] === exp[i],
                $sformatf("store of %0d bytes at beat offset %0d: byte %0d is 0x%02h, expected 0x%02h",
                          1 << size, off, i, u_mem.mem[BeatA + i], exp[i]));
        end
      end
    end
  endtask

  // Every size at every position of a beat: each load returns the word that holds it.
  task automatic test_load_positions();
    preload(BeatA, BeatBytes);
    for (int unsigned size = 0; size < 3; size++) begin
      for (int unsigned off = 0; off < BeatBytes; off += (1 << size)) begin
        obi_issue(make_access(1'b0, BeatA + off, size, $urandom));
        wait_responses();
      end
    end
  endtask

  // SLVERR and DECERR beats, loads and stores, each next to an OKAY access: one at a time, then back
  // to back.
  task automatic test_errors();
    int unsigned err_before;
    err_before = cov_err_ld + cov_err_st;
    obi_issue(make_access(1'b0, ErrSlv + 4, 2, $urandom));
    wait_responses();
    obi_issue(make_access(1'b0, BeatA + 8, 2, $urandom));
    wait_responses();
    obi_issue(make_access(1'b1, ErrDec + 2, 1, $urandom));
    wait_responses();
    obi_issue(make_access(1'b1, BeatA + 12, 2, $urandom));
    wait_responses();
    obi_issue(make_access(1'b0, ErrDec + 13, 0, $urandom));
    obi_issue(make_access(1'b0, BeatA + 4, 2, $urandom));
    obi_issue(make_access(1'b1, ErrSlv + 8, 2, $urandom));
    obi_issue(make_access(1'b1, BeatA, 0, $urandom));
    obi_issue(make_access(1'b0, ErrSlv, 2, $urandom));
    wait_responses();
    check(cov_err_ld + cov_err_st - err_before == 5,
          $sformatf("errors: %0d err responses, expected 5", cov_err_ld + cov_err_st - err_before));
  endtask

  // Loads across the lanes and stores followed by loads of the same word, all back to back: the
  // bridge holds up to two, so the lane of each response comes from the right request.
  task automatic test_back_to_back();
    int unsigned lanes [8] = '{3, 0, 2, 1, 1, 3, 0, 2};
    preload(BeatA, BeatBytes);
    preload(BeatB, BeatBytes);
    foreach (lanes[i]) begin
      obi_issue(make_access(1'b0, ((i % 2) ? BeatB : BeatA) + 4 * lanes[i], 2, $urandom));
    end
    obi_issue(make_access(1'b1, BeatA + 8, 2, $urandom));
    obi_issue(make_access(1'b0, BeatA + 8, 2, $urandom));
    obi_issue(make_access(1'b1, BeatB + 13, 0, $urandom));
    obi_issue(make_access(1'b0, BeatB + 12, 2, $urandom));
    obi_issue(make_access(1'b0, BeatA, 2, $urandom));
    obi_issue(make_access(1'b1, BeatA + 6, 1, $urandom));
    obi_issue(make_access(1'b0, BeatA + 4, 1, $urandom));
    wait_responses();
  endtask

  // Random sizes, positions and directions over the three windows. Half of the accesses wait for
  // their response like the core, the other half go back to back; some come after idle cycles.
  task automatic test_random(input int unsigned ops);
    for (int unsigned n = 0; n < ops; n++) begin
      int unsigned size, off;
      size = $urandom_range(0, 2);
      off  = $urandom_range(0, WinBytes - 1) & ~((1 << size) - 1);
      obi_issue(make_access(1'($urandom), Win[$urandom_range(0, 2)] + off, size, $urandom));
      if ($urandom_range(0, 1)) begin
        wait_responses();
      end
      if ($urandom_range(0, 3) == 0) begin
        repeat ($urandom_range(1, 3)) @(posedge clk);
        #(ApplTime);
      end
    end
    wait_responses();
  endtask

  int unsigned num_ops = 2000;

  initial begin : main
    obi_req = '0;
    void'($value$plusargs("OPS=%d", num_ops));
    foreach (Win[w]) preload(Win[w], WinBytes);
    set_beat_err(ErrSlv, axi_pkg::RESP_SLVERR);
    set_beat_err(ErrDec, axi_pkg::RESP_DECERR);
    @(posedge rst_n);
    repeat (2) @(posedge clk);
    #(ApplTime);

    test_store_positions();
    test_load_positions();
    test_errors();
    test_back_to_back();
    test_random(num_ops);
    repeat (4) @(posedge clk);

    check(responses == num_store + num_load,
          $sformatf("%0d responses for %0d grants", responses, num_store + num_load));
    check(num_aw == num_store && num_w == num_store && num_ar == num_load,
          $sformatf("%0d AW, %0d W, %0d AR for %0d stores and %0d loads", num_aw, num_w, num_ar,
                    num_store, num_load));
    check(cov_two_out > 0, "coverage: never two accesses outstanding");
    check(cov_gnt_rsp > 0, "coverage: never a grant in the cycle of a response");
    check(cov_stall > 0, "coverage: no request ever waited for its grant");
    check(cov_err_ld > 0 && cov_err_st > 0, "coverage: no error response to a load or to a store");
    $display("%0d loads, %0d stores (%0d and %0d with err); %0d cycles with two outstanding, %0d",
             num_load, num_store, cov_err_ld, cov_err_st, cov_two_out, cov_gnt_rsp);
    $display("  grants in the cycle of a response, %0d cycles waiting for a grant", cov_stall);

    if (errors == 0) begin
      $display("PASS: %0d checks on %0d OBI accesses (%0d random)", checks, num_load + num_store,
               num_ops);
    end else begin
      $fatal(1, "%0d of %0d checks failed", errors, checks);
    end
    $finish;
  end

endmodule
