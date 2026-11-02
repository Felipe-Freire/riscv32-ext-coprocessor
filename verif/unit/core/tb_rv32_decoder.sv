// rv32_decoder + rv32_imm_gen: decodes every vector of dec_vectors.hex ({err, instr} per line)
// and writes the outputs to dec_dump.txt. tb_rv32_decoder.py generates the vectors and checks the
// dump against its reference decoder.
module tb_rv32_decoder;
  import rv32_pkg::*;

  logic [31:0] instr, imm;
  logic        err;
  dec_ctrl_t   ctrl;

  rv32_decoder u_decoder (
    .instr_i    (instr),
    .instr_err_i(err),
    .ctrl_o     (ctrl)
  );

  rv32_imm_gen u_imm_gen (
    .instr_i  (instr[31:7]),
    .imm_sel_i(ctrl.imm_sel),
    .imm_o    (imm)
  );

  initial begin
    int          fin, fout, count;
    logic [35:0] vector;
    fin  = $fopen("dec_vectors.hex", "r");
    fout = $fopen("dec_dump.txt", "w");
    if (fin == 0) $fatal(1, "dec_vectors.hex not found: run tb_rv32_decoder.py gen first");
    count = 0;
    while ($fscanf(fin, "%h\n", vector) == 1) begin
      {err, instr} = vector[32:0];
      #1;
      $fdisplay(fout, "%08h %0d %s %0d %0d %s %0d %s %0d %0d %0d %0d %0d %0d %0d %0d %0d %08h",
                instr, ctrl.exc, ctrl.exc_cause.name(), ctrl.rs1_ren, ctrl.rs2_ren,
                ctrl.imm_sel.name(), ctrl.opb_imm, ctrl.alu_op.name(), ctrl.rd_alt_pc, ctrl.branch,
                ctrl.jal, ctrl.jalr, ctrl.mem_re, ctrl.mem_we, ctrl.csr, ctrl.mret, ctrl.rd_we, imm);
      count++;
    end
    $fclose(fout);
    $display("decoded %0d vectors (checked by tb_rv32_decoder.py check)", count);
    $finish;
  end

endmodule
