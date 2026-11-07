module rv32_redirect_logic
  import rv32_pkg::*;
(
  input  logic            jmp_i,
  input  logic [XLEN-1:0] imm_i,
  output logic            flush_id_o,
  output logic            flush_if_o,
  output logic            ex_redirect_o,
  output logic [XLEN-1:2] ex_target_o
);

  always_comb begin
    flush_id_o = 0;
    flush_if_o = 0;
    ex_redirect_o = 0;
    ex_target_o = imm_i;

    if (jmp_i) begin
      flush_id_o = 1;
      flush_if_o = 1;
      ex_redirect_o = 1;
    end
  end

endmodule