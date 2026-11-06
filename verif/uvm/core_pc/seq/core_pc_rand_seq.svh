// Random cycles: stall and redirect each with a configurable probability, aligned random targets.

class core_pc_rand_seq extends uvm_sequence #(core_pc_seq_item);

  int unsigned num_items = 1000;
  int unsigned stall_pct = 25;
  int unsigned set_pct   = 12;

  `uvm_object_utils(core_pc_rand_seq)

  function new(string name = "core_pc_rand_seq");
    super.new(name);
  endfunction

  task body();
    repeat (num_items) begin
      req = core_pc_seq_item::type_id::create("req");
      start_item(req);
      if (!req.randomize() with {
            stall  dist {1'b1 := stall_pct, 1'b0 := 100 - stall_pct};
            pc_set dist {1'b1 := set_pct,   1'b0 := 100 - set_pct};
          }) begin
        `uvm_fatal("SEQ", "Randomization failed")
      end
      finish_item(req);
    end
  endtask

endclass
