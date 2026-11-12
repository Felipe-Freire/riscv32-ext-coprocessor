// Store alignment (EX): places the store data on its byte lanes and builds the byte enables of any
// load or store.
//
// A halfword or word access that is not naturally aligned is misaligned: EX sends no request and
// the instruction traps in MEM.
module rv32_store_align
  import rv32_pkg::*;
(
  input  logic [1:0]      addr_i,        // address bits 1:0
  input  logic [2:0]      funct3_i,      // [1:0] access size
  input  logic [XLEN-1:0] data_i,        // rs2
  output logic [3:0]      be_o,
  output logic [XLEN-1:0] data_o,
  output logic            misaligned_o
);

  always_comb begin : align
    unique case (funct3_i[1:0])
      2'b00: begin
        be_o         = 4'b0001 << addr_i;
        data_o       = {4{data_i[7:0]}};
        misaligned_o = 1'b0;
      end
      2'b01: begin
        be_o         = 4'b0011 << addr_i;
        data_o       = {2{data_i[15:0]}};
        misaligned_o = addr_i[0];
      end
      default: begin
        be_o         = 4'b1111;
        data_o       = data_i;
        misaligned_o = (addr_i != 2'b00);
      end
    endcase
  end

endmodule
