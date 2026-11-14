// What the scoreboard saw of one job, published when its last C word has been checked. The
// coverage collector samples it.

class coproc_job_info extends uvm_object;

  int unsigned m, n, k;
  int unsigned tiles_m, tiles_n;
  int unsigned a_gaps, b_gaps;    // beats that came after idle cycles
  int unsigned c_stalls;          // beats that waited for TREADY
  int unsigned early_a, early_b;  // beats already taken by the block when START arrived
  int unsigned busy_accesses;     // register accesses while the job was running
  real         clk_ratio;         // clk_acc_i period / clk_i period
  bit          consecutive;       // a job had already run since the last reset
  time         start_time, end_time;

  `uvm_object_utils(coproc_job_info)

  function new(string name = "coproc_job_info");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf({"M=%0d N=%0d K=%0d (%0dx%0d tiles), clk ratio %.2f, ",
                      "gaps A/B %0d/%0d, C stalls %0d"},
                     m, n, k, tiles_m, tiles_n, clk_ratio, a_gaps, b_gaps, c_stalls);
  endfunction

endclass
