// Single-port RAM on the OpenRAM macros of FreePDK45 (MEM_TECH=openram45): the same name,
// parameters, ports and contract as the generic version (rtl/prim/prim_ram_1p.sv,
// rtl/prim/README.md), built from tiles of sram_sp_2048x32_m8 (2048 words of 32 bits, byte write
// mask; syn/tech/openram45).
//
// Rows x Cols tiles: Rows = ceil(Depth / 2048) stacked in depth, Cols = ceil(Width / 32) side by
// side in width. The upper address bits pick the row, every tile of that row takes the access, and
// each column holds 32 bits of the word, written under its 4 byte enables. A shape that is not a
// multiple of the macro leaves part of a tile unused: the address and data bits past the shape are
// tied to 0 and those bytes are never written (32 x 1024, the default shape, uses half a macro).
//
// The macro registers its inputs on the rising edge, reads and writes on the falling edge, and
// drives dout0 X from 1 ns after every rising edge until the falling edge of a read, plus its
// output delay. So rdata_o is valid in the cycle after a read, and X in every other cycle, which is
// the contract. A register of the row of the last access selects the row whose dout0 reaches
// rdata_o.
//
// Simulation only: bd_write and bd_read reach a word by its index through the mem array of the
// behavioral model of each macro. A hierarchical name cannot index generate blocks with a
// variable, so each tile registers an accessor object, before time 0, in an array the functions
// index.
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

  // The macro: sram_sp_2048x32_m8.
  localparam int unsigned MacroWidth     = 32;
  localparam int unsigned MacroDepth     = 2048;
  localparam int unsigned MacroAddrWidth = $clog2(MacroDepth);
  localparam int unsigned MacroBytes     = MacroWidth / 8;

  localparam int unsigned Rows    = (Depth + MacroDepth - 1) / MacroDepth;
  localparam int unsigned Cols    = (Width + MacroWidth - 1) / MacroWidth;
  localparam int unsigned RowBits = (Rows > 1) ? $clog2(Rows) : 1;
  // The word and the address, padded to whole tiles.
  localparam int unsigned PadWidth     = Cols * MacroWidth;
  localparam int unsigned PadAddrWidth = MacroAddrWidth + ((Rows > 1) ? $clog2(Rows) : 0);

  typedef logic [MacroWidth-1:0] macro_word_t;

  logic [PadAddrWidth-1:0] addr_pad;
  logic [PadWidth-1:0]     wdata_pad, rdata_pad;
  logic [PadWidth/8-1:0]   be_pad;
  logic [RowBits-1:0]      row, row_q;

  assign addr_pad  = PadAddrWidth'(addr_i);
  assign wdata_pad = PadWidth'(wdata_i);
  assign be_pad    = (PadWidth / 8)'(be_i);
  assign row       = (Rows > 1) ? RowBits'(addr_pad >> MacroAddrWidth) : '0;

  macro_word_t dout [Rows][Cols];

  // The row of the last access: its tiles drive rdata_o in the next cycle. No reset, as the RAM:
  // rdata_o is undefined until the first read anyway.
  always_ff @(posedge clk_i) begin : row_reg
    if (req_i) row_q <= row;
  end

  for (genvar c = 0; c < Cols; c++) begin : gen_rdata
    assign rdata_pad[c*MacroWidth +: MacroWidth] = dout[row_q][c];
  end
  assign rdata_o = rdata_pad[Width-1:0];

`ifndef SYNTHESIS
  virtual class tile_access_c;
    pure virtual function void write(input int unsigned word, input macro_word_t data);
    pure virtual function macro_word_t read(input int unsigned word);
  endclass

  tile_access_c tile_access [Rows][Cols];
`endif

  for (genvar r = 0; r < Rows; r++) begin : gen_row
    for (genvar c = 0; c < Cols; c++) begin : gen_col
      sram_sp_2048x32_m8 u_macro (
        .clk0  (clk_i),
        .csb0  (~(req_i && row == RowBits'(r))),
        .web0  (~we_i),
        .wmask0(be_pad[c*MacroBytes +: MacroBytes]),
        .addr0 (addr_pad[MacroAddrWidth-1:0]),
        .din0  (wdata_pad[c*MacroWidth +: MacroWidth]),
        .dout0 (dout[r][c])
      );

`ifndef SYNTHESIS
      // The accessor of this tile, registered by its constructor when the variable is
      // initialized, which happens before any initial block runs.
      class access_c extends tile_access_c;
        function new();
          tile_access[r][c] = this;
        endfunction
        virtual function void write(input int unsigned word, input macro_word_t data);
          u_macro.mem[word] = data;
        endfunction
        virtual function macro_word_t read(input int unsigned word);
          return u_macro.mem[word];
        endfunction
      endclass

      access_c access = new();
`endif
    end
  end

`ifndef SYNTHESIS
  function automatic void bd_write(input int unsigned index, input logic [Width-1:0] data);
    logic [PadWidth-1:0] data_pad = PadWidth'(data);
    for (int unsigned c = 0; c < Cols; c++) begin
      tile_access[index / MacroDepth][c].write(index % MacroDepth, data_pad[c*MacroWidth +: MacroWidth]);
    end
  endfunction

  function automatic logic [Width-1:0] bd_read(input int unsigned index);
    logic [PadWidth-1:0] data_pad;
    for (int unsigned c = 0; c < Cols; c++) begin
      data_pad[c*MacroWidth +: MacroWidth] = tile_access[index / MacroDepth][c].read(index % MacroDepth);
    end
    return data_pad[Width-1:0];
  endfunction

  // Checked at elaboration.
  if (Width == 0 || Width % 8 != 0) begin : gen_bad_width
    $fatal(1, "prim_ram_1p: Width %0d is not a multiple of 8", Width);
  end
  if (Depth == 0) begin : gen_bad_depth
    $fatal(1, "prim_ram_1p: Depth is 0");
  end

  // From the second edge on, as the generic version: a clock that starts at 1 has an edge at time
  // 0, before the logic in front of the RAM drives anything.
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
`endif

endmodule
