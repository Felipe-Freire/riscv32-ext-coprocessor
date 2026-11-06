// Register file: x1..x31 in flip-flops, x0 hard-wired to 0. Two combinational read ports (ID)
// and one write port (WB).
//
// Write-through: a read of the register that WB writes in the same cycle returns the new value,
// so an instruction in ID sees the result of the instruction three ahead of it without
// forwarding. The registers have no reset (datapath state).
module rv32_regfile
  import rv32_pkg::*;
(
  input  logic            clk_i,

  input  logic [4:0]      rs1_addr_i,
  output logic [XLEN-1:0] rs1_data_o,
  input  logic [4:0]      rs2_addr_i,
  output logic [XLEN-1:0] rs2_data_o,

  input  logic [4:0]      rd_addr_i,
  input  logic [XLEN-1:0] rd_data_i,
  input  logic            rd_we_i
);

  logic [XLEN-1:0] regs_q [31:1];
  logic [XLEN-1:0] rf     [32];

  assign rf[0] = '0;

  // One enable per register, so synthesis can gate the clock of each 32-bit word.
  for (genvar i = 1; i < 32; i++) begin : gen_regs
    always_ff @(posedge clk_i) begin : reg_q
      if (rd_we_i && rd_addr_i == 5'(i)) begin
        regs_q[i] <= rd_data_i;
      end
    end
    assign rf[i] = regs_q[i];
  end

  assign rs1_data_o = (rd_we_i && rd_addr_i == rs1_addr_i && rs1_addr_i != '0) ? rd_data_i
                                                                               : rf[rs1_addr_i];
  assign rs2_data_o = (rd_we_i && rd_addr_i == rs2_addr_i && rs2_addr_i != '0) ? rd_data_i
                                                                               : rf[rs2_addr_i];

endmodule
