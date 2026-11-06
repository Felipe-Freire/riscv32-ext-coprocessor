// Hazard and forwarding unit (ID): compares the registers read in ID with the destinations of the
// two instructions ahead. The instruction three ahead is in WB, where the register file
// write-through covers it.
//
// The forwarding selects are registered in ID/EX and apply when this instruction reaches EX: by
// then the instruction now in EX has moved to EX/MEM, and the one now in MEM to MEM/WB. Only a
// load or CSR read directly ahead cannot forward, because its data exists only at the end of MEM.
// ID then waits one cycle and EX gets a bubble.
module rv32_hazard
  import rv32_pkg::*;
(
  // Instruction in ID
  input  logic       ifid_valid_i,
  input  logic [4:0] rs1_i,
  input  logic [4:0] rs2_i,
  input  logic       rs1_ren_i,
  input  logic       rs2_ren_i,

  // Instruction in EX
  input  logic       idex_valid_i,
  input  logic [4:0] idex_rd_i,
  input  logic       idex_rd_we_i,
  input  logic       idex_late_i,    // load or CSR read: result available only after MEM

  // Instruction in MEM
  input  logic       exmem_valid_i,
  input  logic [4:0] exmem_rd_i,
  input  logic       exmem_rd_we_i,

  input  logic       freeze_i,       // bus access waiting in MEM

  output logic       stall_o,        // hold PC and IF/ID
  output logic       bubble_o,       // send a bubble to EX
  output fwd_sel_e   fwd_a_o,        // operand A, from rs1
  output fwd_sel_e   fwd_b_o         // operand B and store data, both from rs2
);

  logic ex_writes, mem_writes;

  // rd_we is 0 for x0, so x0 never matches.
  assign ex_writes  = idex_valid_i & idex_rd_we_i;
  assign mem_writes = exmem_valid_i & exmem_rd_we_i;

  // The nearest instruction holds the newest value. An instruction that does not read rs ignores
  // the select, so the comparison does not need rs1_ren / rs2_ren.
  function automatic fwd_sel_e fwd_sel(logic [4:0] rs);
    if (ex_writes && idex_rd_i == rs) begin
      return FwdExMem;
    end else if (mem_writes && exmem_rd_i == rs) begin
      return FwdMemWb;
    end else begin
      return FwdNone;
    end
  endfunction

  always_comb begin : fwd_select
    fwd_a_o = fwd_sel(rs1_i);
    fwd_b_o = fwd_sel(rs2_i);
  end

  assign bubble_o = ifid_valid_i & ex_writes & idex_late_i
                    & ((rs1_ren_i & (idex_rd_i == rs1_i)) | (rs2_ren_i & (idex_rd_i == rs2_i)));

  assign stall_o = bubble_o | freeze_i;

endmodule
