// One stream beat. A master sequence sets data and delay (idle cycles before TVALID); the monitor
// fills data and what it saw before the handshake: idle cycles since the previous beat (gap) and
// cycles the beat waited for TREADY (stall).

class axis_item extends uvm_sequence_item;

  bit [AXIS_MAX_DW-1:0] data;
  int unsigned          delay;
  int unsigned          gap;
  int unsigned          stall;

  `uvm_object_utils(axis_item)

  function new(string name = "axis_item");
    super.new(name);
  endfunction

  function void do_copy(uvm_object rhs);
    axis_item t;
    super.do_copy(rhs);
    $cast(t, rhs);
    data  = t.data;
    delay = t.delay;
    gap   = t.gap;
    stall = t.stall;
  endfunction

  function string convert2string();
    return $sformatf("data=0x%0h gap=%0d stall=%0d", data, gap, stall);
  endfunction

endclass
