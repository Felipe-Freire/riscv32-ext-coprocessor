// Reference model of the PC: reset loads boot_addr, then redirect > stall > +4. Every cycle out of
// reset, the PC observed by the monitor must match the model.

class core_pc_scoreboard extends uvm_scoreboard;

  uvm_analysis_imp #(core_pc_seq_item, core_pc_scoreboard) analysis_export;

  core_pc_env_cfg cfg;

  logic [31:0] pc_exp;
  bit          model_valid;   // Set by the first reset
  int unsigned num_checks;
  int unsigned num_errors;

  `uvm_component_utils(core_pc_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    analysis_export = new("analysis_export", this);
  endfunction

  function void write(core_pc_seq_item tr);
    if (tr.rst_n !== 1'b1) begin
      pc_exp      = cfg.boot_addr;
      model_valid = 1'b1;
      return;
    end
    if (!model_valid) return;

    num_checks++;
    if (tr.pc !== pc_exp) begin
      num_errors++;
      `uvm_error("SCB", $sformatf("pc = 0x%08h, expected 0x%08h (%s)",
                                  tr.pc, pc_exp, tr.convert2string()))
    end

    if (tr.pc_set) begin
      pc_exp = tr.pc_target;
    end else if (!tr.stall) begin
      pc_exp = pc_exp + 32'd4;
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB", $sformatf("%0d checks, %0d errors", num_checks, num_errors), UVM_NONE)
    if (num_checks == 0) begin
      `uvm_error("SCB", "No PC was checked")
    end
  endfunction

endclass
