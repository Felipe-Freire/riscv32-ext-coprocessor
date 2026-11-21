// Directed testbench for soc_pkg, the memory map and bus configuration of the SoC:
//   - the regions of rtl/top/README.md are naturally aligned powers of two and do not overlap;
//   - each address map (data crossbar, control crossbar, core data-port demux) has 4 KiB aligned,
//     non-overlapping rules with valid indices, and routes the boundary addresses of the README to
//     the right target, decoded by common_cells addr_decode as the crossbars and the demux do;
//   - the crossbar configurations and the bus types agree with the widths of the package.
// Run: make sim TB=tb_soc_pkg
module tb_soc_pkg;
  import soc_pkg::*;

  int checks = 0;
  int errors = 0;

  function automatic void check(input bit cond, input string msg);
    checks++;
    if (!cond) begin
      errors++;
      $error("%s", msg);
    end
  endfunction

  function automatic bit is_pow2(input logic [31:0] x);
    return (x != 0) && ((x & (x - 1)) == 0);
  endfunction

  // ---- Decoders: one per address map ----------------------------------------------------------------

  localparam int unsigned NoMaps = 3;
  localparam int unsigned MapData = 0;
  localparam int unsigned MapCtrl = 1;
  localparam int unsigned MapCore = 2;

  string map_name [NoMaps] = '{"data crossbar", "control crossbar", "core demux"};

  logic [31:0] dec_addr  [NoMaps];
  int unsigned dec_idx   [NoMaps];
  logic        dec_valid [NoMaps];
  logic        dec_error [NoMaps];

  logic [cf_math_pkg::idx_width(DATA_NUM_SLV)-1:0] data_idx;
  logic [cf_math_pkg::idx_width(CTRL_NUM_SLV)-1:0] ctrl_idx;
  logic [cf_math_pkg::idx_width(CORE_NUM_TGT)-1:0] core_idx;

  addr_decode #(
    .NoIndices(DATA_NUM_SLV),
    .NoRules  (DATA_NUM_SLV),
    .addr_t   (axi_addr_t  ),
    .rule_t   (rule_t      )
  ) u_data_dec (
    .addr_i          (dec_addr[MapData] ),
    .addr_map_i      (DATA_ADDR_MAP     ),
    .idx_o           (data_idx          ),
    .dec_valid_o     (dec_valid[MapData]),
    .dec_error_o     (dec_error[MapData]),
    .en_default_idx_i(1'b0              ),
    .default_idx_i   ('0                )
  );

  addr_decode #(
    .NoIndices(CTRL_NUM_SLV),
    .NoRules  (CTRL_NUM_SLV),
    .addr_t   (axil_addr_t ),
    .rule_t   (rule_t      )
  ) u_ctrl_dec (
    .addr_i          (dec_addr[MapCtrl] ),
    .addr_map_i      (CTRL_ADDR_MAP     ),
    .idx_o           (ctrl_idx          ),
    .dec_valid_o     (dec_valid[MapCtrl]),
    .dec_error_o     (dec_error[MapCtrl]),
    .en_default_idx_i(1'b0              ),
    .default_idx_i   ('0                )
  );

  addr_decode #(
    .NoIndices(CORE_NUM_TGT),
    .NoRules  (CORE_NUM_TGT),
    .addr_t   (logic [31:0]),
    .rule_t   (rule_t      )
  ) u_core_dec (
    .addr_i          (dec_addr[MapCore] ),
    .addr_map_i      (CORE_ADDR_MAP     ),
    .idx_o           (core_idx          ),
    .dec_valid_o     (dec_valid[MapCore]),
    .dec_error_o     (dec_error[MapCore]),
    .en_default_idx_i(1'b0              ),
    .default_idx_i   ('0                )
  );

  assign dec_idx[MapData] = data_idx;
  assign dec_idx[MapCtrl] = ctrl_idx;
  assign dec_idx[MapCore] = core_idx;

  // Decodes addr with one map and checks the target; tgt < 0 expects no rule to match.
  task automatic expect_route(input int unsigned map, input logic [31:0] addr, input int tgt);
    dec_addr[map] = addr;
    #1;
    if (tgt < 0) begin
      check(dec_error[map] && !dec_valid[map],
            $sformatf("%s: 0x%08h should match no rule, got index %0d", map_name[map], addr,
                      dec_idx[map]));
    end else begin
      check(dec_valid[map] && !dec_error[map] && (dec_idx[map] == tgt),
            $sformatf("%s: 0x%08h should go to index %0d, got valid=%b index %0d", map_name[map],
                      addr, tgt, dec_valid[map], dec_idx[map]));
    end
  endtask

  // ---- Static checks -----------------------------------------------------------------------------------

  typedef struct {
    string       name;
    logic [31:0] base;
    logic [31:0] size;
  } region_t;

  region_t regions [] = '{
    '{"Boot ROM", BOOT_ROM_BASE, BOOT_ROM_SIZE},
    '{"I-TCM",    ITCM_BASE,     ITCM_SIZE    },
    '{"D-TCM",    DTCM_BASE,     DTCM_SIZE    },
    '{"L2",       L2_BASE,       L2_SIZE      },
    '{"timer",    TIMER_BASE,    PERIPH_SIZE  },
    '{"DMA",      DMA_BASE,      PERIPH_SIZE  },
    '{"coproc",   COPROC_BASE,   PERIPH_SIZE  }
  };

  function automatic void check_regions();
    foreach (regions[i]) begin
      check(is_pow2(regions[i].size), $sformatf("%s size 0x%0h is not a power of two",
                                                regions[i].name, regions[i].size));
      check((regions[i].base & (regions[i].size - 1)) == 0,
            $sformatf("%s base 0x%08h is not aligned to its size", regions[i].name,
                      regions[i].base));
      for (int j = i + 1; j < regions.size(); j++) begin
        check((regions[i].base + regions[i].size <= regions[j].base) ||
              (regions[j].base + regions[j].size <= regions[i].base),
              $sformatf("%s and %s overlap", regions[i].name, regions[j].name));
      end
    end
    check(L2_BANK_SIZE * L2_NUM_BANKS == L2_SIZE, "the L2 banks do not add up to the L2");
    check($clog2(L2_BANK_SIZE) == 15, "the L2 bank is not selected by address bit 15");
    check((PERIPH_SIZE == 32'h1000) && (CTRL_BASE == TIMER_BASE) && is_pow2(CTRL_SIZE),
          "peripheral windows are not 4 KiB from the start of the control window");
  endfunction

  function automatic void check_rules(input string name, input rule_t rules [], input int num_idx);
    foreach (rules[i]) begin
      check(rules[i].start_addr < rules[i].end_addr,
            $sformatf("%s rule %0d: start 0x%08h is not below end 0x%08h", name, i,
                      rules[i].start_addr, rules[i].end_addr));
      check((rules[i].start_addr[11:0] == 0) && (rules[i].end_addr[11:0] == 0),
            $sformatf("%s rule %0d is not 4 KiB aligned", name, i));
      check(rules[i].idx < num_idx, $sformatf("%s rule %0d: index %0d out of range", name, i,
                                              rules[i].idx));
      for (int j = i + 1; j < rules.size(); j++) begin
        check((rules[i].end_addr <= rules[j].start_addr) ||
              (rules[j].end_addr <= rules[i].start_addr),
              $sformatf("%s rules %0d and %0d overlap", name, i, j));
      end
    end
  endfunction

  function automatic void check_xbar_cfgs();
    check(DATA_XBAR_CFG.NoSlvPorts == DATA_NUM_MST && DATA_XBAR_CFG.NoMstPorts == DATA_NUM_SLV &&
          DATA_XBAR_CFG.NoAddrRules == $size(DATA_ADDR_MAP), "data crossbar: port or rule count");
    check(DATA_XBAR_CFG.AxiIdWidthSlvPorts == AXI_ID_MST_W &&
          DATA_XBAR_CFG.AxiIdUsedSlvPorts == AXI_ID_MST_W, "data crossbar: master ID width");
    check(AXI_ID_SLV_W == AXI_ID_MST_W + $clog2(DATA_NUM_MST), "data crossbar: slave ID width");
    check(DATA_XBAR_CFG.AxiAddrWidth == AXI_ADDR_W && DATA_XBAR_CFG.AxiDataWidth == AXI_DATA_W,
          "data crossbar: address or data width");
    check(CTRL_XBAR_CFG.NoSlvPorts == 1 && CTRL_XBAR_CFG.NoMstPorts == CTRL_NUM_SLV &&
          CTRL_XBAR_CFG.NoAddrRules == $size(CTRL_ADDR_MAP), "control crossbar: port or rule count");
    check(CTRL_XBAR_CFG.AxiAddrWidth == AXIL_ADDR_W && CTRL_XBAR_CFG.AxiDataWidth == AXIL_DATA_W,
          "control crossbar: address or data width");
  endfunction

  axi_mst_req_t mst_req;
  axi_mst_rsp_t mst_rsp;
  axi_slv_req_t slv_req;
  axi_slv_rsp_t slv_rsp;
  axil_req_t    axil_req;
  axil_rsp_t    axil_rsp;
  obi_req_t     obi_req;
  obi_rsp_t     obi_rsp;

  function automatic void check_types();
    check($bits(mst_req.aw.id) == AXI_ID_MST_W && $bits(mst_req.ar.id) == AXI_ID_MST_W &&
          $bits(mst_rsp.b.id) == AXI_ID_MST_W && $bits(mst_rsp.r.id) == AXI_ID_MST_W,
          "axi_mst: ID width");
    check($bits(slv_req.aw.id) == AXI_ID_SLV_W && $bits(slv_rsp.r.id) == AXI_ID_SLV_W,
          "axi_slv: ID width");
    check($bits(mst_req.aw.addr) == AXI_ADDR_W && $bits(mst_req.w.data) == AXI_DATA_W &&
          $bits(mst_req.w.strb) == AXI_DATA_W / 8 && $bits(mst_rsp.r.data) == AXI_DATA_W,
          "axi_mst: address, data or strobe width");
    check($bits(axil_req.aw.addr) == AXIL_ADDR_W && $bits(axil_req.w.data) == AXIL_DATA_W &&
          $bits(axil_req.w.strb) == AXIL_DATA_W / 8 && $bits(axil_rsp.r.data) == AXIL_DATA_W,
          "axil: address, data or strobe width");
    check($bits(obi_req.addr) == 32 && $bits(obi_req.be) == 4 && $bits(obi_req.wdata) == 32 &&
          $bits(obi_rsp.rdata) == 32, "obi: address, byte enable or data width");
  endfunction

  // ---- Test -----------------------------------------------------------------------------------------------

  initial begin
    // The maps are packed arrays of different sizes: copy them for check_rules.
    rule_t data_rules [], ctrl_rules [], core_rules [];

    data_rules = new[$size(DATA_ADDR_MAP)];
    ctrl_rules = new[$size(CTRL_ADDR_MAP)];
    core_rules = new[$size(CORE_ADDR_MAP)];
    foreach (data_rules[i]) data_rules[i] = DATA_ADDR_MAP[i];
    foreach (ctrl_rules[i]) ctrl_rules[i] = CTRL_ADDR_MAP[i];
    foreach (core_rules[i]) core_rules[i] = CORE_ADDR_MAP[i];
    foreach (dec_addr[m]) dec_addr[m] = '0;

    check_regions();
    check_rules("data crossbar",    data_rules, DATA_NUM_SLV);
    check_rules("control crossbar", ctrl_rules, CTRL_NUM_SLV);
    check_rules("core demux",       core_rules, CORE_NUM_TGT);
    check_xbar_cfgs();
    check_types();

    // Data crossbar: the two L2 banks (A and B in bank 0, C in bank 1), DECERR outside the L2.
    expect_route(MapData, 32'h2000_0000, DATA_SLV_L2_BANK0);  // A buffer
    expect_route(MapData, 32'h2000_4000, DATA_SLV_L2_BANK0);  // B buffer
    expect_route(MapData, 32'h2000_7FF0, DATA_SLV_L2_BANK0);
    expect_route(MapData, 32'h2000_8000, DATA_SLV_L2_BANK1);  // C buffer
    expect_route(MapData, 32'h2000_FFF0, DATA_SLV_L2_BANK1);
    expect_route(MapData, 32'h1FFF_FFF0, -1);
    expect_route(MapData, 32'h2001_0000, -1);
    expect_route(MapData, 32'h4000_1000, -1);

    // Control crossbar: one 4 KiB window per peripheral, DECERR in the rest of the control window.
    expect_route(MapCtrl, 32'h4000_0000, CTRL_SLV_TIMER);
    expect_route(MapCtrl, 32'h4000_0FFC, CTRL_SLV_TIMER);
    expect_route(MapCtrl, 32'h4000_1000, CTRL_SLV_DMA);
    expect_route(MapCtrl, 32'h4000_105C, CTRL_SLV_DMA);       // channel 2 STATUS
    expect_route(MapCtrl, 32'h4000_2000, CTRL_SLV_COPROC);
    expect_route(MapCtrl, 32'h4000_2FFC, CTRL_SLV_COPROC);
    expect_route(MapCtrl, 32'h4000_3000, -1);
    expect_route(MapCtrl, 32'h4FFF_FFFC, -1);

    // Core data port: D-TCM, L2 and the control window; no data access to the Boot ROM or I-TCM.
    expect_route(MapCore, 32'h0000_0000, -1);                 // Boot ROM
    expect_route(MapCore, 32'h1000_0000, -1);                 // I-TCM
    expect_route(MapCore, 32'h1000_7FFC, -1);
    expect_route(MapCore, 32'h1001_0000, CORE_TGT_DTCM);
    expect_route(MapCore, 32'h1001_7FFC, CORE_TGT_DTCM);
    expect_route(MapCore, 32'h1001_8000, -1);
    expect_route(MapCore, 32'h2000_0000, CORE_TGT_DATA);
    expect_route(MapCore, 32'h2000_FFFC, CORE_TGT_DATA);
    expect_route(MapCore, 32'h2001_0000, -1);
    expect_route(MapCore, 32'h3FFF_FFFC, -1);
    expect_route(MapCore, 32'h4000_0000, CORE_TGT_CTRL);
    expect_route(MapCore, 32'h4000_3000, CORE_TGT_CTRL);      // decoded further by the crossbar
    expect_route(MapCore, 32'h4FFF_FFFC, CORE_TGT_CTRL);
    expect_route(MapCore, 32'h5000_0000, -1);
    expect_route(MapCore, 32'hFFFF_FFFC, -1);

    if (errors == 0) begin
      $display("PASS: %0d checks", checks);
    end else begin
      $fatal(1, "%0d of %0d checks failed", errors, checks);
    end
    $finish;
  end

endmodule
