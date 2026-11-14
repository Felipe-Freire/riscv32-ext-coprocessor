// Functional coverage of the verification plan, one sample per checked job:
//   cg_cop_cfg   tile counts, K, shape of the tile grid
//   cg_cop_flow  gaps in A and B, C back-pressure, clock ratio, register accesses while busy,
//                beats taken before START, consecutive jobs

class coproc_coverage extends uvm_subscriber #(coproc_job_info);

  typedef enum {
    ShapeSingle,  // one tile
    ShapeRow,     // one row of tiles
    ShapeColumn,  // one column of tiles
    ShapeGrid
  } shape_e;

  typedef enum {
    ClkAccFaster,
    ClkEqual,
    ClkAccSlower
  } clk_e;

  coproc_job_info j;
  shape_e         shape;
  clk_e           clk;

  covergroup cg_cop_cfg;
    cp_tiles_m : coverpoint j.tiles_m {
      bins one  = {1};
      bins few  = {[2:4]};
      bins many = {[5:$]};
    }
    cp_tiles_n : coverpoint j.tiles_n {
      bins one  = {1};
      bins few  = {[2:4]};
      bins many = {[5:$]};
    }
    cp_k : coverpoint j.k {
      bins one     = {1};
      bins short_k = {[2:7]};
      bins mid     = {[8:64]};
      bins long_k  = {[65:65534]};
      bins max     = {65535};
    }
    cp_shape : coverpoint shape;
    cx_tiles : cross cp_tiles_m, cp_tiles_n;
  endgroup

  covergroup cg_cop_flow;
    cp_a_gap      : coverpoint (j.a_gaps > 0);
    cp_b_gap      : coverpoint (j.b_gaps > 0);
    cx_gaps       : cross cp_a_gap, cp_b_gap;
    cp_c_stall    : coverpoint (j.c_stalls > 0);
    cp_clk        : coverpoint clk;
    cp_busy_regs  : coverpoint (j.busy_accesses > 0);
    cp_early      : coverpoint (j.early_a > 0 || j.early_b > 0);
    cp_consecutive: coverpoint j.consecutive;
  endgroup

  `uvm_component_utils(coproc_coverage)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_cop_cfg  = new();
    cg_cop_flow = new();
  endfunction

  function void write(coproc_job_info t);
    j = t;
    if (j.tiles_m == 1 && j.tiles_n == 1)  shape = ShapeSingle;
    else if (j.tiles_m == 1)               shape = ShapeRow;
    else if (j.tiles_n == 1)               shape = ShapeColumn;
    else                                   shape = ShapeGrid;
    if (j.clk_ratio < 0.95)      clk = ClkAccFaster;
    else if (j.clk_ratio > 1.05) clk = ClkAccSlower;
    else                         clk = ClkEqual;
    cg_cop_cfg.sample();
    cg_cop_flow.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("cg_cop_cfg %.1f %%, cg_cop_flow %.1f %%",
                               cg_cop_cfg.get_coverage(), cg_cop_flow.get_coverage()), UVM_NONE)
  endfunction

endclass
