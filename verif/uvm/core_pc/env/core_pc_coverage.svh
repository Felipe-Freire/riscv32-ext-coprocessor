class core_pc_coverage extends uvm_subscriber #(core_pc_seq_item);

  core_pc_seq_item tr;

  covergroup cg;
    option.per_instance = 1;

    cp_stall: coverpoint tr.stall;
    cp_set:   coverpoint tr.pc_set;
    cx_ctrl:  cross cp_stall, cp_set;   // Includes redirect during a stall

    cp_target: coverpoint tr.pc_target iff (tr.pc_set) {
      bins zero = {32'h0000_0000};
      bins low  = {[32'h0000_0004 : 32'h7FFF_FFFC]};
      bins high = {[32'h8000_0000 : 32'hFFFF_FFF8]};
      bins top  = {32'hFFFF_FFFC};
    }

    // Increment from the last word: the PC wraps to 0
    cp_wrap: coverpoint tr.pc iff (!tr.stall && !tr.pc_set) {
      bins wrap = {32'hFFFF_FFFC};
    }

    // Control sequences over consecutive cycles
    cp_ctrl_seq: coverpoint {tr.stall, tr.pc_set} {
      bins stall_then_run      = (2'b10 => 2'b00);
      bins redirect_then_stall = (2'b01, 2'b11 => 2'b10);
      bins redirect_twice      = (2'b01 => 2'b01);
    }
  endgroup

  `uvm_component_utils(core_pc_coverage)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg = new();
  endfunction

  function void write(core_pc_seq_item t);
    if (t.rst_n !== 1'b1) return;
    tr = t;
    cg.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("Functional coverage: %.1f%%", cg.get_coverage()), UVM_NONE)
  endfunction

endclass
