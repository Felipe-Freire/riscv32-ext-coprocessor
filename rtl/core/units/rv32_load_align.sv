// Load alignment (MEM): moves the loaded byte or halfword down to bit 0 and sign- or zero-extends
// it. The memory returns the whole word that holds the access.
module rv32_load_align
  import rv32_pkg::*;
(
  input  logic [1:0]      addr_i,        // address bits 1:0
  input  logic [2:0]      funct3_i,      // [1:0] access size, [2] zero-extend
  input  logic [XLEN-1:0] data_i,        // word from the data port
  output logic [XLEN-1:0] data_o
);

  logic [XLEN-1:0] shifted;

  assign shifted = data_i >> {addr_i, 3'b000};

  always_comb begin : extend
    unique case (funct3_i[1:0])
      2'b00:   data_o = funct3_i[2] ? {24'b0, shifted[7:0]}  : {{24{shifted[7]}},  shifted[7:0]};
      2'b01:   data_o = funct3_i[2] ? {16'b0, shifted[15:0]} : {{16{shifted[15]}}, shifted[15:0]};
      default: data_o = data_i;
    endcase
  end

endmodule
