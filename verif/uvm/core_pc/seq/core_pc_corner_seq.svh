// Directed corner cases: wrap-around at the top of the address space, redirect to 0, redirect
// during a stall, back-to-back redirects.

class core_pc_corner_seq extends uvm_sequence #(core_pc_seq_item);

  `uvm_object_utils(core_pc_corner_seq)

  function new(string name = "core_pc_corner_seq");
    super.new(name);
  endfunction

  task send(bit stall, bit pc_set, bit [31:0] pc_target = '0);
    req = core_pc_seq_item::type_id::create("req");
    start_item(req);
    req.stall     = stall;
    req.pc_set    = pc_set;
    req.pc_target = pc_target;
    finish_item(req);
  endtask

  task body();
    send(1'b0, 1'b1, 32'hFFFF_FFF8);  // Redirect near the top
    send(1'b0, 1'b0);                 // 0xFFFF_FFFC
    send(1'b0, 1'b0);                 // Wraps to 0
    send(1'b0, 1'b1, 32'hFFFF_FFFC);  // Redirect to the last word
    send(1'b0, 1'b0);                 // Wraps to 0
    send(1'b0, 1'b1, 32'h0000_0000);  // Redirect to 0
    send(1'b1, 1'b1, 32'h0000_2000);  // Redirect during a stall
    send(1'b1, 1'b0);                 // Stall after the redirect
    send(1'b0, 1'b0);                 // Resume
    send(1'b0, 1'b1, 32'h0000_4000);  // Back-to-back redirects
    send(1'b0, 1'b1, 32'h0000_5000);
    send(1'b0, 1'b0);
  endtask

endclass
