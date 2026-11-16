// rv32_core running one program image, writing a retirement trace for comparison against Spike
// (scripts/utils/cmp_trace.py). Driven by scripts/sim/verilator/verilator.mk, target `cosim`.
//
// One 4 MiB RAM at 0x8000_0000 serves both the instruction and the data port, with the same
// contents and the same base address as Spike's memory, so the only difference between the two
// runs is the hardware. The run ends when the program writes the HTIF tohost word (sw/common/crt0.S).
//
// Plusargs:
//   +HEX=<path>       memory image, one 32-bit word per line ($readmemh), word 0 at 0x8000_0000
//   +TOHOST=<hex>     address of the tohost word, from `nm` on the ELF
//   +TRACE=<path>     retirement trace to write (default: no trace)
//   +TIMEOUT=<n>      cycles before giving up (default 100000)
//   +GNT_WAIT=<n>     cycles a data request waits for its grant (default 0: granted at once)
//   +RSP_WAIT=<n>     cycles between the grant and the response (default 0: the next cycle)
//   +WAIT_SEED=<n>    nonzero: pseudo-random waits up to those two maxima, from this seed
//
// Wait states stress the freeze path of the core (EX waiting for a grant, MEM waiting for a
// response) and change nothing the reference can see: Spike has no notion of cycles, so the
// retirement trace must come out identical whatever the memory does.
//
// Trace format, one line per retired instruction: `<pc> <instr> <rd> <rd_value>`, all hex, with
// rd = 0 when the instruction writes no register. MEM is the commit point: the instruction in
// MEM/WB retires on the clock edge where the stage advances, so its PC is registered here exactly
// as rv32_mem_stage registers the rest of the MEM/WB payload.
module tb_rv32_core_cosim;
  import rv32_pkg::*;

  localparam logic [XLEN-1:0] RamBase  = 32'h8000_0000;
  // 4 MiB. The programs in sw/tests need a few KiB, but an architectural test carries a 128 KiB
  // stack and a signature area, and the image is sparse anyway.
  localparam int              RamWords = 1024 * 1024;
  localparam logic [XLEN-1:0] RamEnd   = RamBase + 4 * RamWords;

  logic        clk = 1'b0, rst_n = 1'b0;
  logic        instr_req, instr_err;
  logic [31:0] instr_addr, instr_rdata;
  logic        data_req, data_gnt, data_we, data_rvalid, data_err;
  logic [31:0] data_addr, data_wdata, data_rdata;
  logic [3:0]  data_be;

  always #5 clk = ~clk;

  rv32_core #(
    .BootAddr(RamBase)
  ) dut (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .instr_req_o   (instr_req),
    .instr_addr_o  (instr_addr),
    .instr_rdata_i (instr_rdata),
    .instr_err_i   (instr_err),
    .data_req_o    (data_req),
    .data_gnt_i    (data_gnt),
    .data_addr_o   (data_addr),
    .data_we_o     (data_we),
    .data_be_o     (data_be),
    .data_wdata_o  (data_wdata),
    .data_rvalid_i (data_rvalid),
    .data_rdata_i  (data_rdata),
    .data_err_i    (data_err),
    .irq_timer_i   (1'b0),
    .irq_external_i(1'b0)
  );

  // ---- Memory, shared by both ports

  logic [31:0] ram [RamWords];

  function automatic logic in_ram(logic [XLEN-1:0] addr);
    return (addr >= RamBase) && (addr < RamEnd);
  endfunction

  function automatic int unsigned word_of(logic [XLEN-1:0] addr);
    return (addr - RamBase) >> 2;
  endfunction

  // Word indices as plain signals: a function call in the index of a non-blocking assignment
  // upsets Verilator.
  logic [31:0] instr_word, data_word;

  assign instr_word = (instr_addr - RamBase) >> 2;
  assign data_word  = (data_addr  - RamBase) >> 2;

  // Instruction port: data one cycle after the request, held while the request is low.
  always_ff @(posedge clk) begin : imem
    if (instr_req) begin
      instr_err   <= !in_ram(instr_addr);
      instr_rdata <= in_ram(instr_addr) ? ram[instr_word[$clog2(RamWords)-1:0]] : '0;
    end
  end

  // Data port (OBI), with the grant and the response each delayed by 0..n cycles. One access is
  // outstanding at a time, and a new one may be granted in the cycle the previous response lands.
  logic        pending_q, rsp_now, grant_ok, rsp_err_q;
  logic [31:0] rsp_data_q, lfsr_q;
  int unsigned gnt_cnt_q, rsp_cnt_q;
  int          gnt_wait_max, rsp_wait_max, wait_seed;
  logic        tohost_valid;
  logic [31:0] tohost, tohost_addr;

  // Fixed waits count the cycles; random waits ask the LFSR, which advances every cycle.
  assign grant_ok    = (wait_seed == 0) ? (gnt_cnt_q >= unsigned'(gnt_wait_max))
                                        : ((lfsr_q % unsigned'(gnt_wait_max + 1)) == 0);
  assign rsp_now     = pending_q & (rsp_cnt_q == 0);
  assign data_gnt    = data_req & grant_ok & (~pending_q | rsp_now);
  assign data_rvalid = rsp_now;
  assign data_err    = rsp_err_q;
  assign data_rdata  = rsp_now ? rsp_data_q : 32'hDEAD_BEEF;       // valid only with rvalid

  function automatic int unsigned draw(int max_wait);
    if (max_wait <= 0) return 0;
    if (wait_seed == 0) return unsigned'(max_wait);
    return (lfsr_q >> 8) % unsigned'(max_wait + 1);
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin : dmem
    if (!rst_n) begin
      pending_q    <= 1'b0;
      rsp_err_q    <= 1'b0;
      gnt_cnt_q    <= 0;
      rsp_cnt_q    <= 0;
      tohost_valid <= 1'b0;
    end else begin
      lfsr_q    <= {lfsr_q[30:0], lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
      gnt_cnt_q <= (data_req && !data_gnt) ? gnt_cnt_q + 1 : 0;

      if (rsp_now)        pending_q <= 1'b0;
      else if (pending_q) rsp_cnt_q <= rsp_cnt_q - 1;

      if (data_req && data_gnt) begin
        pending_q <= 1'b1;
        rsp_cnt_q <= draw(rsp_wait_max);
        rsp_err_q <= ~in_ram(data_addr);
        if (in_ram(data_addr)) begin
          rsp_data_q <= ram[data_word[$clog2(RamWords)-1:0]];
          if (data_we) begin
            for (int b = 0; b < 4; b++) begin
              if (data_be[b]) ram[data_word[$clog2(RamWords)-1:0]][8*b +: 8] <= data_wdata[8*b +: 8];
            end
            // HTIF: the program ends the run by writing (exit code << 1) | 1 here.
            if (data_addr == tohost_addr && data_wdata != 32'd0) begin
              tohost       <= data_wdata;
              tohost_valid <= 1'b1;
            end
          end
        end
      end
    end
  end

  // OBI: a request stays, unchanged, until it is granted.
  int obi_errors = 0;

  always @(posedge clk) begin : obi_check
    if (rst_n && data_req && !data_gnt) begin
      logic [31:0] addr;
      logic        we;
      addr = data_addr;
      we   = data_we;
      @(negedge clk);
      if (!data_req || data_addr !== addr || data_we !== we) begin
        obi_errors++;
        $display("FAIL: data request dropped or changed before its grant at %0t", $time);
      end
    end
  end

  // ---- Retirement trace

  int              trace_fd = 0;
  int              retired  = 0;
  logic [XLEN-1:2] wb_pc_q;

  // Same enable as the MEM/WB register in rv32_mem_stage, so wb_pc_q is the PC of the instruction
  // whose payload is on memwb_*.
  always_ff @(posedge clk) begin : wb_pc_reg
    if (!dut.freeze) wb_pc_q <= dut.exmem.pc;
  end

  always_ff @(posedge clk) begin : trace
    logic [XLEN-1:0] pc;
    if (rst_n && dut.memwb_valid && !dut.freeze) begin
      pc = {wb_pc_q, 2'b00};
      retired++;
      if (trace_fd != 0) begin
        $fdisplay(trace_fd, "%08h %08h %0d %08h", pc, in_ram(pc) ? ram[word_of(pc)] : 32'h0,
                  dut.memwb_rd_we ? dut.memwb_rd : 5'd0,
                  dut.memwb_rd_we ? dut.memwb_data : 32'h0);
      end
    end
  end

  // ---- Run

  initial begin
    string image, trace_path;
    int    timeout, cycles;

    if (!$value$plusargs("HEX=%s", image)) begin
      $display("FAIL: no +HEX=<image> given");
      $finish;
    end
    if (!$value$plusargs("TOHOST=%h", tohost_addr)) begin
      $display("FAIL: no +TOHOST=<address> given");
      $finish;
    end
    if (!$value$plusargs("TIMEOUT=%d", timeout)) timeout = 100000;
    if (!$value$plusargs("GNT_WAIT=%d", gnt_wait_max))  gnt_wait_max = 0;
    if (!$value$plusargs("RSP_WAIT=%d", rsp_wait_max))  rsp_wait_max = 0;
    if (!$value$plusargs("WAIT_SEED=%d", wait_seed))    wait_seed    = 0;
    lfsr_q = (wait_seed == 0) ? 32'h1 : (wait_seed | 32'h1);   // never all zeroes

    ram = '{default: '0};   // past the program: illegal instruction, not X
    $readmemh(image, ram);

    if ($value$plusargs("TRACE=%s", trace_path)) begin
      trace_fd = $fopen(trace_path, "w");
      if (trace_fd == 0) begin
        $display("FAIL: cannot write %s", trace_path);
        $finish;
      end
    end

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    for (cycles = 0; cycles < timeout && !tohost_valid; cycles++) @(negedge clk);

    if (trace_fd != 0) $fclose(trace_fd);

    if (!tohost_valid) begin
      $display("FAIL: timeout after %0d cycles, %0d instructions retired", cycles, retired);
    end else if (tohost != 32'd1) begin
      $display("FAIL: program exited with code %0d (tohost 0x%08h)", tohost >> 1, tohost);
    end else if (obi_errors != 0) begin
      $display("FAIL: %0d OBI protocol errors", obi_errors);
    end else begin
      $display("PASS: program exited with code 0, %0d instructions retired in %0d cycles",
               retired, cycles);
    end
    $finish;
  end

endmodule
