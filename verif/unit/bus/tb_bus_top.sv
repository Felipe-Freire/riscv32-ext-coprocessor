// Testbench for bus_top, the interconnect. The core data port is an OBI driver; the DMA port is an
// axi_test::axi_rand_master that sends random bursts to its own area of both L2 banks for the whole
// test, so the core's L2 accesses compete with it. Memories and peripherals are models:
//
//   D-TCM        OBI memory in the testbench: grants on random cycles, answers in the next one
//   L2 banks     axi_sim_mem
//   peripherals  vendor axi_lite_regs, 8 registers each. Register 0 is read-only and holds an ID
//                that tells the peripherals apart; offsets 0x20-0x3F answer SLVERR.
//
// Every response at the core port is checked against a byte model of the D-TCM, the L2 and the
// registers, and against the error its address must get: none in the D-TCM and the L2, SLVERR from
// a register, DECERR in the control window outside the peripherals, err from the demux anywhere
// else. Counters at the ports of bus_top check which target each access reached.
//
//   - Directed: the first and last word of every window and the words just outside them, each
//     reaching its target or none; a store and a load back to back, switching target every time.
//   - Random: loads and stores of every size over all the windows and some unmapped space, one at a
//     time like the core or back to back.
//
// bus_obi_sva (verif/assertions) checks the OBI rules at the core port and the D-TCM port.
//
// Run: make sim TB=tb_bus_top [SEED=random] [PLUSARGS=+OPS=<random accesses>]
`include "axi/assign.svh"

module tb_bus_top;
  import soc_pkg::*;

  localparam time CyclTime = 10ns;
  localparam time ApplTime = 2ns;   // stimuli change this long after the clock edge
  localparam time TestTime = 8ns;   // and are sampled this long after it

  localparam int unsigned RegBytes  = 32;  // registers of each peripheral model
  localparam int unsigned DmaChunk  = 20;  // DMA reads and writes per axi_rand_master run
  localparam int unsigned DmaOffset = 32'h4000;  // the DMA area of each bank
  localparam int unsigned DmaBytes  = 32'h1000;

  // Peripheral IDs, read-only in register 0, indexed by CTRL_SLV_*.
  localparam logic [31:0] PeriphId [CTRL_NUM_SLV] = '{32'h544D_5230, 32'h444D_4130, 32'h4350_5230};

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
  // DUT
  // ================================================================================================

  obi_req_t     core_req;
  obi_rsp_t     core_rsp;
  obi_req_t     dtcm_req;
  obi_rsp_t     dtcm_rsp;
  axi_mst_req_t dma_req;
  axi_mst_rsp_t dma_rsp;
  axi_slv_req_t [DATA_NUM_SLV-1:0] l2_req;
  axi_slv_rsp_t [DATA_NUM_SLV-1:0] l2_rsp;
  axil_req_t    [CTRL_NUM_SLV-1:0] periph_req;
  axil_rsp_t    [CTRL_NUM_SLV-1:0] periph_rsp;

  bus_top u_dut (
    .clk_i       (clk       ),
    .rst_ni      (rst_n     ),
    .core_req_i  (core_req  ),
    .core_rsp_o  (core_rsp  ),
    .dtcm_req_o  (dtcm_req  ),
    .dtcm_rsp_i  (dtcm_rsp  ),
    .dma_req_i   (dma_req   ),
    .dma_rsp_o   (dma_rsp   ),
    .l2_req_o    (l2_req    ),
    .l2_rsp_i    (l2_rsp    ),
    .periph_req_o(periph_req),
    .periph_rsp_i(periph_rsp)
  );

  // ================================================================================================
  // Models of the memories and peripherals
  // ================================================================================================

  // D-TCM: grants a request on two cycles out of three, writes or reads at the grant, answers in the
  // next cycle.
  logic [7:0]  dtcm_mem [axi_addr_t];
  logic        dtcm_ready = 1'b0;
  logic        dtcm_rvalid_q;
  logic [31:0] dtcm_rdata_q;

  assign dtcm_rsp = '{gnt: dtcm_req.req & dtcm_ready, rvalid: dtcm_rvalid_q, rdata: dtcm_rdata_q,
                      err: 1'b0};

  initial begin : dtcm_stall
    forever begin
      @(posedge clk);
      #(ApplTime);
      dtcm_ready = ($urandom_range(0, 2) != 0);
    end
  end

  always @(posedge clk or negedge rst_n) begin : dtcm_model
    axi_addr_t word;
    if (!rst_n) begin
      dtcm_rvalid_q <= 1'b0;
    end else begin
      dtcm_rvalid_q <= dtcm_req.req && dtcm_rsp.gnt;
      if (dtcm_req.req && dtcm_rsp.gnt) begin
        word = {dtcm_req.addr[31:2], 2'b00};
        for (int i = 0; i < 4; i++) begin
          if (dtcm_req.we && dtcm_req.be[i]) dtcm_mem[word + i] = dtcm_req.wdata[8*i +: 8];
          dtcm_rdata_q[8*i +: 8] <= dtcm_mem.exists(word + i) ? dtcm_mem[word + i] : 8'hxx;
        end
      end
    end
  end

  // L2 banks
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

  // Peripherals
  for (genvar p = 0; p < CTRL_NUM_SLV; p++) begin : gen_periph
    axi_lite_regs #(
      .RegNumBytes (RegBytes                           ),
      .AxiAddrWidth(AXIL_ADDR_W                        ),
      .AxiDataWidth(AXIL_DATA_W                        ),
      .PrivProtOnly(1'b0                               ),
      .SecuProtOnly(1'b0                               ),
      .AxiReadOnly (RegBytes'(4'hF)                    ),
      .RegRstVal   ({{(RegBytes - 4){8'h00}}, PeriphId[p]}),
      .req_lite_t  (axil_req_t                         ),
      .resp_lite_t (axil_rsp_t                         )
    ) u_regs (
      .clk_i      (clk          ),
      .rst_ni     (rst_n        ),
      .axi_req_i  (periph_req[p]),
      .axi_resp_o (periph_rsp[p]),
      .wr_active_o(             ),
      .rd_active_o(             ),
      .reg_d_i    ('0           ),
      .reg_load_i ('0           ),
      .reg_q_o    (             )
    );
  end

  // ================================================================================================
  // DMA port: random bursts to the DMA area of both banks until the core is done
  // ================================================================================================

  // Like the DMA: two reads and one write in flight, bursts of up to 16 beats, few idle cycles.
  typedef axi_test::axi_rand_master #(
    .AW                  (AXI_ADDR_W  ),
    .DW                  (AXI_DATA_W  ),
    .IW                  (AXI_ID_MST_W),
    .UW                  (AXI_USER_W  ),
    .TA                  (ApplTime    ),
    .TT                  (TestTime    ),
    .MAX_READ_TXNS       (2           ),
    .MAX_WRITE_TXNS      (1           ),
    .AX_MIN_WAIT_CYCLES  (0           ),
    .AX_MAX_WAIT_CYCLES  (4           ),
    .W_MIN_WAIT_CYCLES   (0           ),
    .W_MAX_WAIT_CYCLES   (1           ),
    .RESP_MIN_WAIT_CYCLES(0           ),
    .RESP_MAX_WAIT_CYCLES(2           ),
    .AXI_MAX_BURST_LEN   (16          ),
    .AXI_EXCLS           (1'b0        ),
    .AXI_ATOPS           (1'b0        )
  ) dma_master_t;

  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH(AXI_ADDR_W  ),
    .AXI_DATA_WIDTH(AXI_DATA_W  ),
    .AXI_ID_WIDTH  (AXI_ID_MST_W),
    .AXI_USER_WIDTH(AXI_USER_W  )
  ) dma_bus (clk);

  `AXI_ASSIGN_TO_REQ(dma_req, dma_bus)
  `AXI_ASSIGN_FROM_RESP(dma_bus, dma_rsp)

  bit          core_done = 1'b0;
  bit          dma_done  = 1'b0;
  int unsigned dma_txns  = 0;

  initial begin : dma_traffic
    dma_master_t master;
    master = new(dma_bus);
    for (int b = 0; b < DATA_NUM_SLV; b++) begin
      master.add_memory_region(DATA_ADDR_MAP[b].start_addr + DmaOffset,
                               DATA_ADDR_MAP[b].start_addr + DmaOffset + DmaBytes - 1,
                               axi_pkg::DEVICE_NONBUFFERABLE);
    end
    master.reset();
    @(posedge rst_n);
    while (!core_done) begin
      master.run(DmaChunk, DmaChunk);
      dma_txns += 2 * DmaChunk;
    end
    dma_done = 1'b1;
  end

  // ================================================================================================
  // Expected behaviour
  // ================================================================================================

  typedef enum int {
    T_DTCM, T_L2_BANK0, T_L2_BANK1, T_TIMER, T_DMA, T_COPROC,  // the ports of bus_top
    T_CTRL_NONE,                                                 // DECERR from the control crossbar
    T_NONE                                                       // err from the demux
  } target_e;

  localparam int unsigned NumTargets  = T_NONE + 1;
  localparam int unsigned NumObserved = T_CTRL_NONE;  // targets seen at a port

  localparam target_e PeriphTarget [CTRL_NUM_SLV] = '{T_TIMER, T_DMA, T_COPROC};
  localparam target_e BankTarget   [DATA_NUM_SLV] = '{T_L2_BANK0, T_L2_BANK1};

  function automatic bit in_window(input axi_addr_t addr, input axi_addr_t base,
                                   input axi_addr_t size);
    return addr >= base && addr - base < size;
  endfunction

  function automatic target_e target_of(input axi_addr_t addr);
    if (in_window(addr, DTCM_BASE, DTCM_SIZE)) return T_DTCM;
    for (int b = 0; b < DATA_NUM_SLV; b++) begin
      if (in_window(addr, L2_BASE + b * L2_BANK_SIZE, L2_BANK_SIZE)) return BankTarget[b];
    end
    if (in_window(addr, TIMER_BASE, PERIPH_SIZE))  return T_TIMER;
    if (in_window(addr, DMA_BASE, PERIPH_SIZE))    return T_DMA;
    if (in_window(addr, COPROC_BASE, PERIPH_SIZE)) return T_COPROC;
    if (in_window(addr, CTRL_BASE, CTRL_SIZE))     return T_CTRL_NONE;
    return T_NONE;
  endfunction

  function automatic string tname(input int t);
    target_e e;
    e = target_e'(t);
    return e.name();
  endfunction

  function automatic int periph_of(input target_e t);
    foreach (PeriphTarget[p]) if (PeriphTarget[p] == t) return p;
    return -1;
  endfunction

  typedef logic [31:0] word_t;

  typedef struct {
    bit         we;
    axi_addr_t  addr;
    logic [3:0] be;
    word_t      wdata;
    target_e    target;     // filled in at the grant
    bit         exp_err;
    word_t      exp_rdata;
  } access_t;

  logic [7:0] mem_model [axi_addr_t];                 // D-TCM and L2 bytes
  logic [7:0] reg_model [CTRL_NUM_SLV][RegBytes];     // peripheral registers
  access_t    pending   [$];                          // granted, waiting for the response

  int unsigned issued  [NumTargets];  // accesses granted, by target
  int unsigned reached [NumTargets];  // handshakes seen at the ports of bus_top, by target

  // An access as the core sends it (rv32_store_align); size 0, 1, 2 is a byte, halfword, word.
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

  // At the grant: the target and the error the access must get, the model updated by a store and
  // the word a load must return. One access is outstanding at a time, so this is the state the
  // target answers from.
  function automatic void model_grant(ref access_t a);
    axi_addr_t word;
    int        p, off;
    word     = {a.addr[31:2], 2'b00};
    a.target = target_of(a.addr);
    issued[a.target]++;
    unique case (a.target)
      T_DTCM, T_L2_BANK0, T_L2_BANK1: begin
        a.exp_err = 1'b0;
        for (int i = 0; i < 4; i++) begin
          if (a.we && a.be[i]) mem_model[word + i] = a.wdata[8*i +: 8];
          a.exp_rdata[8*i +: 8] = mem_model.exists(word + i) ? mem_model[word + i] : 8'hxx;
        end
      end
      T_TIMER, T_DMA, T_COPROC: begin
        // axi_lite_regs decodes address bits 5:0. Register 0 is read-only: a store there writes
        // nothing and gets SLVERR, like an offset past the last register.
        p   = periph_of(a.target);
        off = {a.addr[5:2], 2'b00};
        a.exp_err = (off >= RegBytes) || (a.we && off == 0);
        if (!a.exp_err) begin
          for (int i = 0; i < 4; i++) begin
            if (a.we && a.be[i]) reg_model[p][off + i] = a.wdata[8*i +: 8];
            a.exp_rdata[8*i +: 8] = reg_model[p][off + i];
          end
        end
      end
      default: a.exp_err = 1'b1;
    endcase
  endfunction

  function automatic void preload(input axi_addr_t base, input int unsigned bytes);
    for (int unsigned i = 0; i < bytes; i++) begin
      logic [7:0] v;
      v = 8'($urandom);
      mem_model[base + i] = v;
      unique case (target_of(base + i))
        T_DTCM:     dtcm_mem[base + i] = v;
        T_L2_BANK0: gen_bank[DATA_SLV_L2_BANK0].u_mem.mem[base + i] = v;
        T_L2_BANK1: gen_bank[DATA_SLV_L2_BANK1].u_mem.mem[base + i] = v;
        default:    $fatal(1, "preload of 0x%08h, outside the memories", base + i);
      endcase
    end
  endfunction

  // ================================================================================================
  // OBI driver: entered and left ApplTime after a clock edge
  // ================================================================================================

  task automatic obi_issue(input access_t a);
    core_req = '{req: 1'b1, addr: a.addr, we: a.we, be: a.be, wdata: a.wdata};
    #(TestTime - ApplTime);
    while (!core_rsp.gnt) begin
      @(posedge clk);
      #(TestTime);
    end
    model_grant(a);
    pending.push_back(a);
    @(posedge clk);
    #(ApplTime);
    core_req = '0;
  endtask

  task automatic wait_responses();
    while (pending.size() != 0) begin
      @(posedge clk);
      #(ApplTime);
    end
  endtask

  // ================================================================================================
  // Checkers and coverage
  // ================================================================================================

  int unsigned responses = 0;
  int unsigned err_rsp [NumTargets];  // error responses, by target

  always @(posedge clk) begin : rsp_check
    access_t a;
    if (rst_n && core_rsp.rvalid) begin
      if (pending.size() == 0) begin
        check(1'b0, "core port: response with no access outstanding");
      end else begin
        a = pending.pop_front();
        responses++;
        if (core_rsp.err) err_rsp[a.target]++;
        check(core_rsp.err == a.exp_err,
              $sformatf("%s 0x%08h (%s): err %b, expected %b", a.we ? "store" : "load", a.addr,
                        a.target.name(), core_rsp.err, a.exp_err));
        if (!a.we && !a.exp_err) begin
          check(core_rsp.rdata === a.exp_rdata,
                $sformatf("load 0x%08h (%s): rdata 0x%08h, expected 0x%08h", a.addr,
                          a.target.name(), core_rsp.rdata, a.exp_rdata));
        end
      end
    end
  end

  // Where accesses arrive: D-TCM grants, AW and AR of the core (ID prefix DATA_MST_CORE) at each
  // bank, AW and AR at each peripheral.
  int unsigned cov_gnt_rsp = 0;  // core grants in the cycle of a response
  int unsigned cov_shared  = 0;  // cycles the core and the DMA both address the same bank

  localparam int unsigned BankBit = $clog2(L2_BANK_SIZE);  // address bit that picks the bank

  always @(posedge clk) begin : port_monitor
    axi_mst_req_t core_axi, dma_axi;
    logic [1:0]   core_v, core_b, dma_v, dma_b;
    logic         shared;
    shared = 1'b0;
    if (rst_n) begin
      reached[T_DTCM] += dtcm_req.req && dtcm_rsp.gnt;
      for (int b = 0; b < DATA_NUM_SLV; b++) begin
        reached[BankTarget[b]] +=
            (l2_req[b].aw_valid && l2_rsp[b].aw_ready &&
             l2_req[b].aw.id[AXI_ID_SLV_W-1:AXI_ID_MST_W] == DATA_MST_CORE) +
            (l2_req[b].ar_valid && l2_rsp[b].ar_ready &&
             l2_req[b].ar.id[AXI_ID_SLV_W-1:AXI_ID_MST_W] == DATA_MST_CORE);
      end
      for (int p = 0; p < CTRL_NUM_SLV; p++) begin
        reached[PeriphTarget[p]] += (periph_req[p].aw_valid && periph_rsp[p].aw_ready) +
                                    (periph_req[p].ar_valid && periph_rsp[p].ar_ready);
      end
      cov_gnt_rsp += core_req.req && core_rsp.gnt && core_rsp.rvalid;
      // AW and AR of each master at the crossbar inputs, and the bank each one addresses.
      core_axi = u_dut.data_req[DATA_MST_CORE];
      dma_axi  = u_dut.data_req[DATA_MST_DMA];
      core_v   = {core_axi.aw_valid, core_axi.ar_valid};
      core_b   = {core_axi.aw.addr[BankBit], core_axi.ar.addr[BankBit]};
      dma_v    = {dma_axi.aw_valid, dma_axi.ar_valid};
      dma_b    = {dma_axi.aw.addr[BankBit], dma_axi.ar.addr[BankBit]};
      for (int c = 0; c < 2; c++) begin
        for (int d = 0; d < 2; d++) begin
          shared |= core_v[c] && dma_v[d] && (core_b[c] == dma_b[d]);
        end
      end
      cov_shared += shared;
    end
  end

  // ================================================================================================
  // Tests
  // ================================================================================================

  // Windows of the random test and of the preload: the first 1 KiB and the last 256 bytes of each
  // memory, the registers of each peripheral, and unmapped space next to every window.
  typedef struct {
    axi_addr_t   base;
    int unsigned bytes;
  } window_t;

  localparam window_t MemWin [6] = '{
    '{DTCM_BASE, 32'h400}, '{DTCM_BASE + DTCM_SIZE - 32'h100, 32'h100},
    '{L2_BASE, 32'h400},   '{L2_BASE + L2_BANK_SIZE - 32'h100, 32'h100},
    '{L2_BASE + L2_BANK_SIZE, 32'h400}, '{L2_BASE + L2_SIZE - 32'h100, 32'h100}
  };

  localparam window_t RegWin [3] = '{
    '{TIMER_BASE, 2 * RegBytes}, '{DMA_BASE, 2 * RegBytes}, '{COPROC_BASE, 2 * RegBytes}
  };

  localparam window_t ErrWin [10] = '{
    '{BOOT_ROM_BASE, 32'h40}, '{ITCM_BASE, 32'h40}, '{DTCM_BASE - 32'h40, 32'h40},
    '{DTCM_BASE + DTCM_SIZE, 32'h40}, '{L2_BASE - 32'h40, 32'h40}, '{L2_BASE + L2_SIZE, 32'h40},
    '{32'h3000_0000, 32'h40}, '{CTRL_BASE - 32'h40, 32'h40},
    '{COPROC_BASE + PERIPH_SIZE, 32'h40}, '{CTRL_BASE + CTRL_SIZE - 32'h40, 32'h80}
  };

  // A store and a load of one word at the edges of every window and next to them. Each access
  // reaches the target of its address and no other, or none.
  localparam axi_addr_t Probes [27] = '{
    BOOT_ROM_BASE, BOOT_ROM_BASE + BOOT_ROM_SIZE - 4, ITCM_BASE, ITCM_BASE + ITCM_SIZE - 4,
    DTCM_BASE - 4, DTCM_BASE, DTCM_BASE + DTCM_SIZE - 4, DTCM_BASE + DTCM_SIZE,
    L2_BASE - 4, L2_BASE, L2_BASE + L2_BANK_SIZE - 4, L2_BASE + L2_BANK_SIZE,
    L2_BASE + L2_SIZE - 4, L2_BASE + L2_SIZE, 32'h3000_0000,
    CTRL_BASE - 4, TIMER_BASE, TIMER_BASE + 4, TIMER_BASE + PERIPH_SIZE - 4,
    DMA_BASE, DMA_BASE + 4, COPROC_BASE, COPROC_BASE + 4, COPROC_BASE + PERIPH_SIZE,
    CTRL_BASE + CTRL_SIZE - 4, CTRL_BASE + CTRL_SIZE, 32'hFFFF_FFFC
  };

  task automatic test_map();
    int unsigned prev [NumTargets];
    target_e     t;
    foreach (Probes[i]) begin
      t = target_of(Probes[i]);
      for (int we = 1; we >= 0; we--) begin
        prev = reached;
        obi_issue(make_access(we, Probes[i], 2, $urandom));
        wait_responses();
        for (int o = 0; o < NumObserved; o++) begin
          check(reached[o] - prev[o] == (o == t),
                $sformatf("%s 0x%08h (%s): %0d accesses reached %s", we ? "store" : "load",
                          Probes[i], t.name(), reached[o] - prev[o], tname(o)));
        end
      end
    end
  endtask

  // Back to back, a different target every access, errors included.
  task automatic test_back_to_back();
    access_t seq [$];
    seq.push_back(make_access(1'b0, DTCM_BASE + 32'h10, 2, $urandom));
    seq.push_back(make_access(1'b1, L2_BASE + 32'h20, 2, $urandom));
    seq.push_back(make_access(1'b0, TIMER_BASE, 2, $urandom));
    seq.push_back(make_access(1'b0, 32'h3000_0004, 2, $urandom));
    seq.push_back(make_access(1'b0, L2_BASE + L2_BANK_SIZE + 32'h30, 2, $urandom));
    seq.push_back(make_access(1'b1, DMA_BASE + 32'h8, 2, $urandom));
    seq.push_back(make_access(1'b0, COPROC_BASE + PERIPH_SIZE, 2, $urandom));
    seq.push_back(make_access(1'b1, DTCM_BASE + 32'h12, 1, $urandom));
    seq.push_back(make_access(1'b0, DMA_BASE + 32'h8, 2, $urandom));
    seq.push_back(make_access(1'b0, L2_BASE + 32'h20, 2, $urandom));
    seq.push_back(make_access(1'b1, ITCM_BASE, 2, $urandom));
    seq.push_back(make_access(1'b0, DTCM_BASE + 32'h10, 2, $urandom));
    seq.push_back(make_access(1'b1, L2_BASE + L2_BANK_SIZE + 32'h33, 0, $urandom));
    seq.push_back(make_access(1'b0, L2_BASE + L2_BANK_SIZE + 32'h30, 2, $urandom));
    seq.push_back(make_access(1'b0, COPROC_BASE, 2, $urandom));
    foreach (seq[i]) obi_issue(seq[i]);
    wait_responses();
  endtask

  // Random sizes, positions and directions: half to the D-TCM and the L2, a quarter to the
  // registers, a quarter to unmapped space and the control window outside the peripherals.
  task automatic test_random(input int unsigned ops);
    for (int unsigned n = 0; n < ops; n++) begin
      window_t     w;
      int unsigned size, off, pick;
      pick = $urandom_range(0, 99);
      if (pick < 50)      w = MemWin[$urandom_range(0, $size(MemWin) - 1)];
      else if (pick < 75) w = RegWin[$urandom_range(0, $size(RegWin) - 1)];
      else                w = ErrWin[$urandom_range(0, $size(ErrWin) - 1)];
      size = $urandom_range(0, 2);
      off  = $urandom_range(0, w.bytes - 1) & ~((1 << size) - 1);
      obi_issue(make_access(1'($urandom), w.base + off, size, $urandom));
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

  function automatic int unsigned num_issued();
    int unsigned n = 0;
    foreach (issued[t]) n += issued[t];
    return n;
  endfunction

  int unsigned num_ops = 2000;

  initial begin : main
    core_req = '0;
    void'($value$plusargs("OPS=%d", num_ops));
    foreach (issued[t]) begin
      issued[t]  = 0;
      reached[t] = 0;
      err_rsp[t] = 0;
    end
    foreach (reg_model[p, i]) reg_model[p][i] = (i < 4) ? PeriphId[p][8*i +: 8] : 8'h00;
    foreach (MemWin[w]) preload(MemWin[w].base, MemWin[w].bytes);
    @(posedge rst_n);
    repeat (2) @(posedge clk);
    #(ApplTime);

    test_map();
    test_back_to_back();
    test_random(num_ops);
    core_done = 1'b1;
    wait (dma_done);
    repeat (4) @(posedge clk);

    check(responses == num_issued(),
          $sformatf("%0d responses for %0d grants", responses, num_issued()));
    for (int t = 0; t < NumObserved; t++) begin
      check(reached[t] == issued[t],
            $sformatf("%s: %0d accesses reached it, %0d were sent", tname(t),
                      reached[t], issued[t]));
    end
    check(err_rsp[T_NONE] > 0 && err_rsp[T_CTRL_NONE] > 0 && err_rsp[T_TIMER] > 0,
          "coverage: missing err from the demux, DECERR or SLVERR");
    check(cov_gnt_rsp > 0, "coverage: never a grant in the cycle of a response");
    check(cov_shared > 0, "coverage: the core and the DMA never addressed the same bank together");

    $display("Accesses by target (errors):");
    for (int t = 0; t < NumTargets; t++) begin
      $display("  %-12s %5d (%0d)", tname(t), issued[t], err_rsp[t]);
    end
    $display("%0d grants in the cycle of a response, %0d cycles with the core and the DMA on one bank",
             cov_gnt_rsp, cov_shared);

    if (errors == 0) begin
      $display("PASS: %0d checks on %0d core accesses (%0d random) beside %0d DMA bursts", checks,
               num_issued(), num_ops, dma_txns);
    end else begin
      $fatal(1, "%0d of %0d checks failed", errors, checks);
    end
    $finish;
  end

endmodule
