// Single accesses, for addresses the register model does not cover (outside the map, unaligned,
// partial WSTRB). After start(), resp holds the response and, for a read, data the read value.

class axil_write_seq extends uvm_sequence #(axil_item);

  rand bit [31:0] addr;
  rand bit [31:0] data;
  rand bit [3:0]  strb;
  bit      [1:0]  resp;

  constraint c_strb {
    soft strb == 4'hF;
  }

  `uvm_object_utils(axil_write_seq)

  function new(string name = "axil_write_seq");
    super.new(name);
  endfunction

  task body();
    axil_item t = axil_item::type_id::create("t");
    start_item(t);
    if (!t.randomize() with {kind == AxilWrite; addr == local::addr; data == local::data;
                             strb == local::strb;}) begin
      `uvm_fatal("SEQ", "Randomization failed")
    end
    finish_item(t);
    resp = t.resp;
  endtask

endclass

class axil_read_seq extends uvm_sequence #(axil_item);

  rand bit [31:0] addr;
  bit      [31:0] data;
  bit      [1:0]  resp;

  `uvm_object_utils(axil_read_seq)

  function new(string name = "axil_read_seq");
    super.new(name);
  endfunction

  task body();
    axil_item t = axil_item::type_id::create("t");
    start_item(t);
    if (!t.randomize() with {kind == AxilRead; addr == local::addr;}) begin
      `uvm_fatal("SEQ", "Randomization failed")
    end
    finish_item(t);
    data = t.data;
    resp = t.resp;
  endtask

endclass
