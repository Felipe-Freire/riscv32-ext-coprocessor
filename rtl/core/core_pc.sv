// Holds the address of the instruction being fetched. Every cycle it advances by 4, unless the
// pipeline is stalled (hold) or a stage further down redirects the fetch (taken branch, jump, trap
// to mtvec, MRET to mepc). The controller picks the redirect target; this module only registers it.
// A redirect wins over a stall so that it is never lost.

module core_pc #(
  parameter logic [31:0] BootAddr = 32'h0000_0000
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        stall_i,      // Hold the current PC
  input  logic        pc_set_i,     // Redirect the fetch to pc_target_i
  input  logic [31:0] pc_target_i,  // Redirect address, 4-byte aligned

  output logic [31:0] pc_o          // Fetch address
);

  logic [31:0] pc_d, pc_q;

  always_comb begin
    if (pc_set_i) begin
      pc_d = pc_target_i;
    end else if (stall_i) begin
      pc_d = pc_q;
    end else begin
      pc_d = pc_q + 32'd4;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q <= BootAddr;
    end else begin
      pc_q <= pc_d;
    end
  end

  assign pc_o = pc_q;

endmodule
