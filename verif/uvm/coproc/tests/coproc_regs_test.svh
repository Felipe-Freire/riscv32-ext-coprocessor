// T13 cop_regs: COP-01, COP-02.

class coproc_regs_test extends coproc_base_test;

  `uvm_component_utils(coproc_regs_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configure();
    cfg.min_jobs = 3;
  endfunction

  task main();
    coproc_regs_vseq vseq = coproc_regs_vseq::type_id::create("vseq");
    vseq.start(env.vseqr);
  endtask

endclass
