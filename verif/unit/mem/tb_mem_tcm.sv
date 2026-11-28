// mem_tcm: the OBI protocol of rtl/mem/README.md on the two TCMs of the SoC, with whichever
// primitives MEM_TECH compiles (generic by default, the OpenRAM macros with MEM_TECH=openram45).
//
//   D-TCM  HoldRdata = 0: random loads and stores with random byte enables and idle cycles, half of
//          them on 16 hot words so loads often follow stores to the same word
//   I-TCM  HoldRdata = 1: loads only, as the fetch port: sequential words with random jumps, and
//          the request low for random runs of cycles, as when the pipeline stalls
//
// Every cycle, against a reference array loaded with the same random words as the TCM (bd_write):
//   - gnt in the cycle of each request;
//   - rvalid exactly one cycle after each request, and only then; err always 0;
//   - with the rvalid of a load, the word loaded; in every other cycle 0 (D-TCM) or the word of the
//     last load, 0 before the first one (I-TCM);
// and at the end bd_read of every word against the reference.
// +OPS=<n> sets the accesses of each TCM (default 20000).

// One TCM: the DUT, its driver and the checks.
module tb_mem_tcm_port
  import soc_pkg::*;
#(
  parameter bit          HoldRdata = 1'b0,
  parameter bit          Stores    = 1'b1,  // loads and stores; loads only otherwise
  parameter int unsigned SizeBytes = 32'h8000,
  parameter logic [31:0] Base      = DTCM_BASE
) (
  input  logic clk,
  input  logic rst_n,
  output logic done,
  output int   errors
);

  localparam int unsigned Depth    = SizeBytes / 4;
  localparam int unsigned HotWords = 16;
  localparam string       Name     = HoldRdata ? "I-TCM" : "D-TCM";

  obi_req_t req;
  obi_rsp_t rsp;

  mem_tcm #(
    .SizeBytes(SizeBytes),
    .HoldRdata(HoldRdata)
  ) u_tcm (
    .clk_i    (clk  ),
    .rst_ni   (rst_n),
    .obi_req_i(req  ),
    .obi_rsp_o(rsp  )
  );

  // Requests change 1 ns after the edge; the response is sampled just before the next one.
  clocking cb @(posedge clk);
    default input #1step output #1ns;
    output req;
    input  rsp;
  endclocking

  // An access and the response it expects.
  typedef struct {
    bit          req;
    bit          load;
    logic [31:0] expected;
  } access_t;

  logic [31:0] model [Depth];
  logic [31:0] last_load = '0;  // what the I-TCM holds
  access_t     prev      = '{default: '0};
  int          ops, loads, stores, idles, checks;

  function automatic void check(input bit cond, input string msg);
    checks++;
    if (!cond) begin
      errors++;
      $error("%s: %s", Name, msg);
    end
  endfunction

  // Drives one cycle, then checks at the edge that ends it: gnt of this access, and the response of
  // the access of the cycle before, which the TCM gives in this one.
  task automatic cycle(input bit valid, input bit we, input int unsigned index, input logic [31:0] wdata,
                       input logic [3:0] be);
    access_t now = '{default: '0};
    cb.req <= '{req: valid, addr: Base + 4 * index, we: we, be: be, wdata: wdata};
    if (valid && !we) now = '{req: 1'b1, load: 1'b1, expected: model[index]};
    if (valid && we) begin
      now.req = 1'b1;
      for (int b = 0; b < 4; b++) if (be[b]) model[index][8*b +: 8] = wdata[8*b +: 8];
    end
    @(cb);
    if (valid) check(cb.rsp.gnt === 1'b1, "no gnt in the cycle of the request");
    check(cb.rsp.rvalid === prev.req, $sformatf("rvalid %b, expected %b", cb.rsp.rvalid, prev.req));
    check(cb.rsp.err === 1'b0, "err set");
    if (prev.load) begin
      check(cb.rsp.rdata === prev.expected,
            $sformatf("load returned %h, expected %h", cb.rsp.rdata, prev.expected));
      last_load = prev.expected;
    end else begin
      check(cb.rsp.rdata === (HoldRdata ? last_load : 32'h0),
            $sformatf("rdata %h with no load response, expected %h", cb.rsp.rdata,
                      HoldRdata ? last_load : 32'h0));
    end
    prev = now;
  endtask

  initial begin
    int unsigned hot_base, index, r;

    errors = 0;
    done   = 1'b0;
    checks = 0;
    if (!$value$plusargs("OPS=%d", ops)) ops = 20000;
    req = '0;
    hot_base = $urandom_range(Depth - HotWords);
    for (int i = 0; i < Depth; i++) begin
      model[i] = $urandom();
      u_tcm.bd_write(i, model[i]);
    end
    @(posedge rst_n);
    repeat (2) @(cb);

    index = 0;
    for (int i = 0; i < ops; i++) begin
      r = $urandom_range(99);
      if (Stores) begin
        // D-TCM: idle, store or load, half of the accesses on the hot words.
        index = ($urandom_range(1)) ? hot_base + $urandom_range(HotWords - 1) : $urandom_range(Depth - 1);
        if (i < 2) index = (i == 0) ? 0 : Depth - 1;   // the first and the last word too
        if (r < 15) begin
          cycle(1'b0, 1'b0, 0, '0, '0);
          idles++;
        end else if (r < 55) begin
          cycle(1'b1, 1'b1, index, $urandom(), ($urandom_range(3) == 0) ? 4'hf : 4'($urandom()));
          stores++;
        end else begin
          cycle(1'b1, 1'b0, index, '0, '0);
          loads++;
        end
      end else begin
        // I-TCM: fetch the next word, jump, or stall for a few cycles.
        if (r < 15) begin
          repeat ($urandom_range(1, 5)) begin
            cycle(1'b0, 1'b0, 0, '0, '0);
            idles++;
          end
        end else begin
          index = (r < 25) ? $urandom_range(Depth - 1) : (index + 1) % Depth;
          cycle(1'b1, 1'b0, index, '0, '0);
          loads++;
        end
      end
    end
    repeat (2) cycle(1'b0, 1'b0, 0, '0, '0);   // the last response, then the held word

    for (int i = 0; i < Depth; i++) begin
      check(u_tcm.bd_read(i) === model[i],
            $sformatf("bd_read of word %0d returned %h, expected %h", i, u_tcm.bd_read(i), model[i]));
    end
    $display("%s: %0d loads, %0d stores, %0d idle cycles, %0d checks, %0d errors", Name, loads, stores,
             idles, checks, errors);
    done = 1'b1;
  end

endmodule

module tb_mem_tcm;
  import soc_pkg::*;

  logic       clk, rst_n;
  logic [1:0] done;
  int         errors [2];

  clk_rst_gen #(
    .ClkPeriod   (10ns),
    .RstClkCycles(5   )
  ) u_clk_rst (
    .clk_o (clk  ),
    .rst_no(rst_n)
  );

  tb_mem_tcm_port #(.HoldRdata(1'b0), .Stores(1'b1), .SizeBytes(DTCM_SIZE), .Base(DTCM_BASE)) u_dtcm (
    .clk, .rst_n, .done(done[0]), .errors(errors[0])
  );
  tb_mem_tcm_port #(.HoldRdata(1'b1), .Stores(1'b0), .SizeBytes(ITCM_SIZE), .Base(ITCM_BASE)) u_itcm (
    .clk, .rst_n, .done(done[1]), .errors(errors[1])
  );

  initial begin
    fork
      wait (&done);
      begin
        #20ms;
        $fatal(1, "timeout");
      end
    join_any
    if (errors[0] + errors[1] != 0) $fatal(1, "%0d errors", errors[0] + errors[1]);
    $display("PASS: both TCMs follow the protocol and match the reference");
    $finish;
  end

endmodule
