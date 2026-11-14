// Virtual sequencer: the handles the coprocessor sequences need.

class coproc_vseqr extends uvm_sequencer;

  coproc_env_cfg    cfg;
  axil_sequencer    axil_sqr;
  axis_sequencer    a_sqr;
  axis_sequencer    b_sqr;
  coproc_reg_block  regmodel;
  coproc_scoreboard scb;

  `uvm_component_utils(coproc_vseqr)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass
