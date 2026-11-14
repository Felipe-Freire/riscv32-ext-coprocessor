// Registers (verification plan COP-01, COP-02). Every response and read value is checked by the
// scoreboard against the golden model; this sequence only produces the accesses:
//   - reset values, through the register model
//   - DIM_* with random data, partial WSTRB and unaligned addresses
//   - CTRL reads 0, offsets outside the map answer SLVERR
//   - while a job runs: START, DIM_* writes and a DONE clear are all ignored
//   - DONE set at the end of a job, cleared by W1C, and cleared again by the next START

class coproc_regs_vseq extends coproc_base_vseq;

  `uvm_object_utils(coproc_regs_vseq)

  function new(string name = "coproc_regs_vseq");
    super.new(name);
  endfunction

  task body();
    bit [31:0]           d;
    bit [1:0]            resp;
    int unsigned         jobs;
    coproc_job           j;
    uvm_reg_hw_reset_seq reset_seq;
    bit [31:0]           outside[] = '{'h14, 'h18, 'h1C, 'h20, 'h40, 'h100, 'h800, 'hFFC};

    reset_seq       = uvm_reg_hw_reset_seq::type_id::create("reset_seq");
    reset_seq.model = p_sequencer.regmodel;
    reset_seq.start(null, this);

    repeat (40) begin
      bit [31:0] off = 'h08 + 4 * $urandom_range(2);
      raw_write(off | $urandom_range(3), $urandom(), 4'($urandom_range(15)), resp);
      raw_read(off | $urandom_range(3), d, resp);
    end

    raw_read('h00, d, resp);
    raw_read('h04, d, resp);
    foreach (outside[i]) begin
      raw_write(outside[i], $urandom(), 4'hF, resp);
      raw_read(outside[i], d, resp);
    end

    // A job with no data yet, so it stays busy for as long as the accesses below take.
    j = coproc_job::type_id::create("j");
    if (!j.randomize() with {tiles_m == 1; tiles_n == 2; k == 32; early_streams == 0;
                             data == DataRandom;}) begin
      `uvm_fatal("VSEQ", "Randomization failed")
    end
    j.make_matrices();
    jobs = p_sequencer.scb.jobs + 1;
    program_job(j);
    start_job();
    raw_write('h00, 1, 4'hF, resp);     // START while busy
    raw_write('h08, 'h40, 4'hF, resp);  // DIM_* while busy
    raw_write('h0C, 'h40, 4'hF, resp);
    raw_write('h10, 'h7, 4'hF, resp);
    raw_write('h04, 'h2, 4'hF, resp);   // DONE clear while busy
    raw_read('h04, d, resp);
    for (int unsigned off = 'h08; off <= 'h10; off += 4) raw_read(off, d, resp);
    stream_job(j);
    wait_job(jobs, j.max_cycles());

    raw_read('h04, d, resp);            // DONE = 1
    raw_write('h04, 'h2, 4'h1, resp);   // W1C
    raw_read('h04, d, resp);            // DONE = 0

    // Leave DONE set, then check that the next START clears it.
    if (!j.randomize() with {tiles_m == 1; tiles_n == 1; early_streams == 0; k inside {[1:16]};})
    begin
      `uvm_fatal("VSEQ", "Randomization failed")
    end
    run_job(j);
    if (!j.randomize() with {tiles_m == 1; tiles_n == 1; early_streams == 0; k == 40;}) begin
      `uvm_fatal("VSEQ", "Randomization failed")
    end
    j.make_matrices();
    jobs = p_sequencer.scb.jobs + 1;
    program_job(j);
    start_job();
    raw_read('h04, d, resp);            // BUSY = 1, DONE = 0
    stream_job(j);
    wait_job(jobs, j.max_cycles());
  endtask

endclass
