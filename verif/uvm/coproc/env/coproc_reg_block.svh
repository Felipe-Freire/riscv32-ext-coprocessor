// Register model of coproc_top (rtl/coproc/README.md), offsets from the block's base. The
// sequences use it to access registers by name; the golden model checks every access.

class coproc_reg_ctrl extends uvm_reg;

  rand uvm_reg_field start;

  `uvm_object_utils(coproc_reg_ctrl)

  function new(string name = "coproc_reg_ctrl");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    start = uvm_reg_field::type_id::create("start");
    // Writing 1 launches a job; the field always reads 0.
    start.configure(this, 1, 0, "WO", 1, 1'b0, 1, 1, 0);
  endfunction

endclass

class coproc_reg_status extends uvm_reg;

  uvm_reg_field busy;
  uvm_reg_field done;

  `uvm_object_utils(coproc_reg_status)

  function new(string name = "coproc_reg_status");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    busy = uvm_reg_field::type_id::create("busy");
    done = uvm_reg_field::type_id::create("done");
    busy.configure(this, 1, 0, "RO", 1, 1'b0, 1, 0, 0);
    done.configure(this, 1, 1, "W1C", 1, 1'b0, 1, 0, 0);
  endfunction

endclass

class coproc_reg_dim extends uvm_reg;

  rand uvm_reg_field value;

  `uvm_object_utils(coproc_reg_dim)

  function new(string name = "coproc_reg_dim");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    value = uvm_reg_field::type_id::create("value");
    value.configure(this, coproc_pkg::DIM_CNT_W, 0, "RW", 0, '0, 1, 1, 0);
  endfunction

endclass

class coproc_reg_block extends uvm_reg_block;

  rand coproc_reg_ctrl   ctrl;
  rand coproc_reg_status status;
  rand coproc_reg_dim    dim_m;
  rand coproc_reg_dim    dim_n;
  rand coproc_reg_dim    dim_k;

  `uvm_object_utils(coproc_reg_block)

  function new(string name = "coproc_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    ctrl   = coproc_reg_ctrl::type_id::create("ctrl");
    status = coproc_reg_status::type_id::create("status");
    dim_m  = coproc_reg_dim::type_id::create("dim_m");
    dim_n  = coproc_reg_dim::type_id::create("dim_n");
    dim_k  = coproc_reg_dim::type_id::create("dim_k");
    ctrl.configure(this);
    status.configure(this);
    dim_m.configure(this);
    dim_n.configure(this);
    dim_k.configure(this);
    ctrl.build();
    status.build();
    dim_m.build();
    dim_n.build();
    dim_k.build();

    default_map = create_map("map", 'h0, 4, UVM_LITTLE_ENDIAN);
    default_map.add_reg(ctrl, 'h00, "RW");
    default_map.add_reg(status, 'h04, "RW");
    default_map.add_reg(dim_m, 'h08, "RW");
    default_map.add_reg(dim_n, 'h0C, "RW");
    default_map.add_reg(dim_k, 'h10, "RW");
  endfunction

endclass
