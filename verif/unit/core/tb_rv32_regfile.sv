// rv32_regfile: random reads and writes against a reference array, including x0 and same-cycle
// write-through.
module tb_rv32_regfile;

  logic        clk = 1'b0;
  logic [4:0]  rs1, rs2, rd;
  logic [31:0] rs1_data, rs2_data, wdata;
  logic        we;
  logic [31:0] ref_rf[32];
  int          errors = 0, checks = 0, write_through = 0;

  rv32_regfile dut (
    .clk_i     (clk),
    .rs1_addr_i(rs1),
    .rs1_data_o(rs1_data),
    .rs2_addr_i(rs2),
    .rs2_data_o(rs2_data),
    .rd_addr_i (rd),
    .rd_data_i (wdata),
    .rd_we_i   (we)
  );

  always #5 clk = ~clk;

  function automatic logic [31:0] expected(logic [4:0] addr);
    if (addr == 0)         return '0;
    if (we && rd == addr)  return wdata;  // write-through
    return ref_rf[addr];
  endfunction

  task automatic compare(string port, logic [4:0] addr, logic [31:0] got);
    checks++;
    if (got !== expected(addr)) begin
      errors++;
      if (errors <= 10) begin
        $display("FAIL: %s x%0d = %h, expected %h", port, addr, got, expected(addr));
      end
    end
  endtask

  initial begin
    // The registers have no reset: write every one first.
    foreach (ref_rf[i]) ref_rf[i] = '0;
    for (int i = 1; i < 32; i++) begin
      @(negedge clk);
      {rd, wdata, we, rs1, rs2} = {5'(i), 32'h0, 1'b1, 5'd0, 5'd0};
    end
    repeat (50000) begin
      @(negedge clk);
      rs1   = $urandom();
      rs2   = $urandom();
      rd    = $urandom();
      wdata = $urandom();
      we    = $urandom_range(0, 1);
      if ($urandom_range(0, 3) == 0) rs1 = rd;
      if ($urandom_range(0, 3) == 0) rs2 = rd;
      #1;
      if (we && rd != 0 && (rs1 == rd || rs2 == rd)) write_through++;
      compare("rs1", rs1, rs1_data);
      compare("rs2", rs2, rs2_data);
      @(posedge clk);
      if (we && rd != 0) ref_rf[rd] = wdata;
    end
    if (errors == 0) $display("PASS: %0d reads (%0d write-through)", checks, write_through);
    else             $display("FAIL: %0d of %0d reads", errors, checks);
    $finish;
  end

endmodule
