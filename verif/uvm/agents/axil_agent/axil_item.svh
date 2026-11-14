// One AXI4-Lite transaction. The sequence sets kind, addr, data and strb; the driver returns resp
// (and data, for a read). The delays are cycles before each valid / ready of the master.

typedef enum bit {
  AxilRead,
  AxilWrite
} axil_kind_e;

class axil_item extends uvm_sequence_item;

  rand axil_kind_e  kind;
  rand bit [31:0]   addr;
  rand bit [31:0]   data;
  rand bit [3:0]    strb;
  rand int unsigned aw_delay;
  rand int unsigned w_delay;
  rand int unsigned b_delay;
  rand int unsigned ar_delay;
  rand int unsigned r_delay;
  bit      [1:0]    resp;

  constraint c_strb {
    soft strb == 4'hF;
  }

  constraint c_delays {
    aw_delay <= 3;
    w_delay  <= 3;
    b_delay  <= 2;
    ar_delay <= 3;
    r_delay  <= 2;
  }

  `uvm_object_utils(axil_item)

  function new(string name = "axil_item");
    super.new(name);
  endfunction

  function void do_copy(uvm_object rhs);
    axil_item t;
    super.do_copy(rhs);
    $cast(t, rhs);
    kind     = t.kind;
    addr     = t.addr;
    data     = t.data;
    strb     = t.strb;
    aw_delay = t.aw_delay;
    w_delay  = t.w_delay;
    b_delay  = t.b_delay;
    ar_delay = t.ar_delay;
    r_delay  = t.r_delay;
    resp     = t.resp;
  endfunction

  function string convert2string();
    if (kind == AxilWrite) begin
      return $sformatf("write addr=0x%08h data=0x%08h strb=%04b resp=%0d", addr, data, strb, resp);
    end
    return $sformatf("read addr=0x%08h data=0x%08h resp=%0d", addr, data, resp);
  endfunction

endclass
