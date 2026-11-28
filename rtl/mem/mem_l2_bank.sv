// One bank of the L2: an AXI4 slave of the data crossbar (bus_axi_xbar, DATA_SLV_L2_BANK*) on one
// prim_ram_1p of AXI_DATA_W bits, through axi_to_mem of vendor/axi.
//
// axi_to_mem splits each INCR burst into one memory access per beat. Reads and writes share the
// single port of the RAM: one beat per cycle in total, so a read and a write stream running together
// get half of it each. The RAM grants every access in its cycle (mem_gnt = 1) and answers one cycle
// later; axi_to_mem waits for that answer on writes too, so rvalid comes for every access. BufDepth
// is the depth of the response buffer of axi_to_mem: the latency of the RAM (1) is enough for one
// beat per cycle (rtl/mem/README.md).
//
// The word index is addr[$clog2(SizeBytes)-1:$clog2(AXI_DATA_W/8)], bits 14:4 for the 32 KiB banks:
// the bits above select the bank in the crossbar and are ignored here.
//
// Neither master of the crossbar issues atomics, so the bank does not implement them (an AW with
// atop set is flagged in simulation), and its bursts are INCR, the only type axi_to_mem handles.
//
// Simulation only: bd_write and bd_read reach a word of AXI_DATA_W bits by its index without a
// cycle (prim_ram_1p).
module mem_l2_bank
  import soc_pkg::*;
#(
  parameter int unsigned SizeBytes = L2_BANK_SIZE,  // a power of 2, at least two words
  parameter int unsigned BufDepth  = 1
) (
  input  logic         clk_i,
  input  logic         rst_ni,

  input  axi_slv_req_t axi_req_i,
  output axi_slv_rsp_t axi_rsp_o
);

  localparam int unsigned WordBytes = AXI_DATA_W / 8;
  localparam int unsigned Depth     = SizeBytes / WordBytes;
  localparam int unsigned IdxW      = $clog2(Depth);
  localparam int unsigned OffW      = $clog2(WordBytes);

  logic      mem_req, mem_we, mem_rvalid_q;
  axi_addr_t mem_addr;
  axi_data_t mem_wdata, mem_rdata;
  axi_strb_t mem_strb;

  axi_to_mem #(
    .axi_req_t   (axi_slv_req_t),
    .axi_resp_t  (axi_slv_rsp_t),
    .AddrWidth   (AXI_ADDR_W   ),
    .DataWidth   (AXI_DATA_W   ),
    .IdWidth     (AXI_ID_SLV_W ),
    .NumBanks    (1            ),
    .BufDepth    (BufDepth     ),
    .HideStrb    (1'b0         ),
    .OutFifoDepth(1            )
  ) u_axi_to_mem (
    .clk_i       (clk_i       ),
    .rst_ni      (rst_ni      ),
    .busy_o      (            ),
    .axi_req_i   (axi_req_i   ),
    .axi_resp_o  (axi_rsp_o   ),
    .mem_req_o   (mem_req     ),
    .mem_gnt_i   (1'b1        ),
    .mem_addr_o  (mem_addr    ),
    .mem_wdata_o (mem_wdata   ),
    .mem_strb_o  (mem_strb    ),
    .mem_atop_o  (            ),
    .mem_we_o    (mem_we      ),
    .mem_rvalid_i(mem_rvalid_q),
    .mem_rdata_i (mem_rdata   )
  );

  prim_ram_1p #(
    .Width(AXI_DATA_W),
    .Depth(Depth     )
  ) u_ram (
    .clk_i  (clk_i                  ),
    .req_i  (mem_req                ),
    .we_i   (mem_we                 ),
    .addr_i (mem_addr[OffW +: IdxW] ),
    .wdata_i(mem_wdata              ),
    .be_i   (mem_strb               ),
    .rdata_o(mem_rdata              )
  );

  // The answer to every access, read or write, one cycle after it.
  always_ff @(posedge clk_i or negedge rst_ni) begin : rvalid_reg
    if (!rst_ni) begin
      mem_rvalid_q <= 1'b0;
    end else begin
      mem_rvalid_q <= mem_req;
    end
  end

`ifndef SYNTHESIS
  function automatic void bd_write(input int unsigned index, input axi_data_t data);
    u_ram.bd_write(index, data);
  endfunction

  function automatic axi_data_t bd_read(input int unsigned index);
    return u_ram.bd_read(index);
  endfunction

  // Checked at elaboration.
  if (SizeBytes < 2 * WordBytes || (SizeBytes & (SizeBytes - 1)) != 0) begin : gen_bad_size
    $fatal(1, "mem_l2_bank: SizeBytes %0d is not a power of 2 of at least two words", SizeBytes);
  end

  no_atop : assert property (@(posedge clk_i) disable iff (!rst_ni)
                             axi_req_i.aw_valid |-> axi_req_i.aw.atop == '0)
    else $error("mem_l2_bank %m: atomic operation on AW, which the bank does not implement");
  incr_only : assert property (@(posedge clk_i) disable iff (!rst_ni)
                               (axi_req_i.aw_valid |-> axi_req_i.aw.burst == axi_pkg::BURST_INCR) and
                               (axi_req_i.ar_valid |-> axi_req_i.ar.burst == axi_pkg::BURST_INCR))
    else $error("mem_l2_bank %m: burst other than INCR");
`endif

endmodule
