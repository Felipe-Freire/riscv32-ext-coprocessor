// SystemVerilog view of the coprocessor golden model (coproc_model.h), through DPI-C. Compile
// coproc_model.cc with the simulation (xrun takes it on the command line).
package coproc_model_pkg;

  parameter int unsigned COPROC_RESP_OKAY   = 0;
  parameter int unsigned COPROC_RESP_SLVERR = 2;

  parameter int unsigned COPROC_REG_CTRL   = 'h00;
  parameter int unsigned COPROC_REG_STATUS = 'h04;
  parameter int unsigned COPROC_REG_DIM_M  = 'h08;
  parameter int unsigned COPROC_REG_DIM_N  = 'h0C;
  parameter int unsigned COPROC_REG_DIM_K  = 'h10;

  import "DPI-C" function chandle coproc_model_new(int unsigned dim, int unsigned dim_bits);
  import "DPI-C" function void coproc_model_free(chandle m);
  import "DPI-C" function void coproc_model_reset(chandle m);

  import "DPI-C" function int unsigned coproc_model_reg_write(chandle m, int unsigned offset,
                                                              int unsigned data,
                                                              int unsigned strb);
  import "DPI-C" function int unsigned coproc_model_reg_read(chandle m, int unsigned offset,
                                                             output int unsigned data);

  import "DPI-C" function void coproc_model_push_a(chandle m, longint unsigned beat);
  import "DPI-C" function void coproc_model_push_b(chandle m, longint unsigned beat);
  import "DPI-C" function int coproc_model_pop_c(chandle m, output int unsigned word);
  import "DPI-C" function void coproc_model_c_pos(chandle m, output int unsigned ti,
                                                  output int unsigned tj, output int unsigned row,
                                                  output int unsigned col);

  import "DPI-C" function int coproc_model_busy(chandle m);
  import "DPI-C" function int unsigned coproc_model_pending_a(chandle m);
  import "DPI-C" function int unsigned coproc_model_pending_b(chandle m);
  import "DPI-C" function int unsigned coproc_model_jobs(chandle m);

endpackage
