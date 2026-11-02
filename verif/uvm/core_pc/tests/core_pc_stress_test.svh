// Long random run with frequent stalls and redirects, mostly overlapping.

class core_pc_stress_test extends core_pc_base_test;

  `uvm_component_utils(core_pc_stress_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    core_pc_rand_seq rand_seq = core_pc_rand_seq::type_id::create("rand_seq");
    rand_seq.num_items = 20000;
    rand_seq.stall_pct = 50;
    rand_seq.set_pct   = 50;
    super.run_phase(phase);
    phase.raise_objection(this);
    rand_seq.start(env.agent.sqr);
    phase.drop_objection(this);
  endtask

endclass
