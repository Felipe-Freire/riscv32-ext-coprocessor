// One job: dimensions, matrix contents and how the streams behave. make_beats() builds the A and
// B streams in the order the DMA sends them (sw/README.md): for each tile of C, in row-major tile
// order, the K beats of its A panel and the K beats of its B panel.

typedef enum {
  DataRandom,   // uniform int8
  DataExtreme,  // mostly -128 and 127, some -1, 0, 1
  DataZero,     // one of the two matrices all zero
  DataMinMax    // every element -128: the largest products
} coproc_data_e;

class coproc_job extends uvm_object;

  rand int unsigned  tiles_m;
  rand int unsigned  tiles_n;
  rand int unsigned  k;
  rand coproc_data_e data;
  rand bit           early_streams;  // A and B start before the registers are written
  rand int unsigned  a_gap_pct;
  rand int unsigned  b_gap_pct;
  rand int unsigned  c_ready_pct;
  rand int unsigned  c_stall_pct;

  // Bounds of the random dimensions; directed tests raise them.
  int unsigned max_tiles = 6;
  int unsigned max_k     = 200;

  byte a[][];  // A[M][K]
  byte b[][];  // B[K][N]

  constraint c_dims {
    tiles_m inside {[1:max_tiles]};
    tiles_n inside {[1:max_tiles]};
    k inside {[1:max_k]};
    k dist {1 :/ 10, [2:7] :/ 20, [8:64] :/ 45, [65:65535] :/ 25};
  }

  constraint c_data {
    data dist {DataRandom :/ 70, DataExtreme :/ 20, DataZero :/ 5, DataMinMax :/ 5};
  }

  constraint c_flow {
    a_gap_pct inside {[0:50]};
    b_gap_pct inside {[0:50]};
    c_ready_pct inside {[30:100]};
    c_stall_pct inside {[0:5]};
    early_streams dist {1'b0 :/ 80, 1'b1 :/ 20};
  }

  `uvm_object_utils(coproc_job)

  function new(string name = "coproc_job");
    super.new(name);
  endfunction

  function int unsigned m();
    return coproc_pkg::ARRAY_DIM * tiles_m;
  endfunction

  function int unsigned n();
    return coproc_pkg::ARRAY_DIM * tiles_n;
  endfunction

  function byte element();
    int unsigned p = $urandom_range(99);
    case (data)
      DataExtreme: begin
        if (p < 40) return -128;
        if (p < 80) return 127;
        if (p < 87) return -1;
        if (p < 94) return 0;
        return 1;
      end
      DataMinMax: return -128;
      default:    return byte'($urandom());
    endcase
  endfunction

  function void make_matrices();
    bit zero_a = $urandom_range(1);
    a = new[m()];
    foreach (a[r]) begin
      a[r] = new[k];
      foreach (a[r][kk]) a[r][kk] = (data == DataZero && zero_a) ? 0 : element();
    end
    b = new[k];
    foreach (b[kk]) begin
      b[kk] = new[n()];
      foreach (b[kk][c]) b[kk][c] = (data == DataZero && !zero_a) ? 0 : element();
    end
  endfunction

  function void make_beats(ref bit [AXIS_MAX_DW-1:0] a_beats[$],
                           ref bit [AXIS_MAX_DW-1:0] b_beats[$]);
    localparam int unsigned D = coproc_pkg::ARRAY_DIM;
    bit [AXIS_MAX_DW-1:0] beat;
    for (int unsigned ti = 0; ti < tiles_m; ti++) begin
      for (int unsigned tj = 0; tj < tiles_n; tj++) begin
        for (int unsigned kk = 0; kk < k; kk++) begin
          beat = '0;
          for (int unsigned l = 0; l < D; l++) beat[8*l +: 8] = a[D*ti + l][kk];
          a_beats.push_back(beat);
          beat = '0;
          for (int unsigned l = 0; l < D; l++) beat[8*l +: 8] = b[kk][D*tj + l];
          b_beats.push_back(beat);
        end
      end
    end
  endfunction

  // Generous bound on the cycles of the job, gaps and back-pressure included.
  function int unsigned max_cycles();
    return 8 * tiles_m * tiles_n * (k + 64) + 4000;
  endfunction

  function string convert2string();
    return $sformatf("M=%0d N=%0d K=%0d %s, gaps A/B %0d/%0d %%, C ready %0d %% stall %0d %%%s",
                     m(), n(), k, data.name(), a_gap_pct, b_gap_pct, c_ready_pct, c_stall_pct,
                     early_streams ? ", streams first" : "");
  endfunction

endclass
