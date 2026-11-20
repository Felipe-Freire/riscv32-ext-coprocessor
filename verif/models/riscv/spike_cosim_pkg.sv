// SPDX-License-Identifier: Apache-2.0
//
// spike_cosim_pkg.sv - DPI imports + RVFI/RVVI helpers for cosim::SpikeCosim.
//
// Usage (e.g. from a UVM scoreboard):
//
//   import spike_cosim_pkg::*;
//   chandle ref_h = spike_cosim_create("rv32im_zicsr_zifencei", "MU",
//                                      64'h8000_0000, "trace=spike.log");
//   void'(spike_cosim_add_region(ref_h, "ram", 64'h8000_0000, 64'h10_0000, 1'b0));
//   void'(spike_cosim_add_region(ref_h, "periph", 64'h1000_0000, 64'h1_0000, 1'b1));
//   void'(spike_cosim_load_binary(ref_h, "prog.bin", 64'h8000_0000));
//   ...
//   spike_cosim_set_irq_lines(ref_h, {52'b0, meip, 3'b0, mtip, 3'b0, msip, 3'b0});
//   if (!step_rvfi(ref_h, ...)) collect_errors(ref_h, msgs);
//
// Inside a SoC reference model, share one RAM between harts / DMA monitor:
//
//   chandle ram = spike_cosim_ram_create(64'h10_0000);
//   void'(spike_cosim_ram_load_binary(ram, "prog.bin", 0));
//   void'(spike_cosim_add_shared_region(ref_h, "ram", 64'h8000_0000, 64'h10_0000, ram, 1'b0));
//   // DMA/accelerator write seen at the memory slave (AXI W beat):
//   void'(spike_cosim_ram_write(ram, awaddr - 64'h8000_0000, wdata, wstrb));
//
// Interrupt lines must be updated (set_irq_lines) before the commit of the
// first handler instruction that the DUT reports with rvfi_intr / intr.

