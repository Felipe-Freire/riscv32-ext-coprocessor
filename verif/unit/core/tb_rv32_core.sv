// rv32_core: one directed, self-checking program, assembled with GNU as (the listing is in PROG).
//
// The program covers ALU forwarding, load-use, loads and stores of every size, bus wait states
// (including a D-TCM response that arrives while the next request waits for its grant), branches
// and jumps, CSRs, exceptions and a timer interrupt. Each check compares a register with the
// expected value in t5 and jumps to fail on a mismatch; t6 counts the checks passed. At the end the
// program stores (t6 << 1) | pass to TOHOST.
//
// Data memory map: TCM answers at once, BUS grants after 2 cycles and answers 2 cycles later, MMIO
// holds TOHOST (+0), clears irq_timer (+4) and raises it a few cycles later (+8), and any other
// address answers with an error.
module tb_rv32_core;
  import rv32_pkg::*;

  localparam int NumChecks = 31;

  localparam logic [15:0] TcmRegion  = 16'h0000;   // address bits 31:16
  localparam logic [15:0] BusRegion  = 16'h0001;
  localparam logic [15:0] MmioRegion = 16'h0002;

  localparam logic [31:0] PROG [216] = '{
    32'h00000297,  // 000  auipc t0,0x0
    32'h33828293,  // 004  addi t0,t0,824
    32'h30529073,  // 008  csrw mtvec,t0
    32'h00000f93,  // 00c  li t6,0
    32'h00008437,  // 010  lui s0,0x8
    32'h000104b7,  // 014  lui s1,0x10
    // alu_fwd
    32'h00500513,  // 018  li a0,5
    32'hffd00593,  // 01c  li a1,-3
    32'h00b50633,  // 020  add a2,a0,a1
    32'h40b606b3,  // 024  sub a3,a2,a1
    32'h00c69733,  // 028  sll a4,a3,a2
    32'h01400f13,  // 02c  li t5,20
    32'h2fe71c63,  // 030  bne a4,t5,328
    32'h001f8f93,  // 034  addi t6,t6,1
    32'h40c5d7b3,  // 038  sra a5,a1,a2
    32'h00c5d833,  // 03c  srl a6,a1,a2
    32'hfff00f13,  // 040  li t5,-1
    32'h2fe79263,  // 044  bne a5,t5,328
    32'h001f8f93,  // 048  addi t6,t6,1
    32'h40000f37,  // 04c  lui t5,0x40000
    32'hffff0f13,  // 050  addi t5,t5,-1
    32'h2de81a63,  // 054  bne a6,t5,328
    32'h001f8f93,  // 058  addi t6,t6,1
    32'h00a5a8b3,  // 05c  slt a7,a1,a0
    32'h00a5b2b3,  // 060  sltu t0,a1,a0
    32'h00100f13,  // 064  li t5,1
    32'h2de89063,  // 068  bne a7,t5,328
    32'h001f8f93,  // 06c  addi t6,t6,1
    32'h00000f13,  // 070  li t5,0
    32'h2be29a63,  // 074  bne t0,t5,328
    32'h001f8f93,  // 078  addi t6,t6,1
    32'hfff54313,  // 07c  not t1,a0
    32'h0f036393,  // 080  ori t2,t1,240
    32'h7ff3fe13,  // 084  andi t3,t2,2047
    32'h7fa00f13,  // 088  li t5,2042
    32'h29ee1e63,  // 08c  bne t3,t5,328
    32'h001f8f93,  // 090  addi t6,t6,1
    32'habcdeeb7,  // 094  lui t4,0xabcde
    32'habcdef37,  // 098  lui t5,0xabcde
    32'h29ee9663,  // 09c  bne t4,t5,328
    32'h001f8f93,  // 0a0  addi t6,t6,1
    // load_store
    32'h8b2df2b7,  // 0a4  lui t0,0x8b2df
    32'h00d28293,  // 0a8  addi t0,t0,13
    32'h00542023,  // 0ac  sw t0,0(s0)
    32'h00140303,  // 0b0  lb t1,1(s0)
    32'hff000f13,  // 0b4  li t5,-16
    32'h27e31863,  // 0b8  bne t1,t5,328
    32'h001f8f93,  // 0bc  addi t6,t6,1
    32'h00144303,  // 0c0  lbu t1,1(s0)
    32'h0f000f13,  // 0c4  li t5,240
    32'h27e31063,  // 0c8  bne t1,t5,328
    32'h001f8f93,  // 0cc  addi t6,t6,1
    32'h00241303,  // 0d0  lh t1,2(s0)
    32'hffff9f37,  // 0d4  lui t5,0xffff9
    32'hb2df0f13,  // 0d8  addi t5,t5,-1235
    32'h25e31663,  // 0dc  bne t1,t5,328
    32'h001f8f93,  // 0e0  addi t6,t6,1
    32'h00245303,  // 0e4  lhu t1,2(s0)
    32'h00009f37,  // 0e8  lui t5,0x9
    32'hb2df0f13,  // 0ec  addi t5,t5,-1235
    32'h23e31c63,  // 0f0  bne t1,t5,328
    32'h001f8f93,  // 0f4  addi t6,t6,1
    32'h000013b7,  // 0f8  lui t2,0x1
    32'h23438393,  // 0fc  addi t2,t2,564
    32'h00741123,  // 100  sh t2,2(s0)
    32'h05500393,  // 104  li t2,85
    32'h007400a3,  // 108  sb t2,1(s0)
    32'h00042303,  // 10c  lw t1,0(s0)
    32'h00130313,  // 110  addi t1,t1,1
    32'h12345f37,  // 114  lui t5,0x12345
    32'h50ef0f13,  // 118  addi t5,t5,1294
    32'h21e31663,  // 11c  bne t1,t5,328
    32'h001f8f93,  // 120  addi t6,t6,1
    // bus_wait
    32'h0054a423,  // 124  sw t0,8(s1)
    32'h00042303,  // 128  lw t1,0(s0)
    32'h0084a383,  // 12c  lw t2,8(s1)
    32'h12345f37,  // 130  lui t5,0x12345
    32'h50df0f13,  // 134  addi t5,t5,1293
    32'h1fe31863,  // 138  bne t1,t5,328
    32'h001f8f93,  // 13c  addi t6,t6,1
    32'h8b2dff37,  // 140  lui t5,0x8b2df
    32'h00df0f13,  // 144  addi t5,t5,13
    32'h1fe39063,  // 148  bne t2,t5,328
    32'h001f8f93,  // 14c  addi t6,t6,1
    32'hb02022f3,  // 150  csrr t0,minstret
    32'h00000013,  // 154  nop
    32'h0084a303,  // 158  lw t1,8(s1)
    32'hb02023f3,  // 15c  csrr t2,minstret
    32'h405383b3,  // 160  sub t2,t2,t0
    32'h00300f13,  // 164  li t5,3
    32'h1de39063,  // 168  bne t2,t5,328
    32'h001f8f93,  // 16c  addi t6,t6,1
    // branch_jump
    32'h00000293,  // 170  li t0,0
    32'h00500313,  // 174  li t1,5
    // loop
    32'h006282b3,  // 178  add t0,t0,t1
    32'hfff30313,  // 17c  addi t1,t1,-1
    32'hfe031ce3,  // 180  bnez t1,178
    32'h00f00f13,  // 184  li t5,15
    32'h1be29063,  // 188  bne t0,t5,328
    32'h001f8f93,  // 18c  addi t6,t6,1
    32'hfff00313,  // 190  li t1,-1
    32'h0062e463,  // 194  bltu t0,t1,19c
    32'h1900006f,  // 198  j 328
    32'h0062d463,  // 19c  bge t0,t1,1a4
    32'h1880006f,  // 1a0  j 328
    32'h18628263,  // 1a4  beq t0,t1,328
    32'h008000ef,  // 1a8  jal 1b0
    32'h17c0006f,  // 1ac  j 328
    32'h00000397,  // 1b0  auipc t2,0x0
    32'h401383b3,  // 1b4  sub t2,t2,ra
    32'h00400f13,  // 1b8  li t5,4
    32'h17e39663,  // 1bc  bne t2,t5,328
    32'h001f8f93,  // 1c0  addi t6,t6,1
    32'h00000e17,  // 1c4  auipc t3,0x0
    32'h010e0e13,  // 1c8  addi t3,t3,16
    32'h000e00e7,  // 1cc  jalr t3
    32'h1580006f,  // 1d0  j 328
    32'h00000e17,  // 1d4  auipc t3,0x0
    32'h000e0e13,  // 1d8  mv t3,t3
    32'hffce0e13,  // 1dc  addi t3,t3,-4
    32'h41c083b3,  // 1e0  sub t2,ra,t3
    32'h00000f13,  // 1e4  li t5,0
    32'h15e39063,  // 1e8  bne t2,t5,328
    32'h001f8f93,  // 1ec  addi t6,t6,1
    // csr
    32'h000062b7,  // 1f0  lui t0,0x6
    32'ha5a28293,  // 1f4  addi t0,t0,-1446
    32'h34029073,  // 1f8  csrw mscratch,t0
    32'h3402e373,  // 1fc  csrrsi t1,mscratch,5
    32'h340d73f3,  // 200  csrrci t2,mscratch,26
    32'h34002e73,  // 204  csrr t3,mscratch
    32'h00006f37,  // 208  lui t5,0x6
    32'ha5af0f13,  // 20c  addi t5,t5,-1446
    32'h11e31c63,  // 210  bne t1,t5,328
    32'h001f8f93,  // 214  addi t6,t6,1
    32'h00006f37,  // 218  lui t5,0x6
    32'ha5ff0f13,  // 21c  addi t5,t5,-1441
    32'h11e39463,  // 220  bne t2,t5,328
    32'h001f8f93,  // 224  addi t6,t6,1
    32'h00006f37,  // 228  lui t5,0x6
    32'ha45f0f13,  // 22c  addi t5,t5,-1467
    32'h0fee1c63,  // 230  bne t3,t5,328
    32'h001f8f93,  // 234  addi t6,t6,1
    32'h301022f3,  // 238  csrr t0,misa
    32'h40000f37,  // 23c  lui t5,0x40000
    32'h100f0f13,  // 240  addi t5,t5,256
    32'h0fe29263,  // 244  bne t0,t5,328
    32'h001f8f93,  // 248  addi t6,t6,1
    32'hb02022f3,  // 24c  csrr t0,minstret
    32'hb0202373,  // 250  csrr t1,minstret
    32'h40530333,  // 254  sub t1,t1,t0
    32'h00100f13,  // 258  li t5,1
    32'h0de31663,  // 25c  bne t1,t5,328
    32'h001f8f93,  // 260  addi t6,t6,1
    32'hb0201073,  // 264  csrw minstret,zero
    32'hb02022f3,  // 268  csrr t0,minstret
    32'h00000f13,  // 26c  li t5,0
    32'h0be29c63,  // 270  bne t0,t5,328
    32'h001f8f93,  // 274  addi t6,t6,1
    // exceptions
    32'h00000073,  // 278  ecall
    32'h00b00f13,  // 27c  li t5,11
    32'h0bed9463,  // 280  bne s11,t5,328
    32'h001f8f93,  // 284  addi t6,t6,1
    32'h300022f3,  // 288  csrr t0,mstatus
    32'h00002f37,  // 28c  lui t5,0x2
    32'h880f0f13,  // 290  addi t5,t5,-1920
    32'h09e29a63,  // 294  bne t0,t5,328
    32'h001f8f93,  // 298  addi t6,t6,1
    32'h00242283,  // 29c  lw t0,2(s0)
    32'h00400f13,  // 2a0  li t5,4
    32'h09ed9263,  // 2a4  bne s11,t5,328
    32'h001f8f93,  // 2a8  addi t6,t6,1
    32'h00030337,  // 2ac  lui t1,0x30
    32'h00532023,  // 2b0  sw t0,0(t1)
    32'h00700f13,  // 2b4  li t5,7
    32'h07ed9863,  // 2b8  bne s11,t5,328
    32'h001f8f93,  // 2bc  addi t6,t6,1
    32'h00000000,  // 2c0  .word 0x00000000
    32'h00200f13,  // 2c4  li t5,2
    32'h07ed9063,  // 2c8  bne s11,t5,328
    32'h001f8f93,  // 2cc  addi t6,t6,1
    // interrupt
    32'h00000d13,  // 2d0  li s10,0
    32'h08000293,  // 2d4  li t0,128
    32'h3042a073,  // 2d8  csrs mie,t0
    32'h30046073,  // 2dc  csrsi mstatus,8
    32'h00020337,  // 2e0  lui t1,0x20
    32'h00632423,  // 2e4  sw t1,8(t1)
    32'h0c800393,  // 2e8  li t2,200
    32'hfff38393,  // 2ec  addi t2,t2,-1
    32'h02038c63,  // 2f0  beqz t2,328
    32'hfe0d0ce3,  // 2f4  beqz s10,2ec
    32'h00100f13,  // 2f8  li t5,1
    32'h03ed1663,  // 2fc  bne s10,t5,328
    32'h001f8f93,  // 300  addi t6,t6,1
    32'h80000f37,  // 304  lui t5,0x80000
    32'h007f0f13,  // 308  addi t5,t5,7
    32'h01ed9e63,  // 30c  bne s11,t5,328
    32'h001f8f93,  // 310  addi t6,t6,1
    // pass
    32'h001f9293,  // 314  slli t0,t6,0x1
    32'h0012e293,  // 318  ori t0,t0,1
    32'h00020337,  // 31c  lui t1,0x20
    32'h00532023,  // 320  sw t0,0(t1)
    32'h0000006f,  // 324  j 324
    // fail
    32'h001f9293,  // 328  slli t0,t6,0x1
    32'h00020337,  // 32c  lui t1,0x20
    32'h00532023,  // 330  sw t0,0(t1)
    32'h0000006f,  // 334  j 334
    // handler
    32'h34202df3,  // 338  csrr s11,mcause
    32'h000dca63,  // 33c  bltz s11,350
    32'h34102cf3,  // 340  csrr s9,mepc
    32'h004c8c93,  // 344  addi s9,s9,4
    32'h341c9073,  // 348  csrw mepc,s9
    32'h30200073,  // 34c  mret
    32'h00020cb7,  // 350  lui s9,0x20
    32'h000ca223,  // 354  sw zero,4(s9)
    32'h001d0d13,  // 358  addi s10,s10,1
    32'h30200073   // 35c  mret
  };

  logic        clk = 1'b0, rst_n = 1'b0;
  logic        instr_req, instr_err;
  logic [31:0] instr_addr, instr_rdata;
  logic        data_req, data_gnt, data_we, data_rvalid, data_err;
  logic [31:0] data_addr, data_wdata, data_rdata;
  logic [3:0]  data_be;
  logic        irq_timer;

  always #5 clk = ~clk;

  rv32_core dut (
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
    .irq_timer_i   (irq_timer),
    .irq_external_i(1'b0)
  );

  // ---- Instruction memory: data one cycle after the request, held while the request is low

  always_ff @(posedge clk) begin
    if (instr_req) begin
      instr_err   <= instr_addr[31:2] >= $size(PROG);
      instr_rdata <= instr_addr[31:2] < $size(PROG) ? PROG[instr_addr[31:2]] : '0;
    end
  end

  // ---- Data memory (TCM and BUS share the words) and MMIO

  logic [31:0] dmem [256];
  logic        is_bus, pending, tohost_valid;
  logic [31:0] tohost, rsp_data;
  int          gnt_wait, rsp_wait, irq_delay;

  assign is_bus      = data_addr[31:16] == BusRegion;
  assign data_gnt    = data_req & (~is_bus | gnt_wait == 2);
  assign data_rvalid = pending & rsp_wait == 0;
  assign data_rdata  = data_rvalid ? rsp_data : 32'hDEAD_BEEF;   // valid only with rvalid

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pending      <= 1'b0;
      gnt_wait     <= 0;
      irq_timer    <= 1'b0;
      irq_delay    <= 0;
      tohost_valid <= 1'b0;
    end else begin
      gnt_wait <= (data_req && !data_gnt) ? gnt_wait + 1 : 0;
      if (data_rvalid)  pending  <= 1'b0;
      else if (pending) rsp_wait <= rsp_wait - 1;
      if (irq_delay == 1) irq_timer <= 1'b1;
      if (irq_delay != 0) irq_delay <= irq_delay - 1;

      if (data_req && data_gnt) begin
        pending    <= 1'b1;
        rsp_wait   <= is_bus ? 2 : 0;
        data_err   <= !(data_addr[31:16] inside {TcmRegion, BusRegion, MmioRegion});
        rsp_data   <= dmem[data_addr[9:2]];
        if (data_we && data_addr[31:16] inside {TcmRegion, BusRegion}) begin
          for (int b = 0; b < 4; b++) begin
            if (data_be[b]) dmem[data_addr[9:2]][8*b +: 8] <= data_wdata[8*b +: 8];
          end
        end
        if (data_we && data_addr[31:16] == MmioRegion) begin
          unique case (data_addr[3:2])
            2'd0: begin
              tohost       <= data_wdata;
              tohost_valid <= 1'b1;
            end
            2'd1:    irq_timer <= 1'b0;
            default: irq_delay <= 5;
          endcase
        end
      end
    end
  end

  // ---- OBI: a request stays, unchanged, until it is granted

  int errors = 0;

  always @(posedge clk) begin
    if (rst_n && data_req && !data_gnt) begin
      logic [31:0] addr;
      addr = data_addr;
      @(negedge clk);
      if (!data_req || data_addr !== addr) begin
        errors++;
        $display("FAIL: data request dropped or changed before its grant at %0t", $time);
      end
    end
  end

  initial begin
    int cycles;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    for (cycles = 0; cycles < 5000 && !tohost_valid; cycles++) @(negedge clk);

    if (!tohost_valid) begin
      $display("FAIL: timeout after %0d cycles", cycles);
    end else if (tohost !== {NumChecks[30:0], 1'b1} || errors != 0) begin
      $display("FAIL: check %0d failed (t6 = %0d), %0d bus errors", tohost[31:1] + 1, tohost[31:1],
               errors);
    end else begin
      $display("PASS: %0d checks, %0d cycles", NumChecks, cycles);
    end
    $finish;
  end

endmodule
