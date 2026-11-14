// Register layer <-> AXI4-Lite items. The driver writes the response into the request, so the
// adapter does not use separate response items.

class axil_reg_adapter extends uvm_reg_adapter;

  `uvm_object_utils(axil_reg_adapter)

  function new(string name = "axil_reg_adapter");
    super.new(name);
    supports_byte_enable = 1;
    provides_responses   = 0;
  endfunction

  function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    axil_item t = axil_item::type_id::create("t");
    if (!t.randomize() with {kind == ((rw.kind == UVM_WRITE) ? AxilWrite : AxilRead);
                             addr == rw.addr[31:0];
                             data == rw.data[31:0];
                             strb == rw.byte_en[3:0];}) begin
      `uvm_fatal("ADAPTER", "Randomization failed")
    end
    return t;
  endfunction

  function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    axil_item t;
    if (!$cast(t, bus_item)) begin
      `uvm_fatal("ADAPTER", "Not an axil_item")
    end
    rw.kind   = (t.kind == AxilWrite) ? UVM_WRITE : UVM_READ;
    rw.addr   = t.addr;
    rw.data   = t.data;
    rw.status = (t.resp == 2'b00) ? UVM_IS_OK : UVM_NOT_OK;
  endfunction

endclass