package spike_cosim_pkg;

  typedef enum int {
    REG_X   = 0,
    REG_F   = 1,
    REG_V   = 2,
    REG_CSR = 3
  } reg_file_e;

  localparam byte unsigned MODE_UNKNOWN = 8'hFF;

  // ---------------------------------------------------------------------------
  // DPI imports (see spike_cosim_dpi.cc)
  // ---------------------------------------------------------------------------
  // options: "key=value ..." - trace, hart_id, pmp_regions, pmp_granularity,
  // wfi_as_nop, mtvec, irq_mask, check_{order,insn,next_pc,mem,mode}
  import "DPI-C" function chandle spike_cosim_create(
      string isa, string priv, longint unsigned reset_pc, string options);
  import "DPI-C" function void spike_cosim_destroy(chandle h);

  import "DPI-C" function int spike_cosim_add_region(
      chandle h, string name, longint unsigned base, longint unsigned size, bit dut_driven);
  import "DPI-C" function int spike_cosim_write_mem_byte(
      chandle h, longint unsigned addr, byte unsigned data);
  import "DPI-C" function longint spike_cosim_load_binary(
      chandle h, string path, longint unsigned base);
  import "DPI-C" function int spike_cosim_add_shared_region(
      chandle h, string name, longint unsigned base, longint unsigned size,
      chandle ram, bit dut_driven);
  import "DPI-C" function void spike_cosim_flush_icache(chandle h);

  // Shared reference RAM (SoC level). Offsets are RAM-relative.
  import "DPI-C" function chandle spike_cosim_ram_create(longint unsigned size);
  import "DPI-C" function void spike_cosim_ram_destroy(chandle ram);
  import "DPI-C" function int spike_cosim_ram_write(
      chandle ram, longint unsigned offset, longint unsigned data, byte unsigned strobe);
  import "DPI-C" function int spike_cosim_ram_read(
      chandle ram, longint unsigned offset, int len, output longint unsigned data);
  import "DPI-C" function longint spike_cosim_ram_load_binary(
      chandle ram, string path, longint unsigned offset);

  import "DPI-C" function void spike_cosim_set_irq_lines(chandle h, longint unsigned mip);
  import "DPI-C" function longint unsigned spike_cosim_read_csr(chandle h, int csr);
  import "DPI-C" function void spike_cosim_write_csr(chandle h, int csr, longint unsigned value);
  import "DPI-C" function void spike_cosim_set_csr_constant(
      chandle h, int csr, longint unsigned value);
  import "DPI-C" function void spike_cosim_add_volatile_csr(chandle h, int csr);
  import "DPI-C" function void spike_cosim_set_csr_warl_mask(
      chandle h, int csr, longint unsigned and_mask, longint unsigned or_mask);

  import "DPI-C" function void spike_cosim_retire_begin(
      chandle h, longint unsigned order, longint unsigned pc_rdata, longint unsigned pc_wdata,
      int unsigned insn, bit trap, bit intr, byte unsigned mode);
  import "DPI-C" function void spike_cosim_retire_add_reg(
      chandle h, int file, int index, longint unsigned value);
  import "DPI-C" function void spike_cosim_retire_set_mem(
      chandle h, longint unsigned addr, int unsigned rmask, int unsigned wmask,
      longint unsigned rdata, longint unsigned wdata);
  import "DPI-C" function void spike_cosim_retire_set_faults(
      chandle h, bit fetch_fault, bit mem_fault);
  import "DPI-C" function int spike_cosim_retire_commit(chandle h);

  import "DPI-C" function int spike_cosim_num_errors(chandle h);
  import "DPI-C" function string spike_cosim_get_error(chandle h, int index);
  import "DPI-C" function void spike_cosim_clear_errors(chandle h);
  import "DPI-C" function longint unsigned spike_cosim_retired_count(chandle h);

  // ---------------------------------------------------------------------------
  // RVFI (riscv-formal), NRET = 1, XLEN = 32
  // ---------------------------------------------------------------------------
  // Memory fields are always forwarded (zero masks = "no access"), so a load or
  // store that only Spike performed is caught.
  function automatic bit step_rvfi(
      chandle h,
      longint unsigned order,
      bit [31:0] insn,
      bit        trap,
      bit        intr,
      bit [1:0]  mode,
      bit [31:0] pc_rdata,
      bit [31:0] pc_wdata,
      bit [4:0]  rd_addr,
      bit [31:0] rd_wdata,
      bit [31:0] mem_addr,
      bit [3:0]  mem_rmask,
      bit [3:0]  mem_wmask,
      bit [31:0] mem_rdata,
      bit [31:0] mem_wdata,
      bit        fetch_fault = 1'b0,
      bit        mem_fault   = 1'b0);
    spike_cosim_retire_begin(h, order, pc_rdata, pc_wdata, insn, trap, intr, byte'(mode));
    if (rd_addr != 0) spike_cosim_retire_add_reg(h, REG_X, int'(rd_addr), rd_wdata);
    spike_cosim_retire_set_mem(h, mem_addr, mem_rmask, mem_wmask, mem_rdata, mem_wdata);
    spike_cosim_retire_set_faults(h, fetch_fault, mem_fault);
    return spike_cosim_retire_commit(h) != 0;
  endfunction

  // Optional RVFI CSR extension: call between retire_begin and retire_commit
  // for each rvfi_csr_<name>_wmask != 0 you want checked.
  function automatic void add_csr_write(chandle h, int csr, longint unsigned wdata);
    spike_cosim_retire_add_reg(h, REG_CSR, csr, wdata);
  endfunction

  // ---------------------------------------------------------------------------
  // RVVI-TRACE, single retire slot, XLEN = 32
  // ---------------------------------------------------------------------------
  // RVVI carries no memory fields: data accesses are not compared and
  // DUT-driven regions cannot supply load data (use RVFI or add set_mem).
  function automatic bit step_rvvi(
      chandle h,
      longint unsigned order,
      bit [31:0] insn,
      bit        trap,
      bit        intr,
      bit [1:0]  mode,
      bit [31:0] pc_rdata,
      bit [31:0] pc_wdata,
      bit [31:0] x_wb,
      bit [31:0] x_wdata[32],
      bit        fetch_fault = 1'b0,
      bit        mem_fault   = 1'b0);
    spike_cosim_retire_begin(h, order, pc_rdata, pc_wdata, insn, trap, intr, byte'(mode));
    for (int i = 1; i < 32; i++) begin
      if (x_wb[i]) spike_cosim_retire_add_reg(h, REG_X, i, x_wdata[i]);
    end
    spike_cosim_retire_set_faults(h, fetch_fault, mem_fault);
    return spike_cosim_retire_commit(h) != 0;
  endfunction

  // ---------------------------------------------------------------------------
  // Error collection
  // ---------------------------------------------------------------------------
  function automatic void collect_errors(chandle h, ref string msgs[$]);
    for (int i = 0; i < spike_cosim_num_errors(h); i++) begin
      msgs.push_back(spike_cosim_get_error(h, i));
    end
    spike_cosim_clear_errors(h);
  endfunction

endpackage : spike_cosim_pkg
