// T14 cop_matmul_directed: COP-03 to COP-05. Chosen shapes and values, each with random stream
// behaviour: one tile with K = 1, rows and columns of tiles, a 64x64x64 product, the extremes,
// zero matrices and a long accumulation. +BIG_K adds K = 65535, the largest DIM_K.
//
// With int8 operands and K <= 65535, |C| <= 65535 * 2^14 < 2^31: the int32 wrap-around of the
// spec cannot happen through this port. The K = 65535 job of -128 values gets closest.

class coproc_matmul_directed_test extends coproc_base_test;

  `uvm_component_utils(coproc_matmul_directed_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function coproc_job make(int unsigned tm, int unsigned tn, int unsigned k, coproc_data_e data);
    coproc_job j = coproc_job::type_id::create("j");
    j.max_tiles = 8;
    j.max_k     = 65535;
    if (!j.randomize() with {tiles_m == tm; tiles_n == tn; k == local::k; data == local::data;})
    begin
      `uvm_fatal("TEST", "Job randomization failed")
    end
    return j;
  endfunction

  function void configure();
    cfg.min_jobs = 13;
  endfunction

  task main();
    coproc_job_vseq vseq = coproc_job_vseq::type_id::create("vseq");
    vseq.directed.push_back(make(1, 1, 1, DataRandom));
    vseq.directed.push_back(make(1, 1, 8, DataRandom));
    vseq.directed.push_back(make(1, 1, 64, DataExtreme));
    vseq.directed.push_back(make(2, 1, 3, DataRandom));
    vseq.directed.push_back(make(1, 2, 5, DataRandom));
    vseq.directed.push_back(make(3, 3, 17, DataRandom));
    vseq.directed.push_back(make(1, 6, 9, DataExtreme));
    vseq.directed.push_back(make(6, 1, 9, DataExtreme));
    vseq.directed.push_back(make(2, 2, 1, DataZero));
    vseq.directed.push_back(make(1, 1, 300, DataMinMax));
    vseq.directed.push_back(make(8, 8, 64, DataRandom));
    vseq.directed.push_back(make(1, 1, 4096, DataMinMax));
    vseq.directed.push_back(make(1, 1, 1, DataMinMax));
    if ($test$plusargs("BIG_K")) begin
      vseq.directed.push_back(make(1, 1, 65535, DataMinMax));
    end
    vseq.start(env.vseqr);
  endtask

endclass
