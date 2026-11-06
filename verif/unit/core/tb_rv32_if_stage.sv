// rv32_if_stage: the testbench plays the instruction memory (one-cycle latency, output held
// while the request is low) and the rest of the pipeline (random stalls, and ID, EX and trap
// redirects, also during stalls). It checks that ID receives exactly the program-order stream of
// (pc, instruction, error), that IF/ID holds during a stall and that pc_o = ifid_pc + 4.
module tb_rv32_if_stage;

  localparam logic [31:0] BOOT = 32'h1000_0000;

  logic        clk = 1'b0, rst_n = 1'b0;
  logic        req, mem_err_q, stall, id_redirect, ex_redirect, trap, ifid_valid, ifid_err;
  logic [31:0] addr, mem_rdata_q, ifid_instr;
  logic [31:2] id_target, ex_target, trap_target, pc, ifid_pc;

  rv32_if_stage #(
    .BootAddr(BOOT)
  ) dut (
    .clk_i        (clk),
    .rst_ni       (rst_n),
    .instr_req_o  (req),
    .instr_addr_o (addr),
    .instr_rdata_i(mem_rdata_q),
    .instr_err_i  (mem_err_q),
    .stall_i      (stall),
    .id_redirect_i(id_redirect),
    .id_target_i  (id_target),
    .ex_redirect_i(ex_redirect),
    .ex_target_i  (ex_target),
    .trap_i       (trap),
    .trap_target_i(trap_target),
    .pc_o         (pc),
    .ifid_valid_o (ifid_valid),
    .ifid_pc_o    (ifid_pc),
    .ifid_instr_o (ifid_instr),
    .ifid_err_o   (ifid_err)
  );

  always #5 clk = ~clk;

  // Program image and program behavior, as functions of the address
  function automatic logic [31:0] mem(logic [31:2] a);    return {a * 30'h2545F49, 2'b11}; endfunction
  function automatic logic        bad(logic [31:2] a);    return a[9:2] == 8'hEE;          endfunction
  function automatic logic        is_jump(logic [31:2] a); return (a * 30'h9E37) % 7 == 0;  endfunction
  function automatic logic [31:2] jump_to(logic [31:2] a); return a + (a % 13) - 6;         endfunction

  always_ff @(posedge clk) begin : imem
    if (req) begin
      mem_rdata_q <= mem(addr[31:2]);
      mem_err_q   <= bad(addr[31:2]);
    end
  end

  // Rest of the pipeline: drive on the falling edge. A jump keeps requesting its redirect while
  // it is held in ID.
  int redirects_in_stall = 0;
  always @(negedge clk) begin
    if (rst_n) begin
      stall       = ($urandom_range(0, 9) < 3);
      ex_redirect = ($urandom_range(0, 99) < 4);
      trap        = ($urandom_range(0, 99) < 2);
      ex_target   = BOOT[31:2] + $urandom_range(0, 4095);
      trap_target = BOOT[31:2] + $urandom_range(0, 4095);
      id_redirect = ifid_valid && is_jump(ifid_pc);
      id_target   = jump_to(ifid_pc);
      if (stall && (ex_redirect || trap)) redirects_in_stall++;
    end
  end

  // Checker, sampled just before each rising edge
  logic [31:2] expected_pc;
  logic        held_valid, check_hold = 1'b0;
  logic [31:2] held_pc;
  logic [31:0] held_instr;
  int          cycles = 0, accepted = 0, errors = 0;

  task automatic fail(string msg);
    errors++;
    if (errors <= 10) $display("FAIL: %s", msg);
  endtask

  always @(posedge clk) begin
    if (rst_n) begin
      cycles++;
      if (ifid_valid && pc !== ifid_pc + 1) fail($sformatf("pc_o %h, ifid_pc %h", pc, ifid_pc));
      if (check_hold && (ifid_valid !== held_valid ||
                         (ifid_valid && (ifid_pc !== held_pc || ifid_instr !== held_instr)))) begin
        fail("IF/ID changed during a stall");
      end
      check_hold = stall && !ex_redirect && !trap;
      {held_valid, held_pc, held_instr} = {ifid_valid, ifid_pc, ifid_instr};

      if (trap) begin
        expected_pc = trap_target;
      end else if (ex_redirect) begin
        expected_pc = ex_target;
      end else if (ifid_valid && !stall) begin  // ID takes the instruction
        accepted++;
        if (ifid_pc !== expected_pc || ifid_instr !== mem(ifid_pc) || ifid_err !== bad(ifid_pc)) begin
          fail($sformatf("ID got pc %h instr %h err %b, expected pc %h",
                         ifid_pc, ifid_instr, ifid_err, expected_pc));
        end
        expected_pc = id_redirect ? jump_to(ifid_pc) : ifid_pc + 1;
      end
    end
  end

  initial begin
    {stall, id_redirect, ex_redirect, trap} = '0;
    expected_pc = BOOT[31:2];
    repeat (3) @(negedge clk);
    if (pc !== BOOT[31:2] || ifid_valid !== 1'b0) fail("reset state");
    rst_n = 1'b1;
    repeat (200000) @(posedge clk);
    if (errors == 0) begin
      $display("PASS: %0d cycles, %0d instructions to ID, %0d redirects during a stall",
               cycles, accepted, redirects_in_stall);
    end else begin
      $display("FAIL: %0d errors in %0d cycles", errors, cycles);
    end
    $finish;
  end

endmodule
