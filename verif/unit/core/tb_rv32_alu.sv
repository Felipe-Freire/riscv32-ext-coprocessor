// rv32_alu: every operation on corner and random operands against a behavioral model, plus the
// comparison flags (AluSub, AluSlt, AluSltu) and the raw adder output.
module tb_rv32_alu;
  import rv32_pkg::*;

  alu_op_e     op;
  logic [31:0] a, b, result, adder;
  logic        eq, lt, ltu;
  int          errors = 0, checks = 0;

  rv32_alu dut (
    .op_i    (op),
    .a_i     (a),
    .b_i     (b),
    .result_o(result),
    .adder_o (adder),
    .eq_o    (eq),
    .lt_o    (lt),
    .ltu_o   (ltu)
  );

  function automatic logic [31:0] model(alu_op_e o, logic [31:0] x, logic [31:0] y);
    case (o)
      AluAdd:   return x + y;
      AluSub:   return x - y;
      AluSll:   return x << y[4:0];
      AluSlt:   return {31'b0, $signed(x) < $signed(y)};
      AluSltu:  return {31'b0, x < y};
      AluXor:   return x ^ y;
      AluSrl:   return x >> y[4:0];
      AluSra:   return $unsigned($signed(x) >>> y[4:0]);
      AluOr:    return x | y;
      AluAnd:   return x & y;
      AluPassB: return y;
      default:  return 'x;
    endcase
  endfunction

  task automatic fail(string msg);
    errors++;
    if (errors <= 10) $display("FAIL: %s", msg);
  endtask

  task automatic check(alu_op_e o, logic [31:0] x, logic [31:0] y);
    op = o;
    a  = x;
    b  = y;
    #1;
    checks++;
    if (result !== model(o, x, y)) begin
      fail($sformatf("%s a=%h b=%h result=%h expected=%h", o.name(), x, y, result, model(o, x, y)));
    end
    if (o inside {AluSub, AluSlt, AluSltu} &&
        (eq !== (x == y) || lt !== ($signed(x) < $signed(y)) || ltu !== (x < y))) begin
      fail($sformatf("flags %s a=%h b=%h eq=%b lt=%b ltu=%b", o.name(), x, y, eq, lt, ltu));
    end
    if (o inside {AluAdd, AluSub} && adder !== model(o, x, y)) begin
      fail($sformatf("adder_o %s a=%h b=%h", o.name(), x, y));
    end
  endtask

  initial begin
    automatic logic [31:0] corner[] = '{32'h0, 32'h1, 32'h2, 32'h1F, 32'h20, 32'h7FFF_FFFF,
                                        32'h8000_0000, 32'h8000_0001, 32'hFFFF_FFFE, 32'hFFFF_FFFF,
                                        32'hAAAA_5555};
    alu_op_e o;
    o = o.first();
    do begin
      foreach (corner[i]) foreach (corner[j]) check(o, corner[i], corner[j]);
      repeat (20000) check(o, $urandom(), $urandom());
      // operands that differ by -2..+2, for the comparison logic
      repeat (2000) begin
        automatic logic [31:0] x = $urandom();
        check(o, x, x + ($urandom_range(0, 4) - 2));
      end
      o = o.next();
    end while (o != o.first());
    if (errors == 0) $display("PASS: %0d checks", checks);
    else             $display("FAIL: %0d of %0d checks", errors, checks);
    $finish;
  end

endmodule
