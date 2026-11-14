// T17 cop_reset_negative, reset part: COP-09. A job is cut by a reset at a random point (loading,
// draining or sending C), then a clean job must run and match the model. Repeated +JOBS times
// (default 6). Dimensions outside the spec (COP-10) wait for the decision on point P1.

class coproc_reset_test extends coproc_base_test;

  `uvm_component_utils(coproc_reset_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    cfg.min_jobs = plusarg_jobs(6);
  endfunction

  task main();
    for (int unsigned i = 0; i < cfg.min_jobs; i++) begin
      cut_job();
      clean_job();
    end
  endtask

  // Starts a random job and resets the block in the middle of it.
  task cut_job();
    coproc_job_vseq vseq = coproc_job_vseq::type_id::create("cut");
    process         p;
    event           started;
    vseq.num_jobs      = 1;
    vseq.job.max_tiles = 3;
    vseq.job.max_k     = 64;
    fork
      begin
        p = process::self();
        -> started;
        vseq.start(env.vseqr);
      end
    join_none
    wait (started.triggered);
    repeat ($urandom_range(400, 5)) @(posedge tb_vif.clk_sys);

    // The reset first: the drivers drop what they are doing and finish their items. Then the
    // sequences that were feeding them, and the register model's locks, can go.
    tb_vif.reset($urandom_range(20, 2));
    if (p.status() != process::FINISHED) begin
      p.kill();
    end
    env.vseqr.stop_sequences();
    env.axil_agt.sqr.stop_sequences();
    env.a_agt.sqr.stop_sequences();
    env.b_agt.sqr.stop_sequences();
    env.regmodel.reset();
    `uvm_info("TEST", "Job cut by a reset", UVM_MEDIUM)
  endtask

  task clean_job();
    coproc_job_vseq vseq = coproc_job_vseq::type_id::create("clean");
    vseq.num_jobs      = 1;
    vseq.job.max_tiles = 3;
    vseq.job.max_k     = 64;
    vseq.start(env.vseqr);
  endtask

endclass
