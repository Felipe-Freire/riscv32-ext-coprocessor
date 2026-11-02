// RV32I ALU: add/sub, set-less-than, logic, shifts and pass-B.
//
// One adder serves ADD/SUB, SLT/SLTU, the branch comparison and the load/store and JALR
// address. lt_o / ltu_o are valid when op_i is AluSub, AluSlt or AluSltu; eq_o is always valid.
module rv32_alu
  import rv32_pkg::*;
(
  input  alu_op_e         op_i,
  input  logic [XLEN-1:0] a_i,
  input  logic [XLEN-1:0] b_i,
  output logic [XLEN-1:0] result_o,
  output logic [XLEN-1:0] adder_o,  // raw adder output: load/store address, JALR target
  output logic            eq_o,     // a == b
  output logic            lt_o,     // a <  b, signed
  output logic            ltu_o     // a <  b, unsigned
);

  logic          sub;
  logic [XLEN:0] sum;

  // a - b = a + ~b + 1. Bit XLEN is the carry out: 1 means no borrow, i.e. a >= b unsigned.
  assign sub = (op_i inside {AluSub, AluSlt, AluSltu});
  assign sum = {1'b0, a_i} + {1'b0, b_i ^ {XLEN{sub}}} + (XLEN+1)'(sub);

  assign adder_o = sum[XLEN-1:0];
  assign eq_o    = (a_i == b_i);
  assign ltu_o   = ~sum[XLEN];
  // Same signs: the difference cannot overflow, so its sign decides. Different signs: a < b
  // exactly when a is the negative one.
  assign lt_o    = (a_i[XLEN-1] == b_i[XLEN-1]) ? sum[XLEN-1] : a_i[XLEN-1];

  // All shifts use one right shifter: SLL reverses the operand before the shift and the result
  // after it. The extra top bit is the fill, a[XLEN-1] for SRA and 0 otherwise.
  logic            sll;
  logic [XLEN-1:0] shift_in, shift_rev;
  logic [XLEN:0]   shift_right;

  assign sll         = (op_i == AluSll);
  assign shift_right = $signed({(op_i == AluSra) & a_i[XLEN-1], shift_in}) >>> b_i[4:0];

  always_comb begin : shift_loop
    for (int unsigned i = 0; i < XLEN; i++) begin
      shift_in[i]  = sll ? a_i[XLEN-1-i] : a_i[i];
      shift_rev[i] = shift_right[XLEN-1-i];
    end
  end

  always_comb begin : alu_result
    unique case (op_i)
      AluAdd, AluSub: result_o = sum[XLEN-1:0];
      AluSlt:         result_o = XLEN'(lt_o);
      AluSltu:        result_o = XLEN'(ltu_o);
      AluXor:         result_o = a_i ^ b_i;
      AluOr:          result_o = a_i | b_i;
      AluAnd:         result_o = a_i & b_i;
      AluSll:         result_o = shift_rev;
      AluSrl, AluSra: result_o = shift_right[XLEN-1:0];
      AluPassB:       result_o = b_i;
      default:        result_o = '0;
    endcase
  end

endmodule
