// prim_ram_1p: the contract of rtl/prim/README.md, on the two shapes the SoC uses (32 x 8192 for the
// TCMs, 128 x 2048 for an L2 bank), with whichever version the primitive file list compiles.
//
// Each shape runs, against a reference array:
//   1. backdoor: bd_write fills every word, front-door reads check a sample of them;
//   2. random accesses, one per cycle with no gaps forced: reads, writes with random byte enables
//      and idle cycles, half of them on 16 hot addresses so reads often follow writes to the same
//      word, plus the first and the last word;
//   3. the read data one cycle after every read, and X one cycle after a write or an idle cycle
//      (the model holds no output, like the OpenRAM macros);
//   4. backdoor: bd_read of every word against the reference at the end.
// +OPS=<n> sets the random accesses per shape (default 20000).

// One shape: its RAM, the driver and the checks.
module tb_prim_ram_1p_shape #(
  parameter int unsigned Width = 32,
  parameter int unsigned Depth = 1024
) (
  input  logic clk,
  output logic done,
  output int   errors
);

  localparam int unsigned AddrWidth = $clog2(Depth);
  localparam int unsigned NumBytes  = Width / 8;
  localparam int unsigned HotWords  = 16;

  typedef logic [Width-1:0] word_t;

  logic                 req, we;
  logic [AddrWidth-1:0] addr;
  word_t                wdata, rdata;
  logic [NumBytes-1:0]  be;

  prim_ram_1p #(
    .Width(Width),
    .Depth(Depth)
  ) u_ram (
    .clk_i  (clk),
    .req_i  (req),
    .we_i   (we),
    .addr_i (addr),
    .wdata_i(wdata),
    .be_i   (be),
    .rdata_o(rdata)
  );

  // Inputs change 1 ns after the edge; rdata is sampled just before the next one.
  clocking cb @(posedge clk);
    default input #1step output #1ns;
    output req, we, addr, wdata, be;
    input  rdata;
  endclocking

  // An access whose response is still on its way: rdata holds it two edges after it is driven.
  typedef struct {
    bit    read;
    word_t expected;
    int    addr;
  } access_t;

  word_t   model [Depth];
  access_t in_flight [$];
  int      ops, reads, writes;

  function automatic word_t random_word();
    word_t w;
    for (int i = 0; i < Width; i += 32) w[i +: 32] = $urandom();
    return w;
  endfunction

  function automatic int random_addr(int hot_base);
    int r = $urandom_range(99);
    if (r < 2)  return 0;
    if (r < 4)  return Depth - 1;
    if (r < 52) return hot_base + $urandom_range(HotWords - 1);
    return $urandom_range(Depth - 1);
  endfunction

  // Drive one access (or an idle cycle) and check the response of the one two edges back.
  task automatic cycle(bit do_req, bit do_we, int a, word_t data, logic [NumBytes-1:0] mask);
    access_t acc;

    @(cb);
    if (in_flight.size() == 2) begin
      acc = in_flight.pop_front();
      if (acc.read && cb.rdata !== acc.expected) begin
        errors++;
        $error("%0d x %0d: read of word %0d returned %h, expected %h", Width, Depth, acc.addr,
               cb.rdata, acc.expected);
      end else if (!acc.read && !$isunknown(cb.rdata)) begin
        errors++;
        $error("%0d x %0d: rdata %h after a cycle without a read, expected X", Width, Depth,
               cb.rdata);
      end
    end

    cb.req   <= do_req;
    cb.we    <= do_we;
    cb.addr  <= do_req ? AddrWidth'(a) : 'x;
    cb.wdata <= do_req && do_we ? data : 'x;
    cb.be    <= do_req && do_we ? mask : 'x;

    acc = '{read: do_req && !do_we, expected: 'x, addr: a};
    if (acc.read) acc.expected = model[a];
    if (do_req && do_we) begin
      for (int b = 0; b < NumBytes; b++) begin
        if (mask[b]) model[a][8*b +: 8] = data[8*b +: 8];
      end
    end
    in_flight.push_back(acc);
  endtask

  initial begin
    int hot_base, r;

    errors = 0;
    done   = 1'b0;
    if (!$value$plusargs("OPS=%d", ops)) ops = 20000;
    req = 1'b0;
    hot_base = $urandom_range(Depth - HotWords);

    // 1. Backdoor fill, then front-door reads of a sample.
    for (int i = 0; i < Depth; i++) begin
      model[i] = random_word();
      u_ram.bd_write(i, model[i]);
    end
    repeat (2) cycle(1'b0, 1'b0, 0, '0, '0);
    for (int i = 0; i < 256; i++) cycle(1'b1, 1'b0, random_addr(hot_base), '0, '0);

    // 2. and 3. Random accesses.
    for (int i = 0; i < ops; i++) begin
      r = $urandom_range(99);
      if (r < 15) begin
        cycle(1'b0, 1'b0, 0, '0, '0);
      end else if (r < 55) begin
        cycle(1'b1, 1'b1, random_addr(hot_base), random_word(),
              ($urandom_range(3) == 0) ? '1 : NumBytes'($urandom()));
        writes++;
      end else begin
        cycle(1'b1, 1'b0, random_addr(hot_base), '0, '0);
        reads++;
      end
    end
    repeat (2) cycle(1'b0, 1'b0, 0, '0, '0);   // drain the last responses

    // 4. Backdoor read of every word.
    for (int i = 0; i < Depth; i++) begin
      if (u_ram.bd_read(i) !== model[i]) begin
        errors++;
        $error("%0d x %0d: bd_read of word %0d returned %h, expected %h", Width, Depth, i,
               u_ram.bd_read(i), model[i]);
      end
    end

    $display("%0d x %0d: %0d reads, %0d writes, %0d errors", Width, Depth, reads, writes, errors);
    done = 1'b1;
  end

endmodule

module tb_prim_ram_1p;

  logic       clk = 1'b0;
  logic [1:0] done;
  int         errors [2];

  always #5 clk = ~clk;

  tb_prim_ram_1p_shape #(.Width(32),  .Depth(8192)) u_tcm (.clk, .done(done[0]), .errors(errors[0]));
  tb_prim_ram_1p_shape #(.Width(128), .Depth(2048)) u_l2  (.clk, .done(done[1]), .errors(errors[1]));

  initial begin
    fork
      wait (&done);
      begin
        #10ms;
        $fatal(1, "timeout");
      end
    join_any
    if (errors[0] + errors[1] != 0) $fatal(1, "%0d errors", errors[0] + errors[1]);
    $display("PASS: both shapes match the reference");
    $finish;
  end

endmodule
