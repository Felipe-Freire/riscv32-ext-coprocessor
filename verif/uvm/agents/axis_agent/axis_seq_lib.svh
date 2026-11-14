// Sends a list of beats. Before each beat, with probability gap_pct %, the master waits 1 to
// max_gap idle cycles.

class axis_beats_seq extends uvm_sequence #(axis_item);

  bit [AXIS_MAX_DW-1:0] beats[$];
  int unsigned          gap_pct = 0;
  int unsigned          max_gap = 4;

  `uvm_object_utils(axis_beats_seq)

  function new(string name = "axis_beats_seq");
    super.new(name);
  endfunction

  task body();
    axis_item t;
    foreach (beats[i]) begin
      t = axis_item::type_id::create("t");
      start_item(t);
      t.data  = beats[i];
      t.delay = (gap_pct > 0 && $urandom_range(99) < gap_pct) ? $urandom_range(max_gap, 1) : 0;
      finish_item(t);
    end
  endtask

endclass
