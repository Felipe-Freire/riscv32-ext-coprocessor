// Directed corner cases, then random cycles with the default stall and redirect rates.

class core_pc_smoke_test extends core_pc_base_test;

  `uvm_component_utils(core_pc_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    core_pc_corner_seq corner_seq = core_pc_corner_seq::type_id::create("corner_seq");
    core_pc_rand_seq   rand_seq   = core_pc_rand_seq::type_id::create("rand_seq");
    super.run_phase(phase);
    phase.raise_objection(this);
    corner_seq.start(env.agent.sqr);
    rand_seq.start(env.agent.sqr);
    phase.drop_objection(this);
  endtask

endclass
