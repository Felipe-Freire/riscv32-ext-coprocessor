// Holds the address of the instruction being fetched, in 4-byte words (bits 1:0 are always 0).
// Every cycle it advances by 4, unless the pipeline is stalled (hold) or a stage further down
// redirects the fetch (taken branch, jump, trap to mtvec, MRET to mepc). The fetch stage picks the
// redirect target; this module only registers it. A redirect wins over a stall so that it is
// never lost.

module rv32_pc
  import rv32_pkg::*;
#(
  parameter logic [XLEN-1:0] BootAddr = 32'h0000_0000
) (
  input  logic            clk_i,
  input  logic            rst_ni,

  input  logic            stall_i,      // Hold the current PC
  input  logic            pc_set_i,     // Redirect the fetch to pc_target_i
  input  logic [XLEN-1:2] pc_target_i,  // Redirect address

  output logic [XLEN-1:2] pc_o          // Fetch address
);

  logic [XLEN-1:2] pc_d, pc_q;

  assign pc_d = pc_set_i ? pc_target_i : pc_q + 1'b1;

  always_ff @(posedge clk_i or negedge rst_ni) begin : pc_reg
    if (!rst_ni) begin
      pc_q <= BootAddr[XLEN-1:2];
    end else if (pc_set_i || !stall_i) begin
      pc_q <= pc_d;
    end
  end

  assign pc_o = pc_q;

endmodule
