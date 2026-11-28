// Single-port RAM, generic behavioral version for simulation. The technology versions (same name,
// parameters and ports, rtl/prim/<tech>/) replace it through the primitive file list; see
// rtl/prim/README.md for the contract every version keeps:
//
//   - one access per cycle: req_i with we_i writes the bytes of wdata_i whose be_i bit is set,
//     req_i without we_i reads;
//   - read latency of one cycle: rdata_o holds the word in the cycle after the read, and only then.
//     In this model rdata_o is X in every other cycle, as in the OpenRAM macros, so no block comes
//     to depend on a macro that holds its output;
//   - no reset: the contents are unknown until written.
//
// This version is a flip-flop array: never synthesize it for a real memory.
//
// Simulation only: bd_write and bd_read reach a word by its index (the address) without a cycle,
// for testbenches that load or check the contents (programs, matrices).
module prim_ram_1p #(
  parameter  int unsigned Width     = 32,    // bits per word, a multiple of 8
  parameter  int unsigned Depth     = 1024,  // words
  localparam int unsigned AddrWidth = (Depth > 1) ? $clog2(Depth) : 1
) (
  input  logic                 clk_i,
  input  logic                 req_i,
  input  logic                 we_i,
  input  logic [AddrWidth-1:0] addr_i,
  input  logic [Width-1:0]     wdata_i,
  input  logic [Width/8-1:0]   be_i,
  output logic [Width-1:0]     rdata_o
);

  logic [Width-1:0] mem [Depth];
  logic [Width-1:0] rdata_q;

  // A plain always, not always_ff: bd_write writes the same array from the testbench, and a
  // variable of an always_ff block cannot have another writer.
  always @(posedge clk_i) begin : write_port
    if (req_i && we_i) begin
      for (int unsigned b = 0; b < Width / 8; b++) begin
        if (be_i[b]) mem[addr_i][8*b +: 8] <= wdata_i[8*b +: 8];
      end
    end
  end

  always_ff @(posedge clk_i) begin : read_port
    if (req_i && !we_i) rdata_q <= mem[addr_i];
  end

`ifndef SYNTHESIS
  // rdata_o only in the cycle after a read.
  logic read_q;

  always_ff @(posedge clk_i) begin : read_valid
    read_q <= req_i && !we_i;
  end

  assign rdata_o = read_q ? rdata_q : 'x;

  function automatic void bd_write(input int unsigned index, input logic [Width-1:0] data);
    mem[index] = data;
  endfunction

  function automatic logic [Width-1:0] bd_read(input int unsigned index);
    return mem[index];
  endfunction

  // Checked at elaboration.
  if (Width == 0 || Width % 8 != 0) begin : gen_bad_width
    $fatal(1, "prim_ram_1p: Width %0d is not a multiple of 8", Width);
  end
  if (Depth == 0) begin : gen_bad_depth
    $fatal(1, "prim_ram_1p: Depth is 0");
  end

  // From the second edge on: a clock that starts at 1 has an edge at time 0 (X to 1), before the
  // logic in front of the RAM drives anything.
  logic armed = 1'b0;

  always @(posedge clk_i) armed <= 1'b1;

  known_req : assert property (@(posedge clk_i) armed |-> !$isunknown(req_i))
    else $error("prim_ram_1p %m: req_i is X");
  known_cmd : assert property (@(posedge clk_i) armed && req_i |-> !$isunknown({we_i, addr_i}))
    else $error("prim_ram_1p %m: we_i or addr_i is X during an access");
  known_be  : assert property (@(posedge clk_i) armed && req_i && we_i |-> !$isunknown(be_i))
    else $error("prim_ram_1p %m: be_i is X during a write");
  in_range  : assert property (@(posedge clk_i) armed && req_i |-> addr_i < Depth)
    else $error("prim_ram_1p %m: address %0d past the last word %0d", addr_i, Depth - 1);
`else
  assign rdata_o = rdata_q;
`endif

endmodule
