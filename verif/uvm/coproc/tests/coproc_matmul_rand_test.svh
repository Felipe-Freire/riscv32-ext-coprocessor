// T15 cop_matmul_rand: COP-03, COP-06, COP-07. Random jobs back to back (+JOBS, default 40), each
// with its own dimensions, data, gaps in A and B and back-pressure on C.

class coproc_matmul_rand_test extends coproc_base_test;

  `uvm_component_utils(coproc_matmul_rand_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    cfg.min_jobs = plusarg_jobs(40);
  endfunction

  task main();
    coproc_job_vseq vseq = coproc_job_vseq::type_id::create("vseq");
    vseq.num_jobs = cfg.min_jobs;
    vseq.start(env.vseqr);
  endtask

endclass
