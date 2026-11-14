// T16 cop_cdc: COP-08. Random jobs (+JOBS, default 24) with the array clock changed before each
// one: from 4x faster to 4x slower than clk_i, and sometimes equal. The first job also starts
// with a random phase between the two clocks.

class coproc_cdc_vseq extends coproc_job_vseq;

  realtime periods[] = '{2.5ns, 4ns, 5ns, 7.5ns, 10ns, 10ns, 12.5ns, 20ns, 30ns, 40ns};

  `uvm_object_utils(coproc_cdc_vseq)

  function new(string name = "coproc_cdc_vseq");
    super.new(name);
  endfunction

  task before_job(int unsigned idx);
    p_sequencer.cfg.tb_vif.acc_period = periods[$urandom_range(periods.size() - 1)];
    `uvm_info("VSEQ", $sformatf("clk_acc_i period %0.2f ns", p_sequencer.cfg.tb_vif.acc_period),
              UVM_MEDIUM)
  endtask

endclass

class coproc_cdc_test extends coproc_base_test;

  `uvm_component_utils(coproc_cdc_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    cfg.min_jobs      = plusarg_jobs(24);
    tb_vif.acc_period = 7.5ns;
    tb_vif.acc_phase  = 1ns * $urandom_range(9);
  endfunction

  task main();
    coproc_cdc_vseq vseq = coproc_cdc_vseq::type_id::create("vseq");
    vseq.num_jobs = cfg.min_jobs;
    vseq.start(env.vseqr);
  endtask

endclass
