// A series of jobs: the ready-made ones in `directed` if a test filled it, otherwise num_jobs
// randomizations of `job`. A test bounds the random jobs through job.max_tiles and job.max_k, or
// replaces `job` with a subclass that adds constraints.

class coproc_job_vseq extends coproc_base_vseq;

  int unsigned num_jobs = 10;
  coproc_job   directed[$];
  coproc_job   job;

  `uvm_object_utils(coproc_job_vseq)

  function new(string name = "coproc_job_vseq");
    super.new(name);
    job = coproc_job::type_id::create("job");
  endfunction

  // Runs before each job; a test overrides it, e.g. to change the clock ratio between jobs.
  virtual task before_job(int unsigned idx);
  endtask

  task body();
    if (directed.size() > 0) begin
      foreach (directed[i]) begin
        before_job(i);
        run_job(directed[i]);
      end
    end else begin
      for (int unsigned i = 0; i < num_jobs; i++) begin
        before_job(i);
        if (!job.randomize()) begin
          `uvm_fatal("VSEQ", "Job randomization failed")
        end
        run_job(job);
      end
    end
  endtask

endclass
