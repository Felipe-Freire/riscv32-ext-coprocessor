// One clock cycle of core_pc. The driver uses the input fields; the monitor fills all fields,
// with the values sampled just before the rising edge.

class core_pc_seq_item extends uvm_sequence_item;

  rand bit        stall;
  rand bit        pc_set;
  rand bit [31:0] pc_target;

  // Observed only
  logic           rst_n;
  logic [31:0]    pc;

  constraint c_target_aligned { pc_target[1:0] == 2'b00; }

  `uvm_object_utils_begin(core_pc_seq_item)
    `uvm_field_int(stall,     UVM_ALL_ON)
    `uvm_field_int(pc_set,    UVM_ALL_ON)
    `uvm_field_int(pc_target, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(rst_n,     UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_field_int(pc,        UVM_ALL_ON | UVM_NOCOMPARE | UVM_HEX)
  `uvm_object_utils_end

  function new(string name = "core_pc_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("rst_n=%b stall=%b pc_set=%b pc_target=0x%08h pc=0x%08h",
                     rst_n, stall, pc_set, pc_target, pc);
  endfunction

endclass
