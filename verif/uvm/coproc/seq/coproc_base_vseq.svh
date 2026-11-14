// Building blocks of the coprocessor sequences: register accesses (by name through the register
// model, or raw for addresses it does not cover), streaming a job, waiting for its end.
//
// A job is over for software when STATUS shows BUSY = 0. Before that, wait_job() also waits for
// the scoreboard to have checked every C word, so the next job never starts while the C FIFO
// still holds beats of the previous one.

class coproc_base_vseq extends uvm_sequence;

  `uvm_object_utils(coproc_base_vseq)
  `uvm_declare_p_sequencer(coproc_vseqr)

  function new(string name = "coproc_base_vseq");
    super.new(name);
  endfunction

  // An access cut short by a reset is not an error: the test asserted the reset.
  function bit in_reset();
    return p_sequencer.cfg.tb_vif.rst_n !== 1'b1;
  endfunction

  task reg_write(uvm_reg r, uvm_reg_data_t value);
    uvm_status_e st;
    r.write(st, value, .parent(this));
    if (st != UVM_IS_OK && !in_reset()) begin
      `uvm_error("VSEQ", $sformatf("Write to %s failed", r.get_name()))
    end
  endtask

  task reg_read(uvm_reg r, output uvm_reg_data_t value);
    uvm_status_e st;
    r.read(st, value, .parent(this));
    if (st != UVM_IS_OK && !in_reset()) begin
      `uvm_error("VSEQ", $sformatf("Read of %s failed", r.get_name()))
    end
  endtask

  task raw_write(bit [31:0] addr, bit [31:0] data, bit [3:0] strb, output bit [1:0] resp);
    axil_write_seq s = axil_write_seq::type_id::create("s");
    if (!s.randomize() with {addr == local::addr; data == local::data; strb == local::strb;}) begin
      `uvm_fatal("VSEQ", "Randomization failed")
    end
    s.start(p_sequencer.axil_sqr, this);
    resp = s.resp;
  endtask

  task raw_read(bit [31:0] addr, output bit [31:0] data, output bit [1:0] resp);
    axil_read_seq s = axil_read_seq::type_id::create("s");
    if (!s.randomize() with {addr == local::addr;}) begin
      `uvm_fatal("VSEQ", "Randomization failed")
    end
    s.start(p_sequencer.axil_sqr, this);
    data = s.data;
    resp = s.resp;
  endtask

  task program_job(coproc_job j);
    reg_write(p_sequencer.regmodel.dim_m, j.m());
    reg_write(p_sequencer.regmodel.dim_n, j.n());
    reg_write(p_sequencer.regmodel.dim_k, j.k);
  endtask

  task start_job();
    reg_write(p_sequencer.regmodel.ctrl, 1);
  endtask

  // Sends the A and B streams of the job and sets the C back-pressure for it.
  task stream_job(coproc_job j);
    axis_beats_seq sa = axis_beats_seq::type_id::create("sa");
    axis_beats_seq sb = axis_beats_seq::type_id::create("sb");
    j.make_beats(sa.beats, sb.beats);
    sa.gap_pct = j.a_gap_pct;
    sb.gap_pct = j.b_gap_pct;
    p_sequencer.cfg.c_cfg.ready_pct = j.c_ready_pct;
    p_sequencer.cfg.c_cfg.stall_pct = j.c_stall_pct;
    fork
      sa.start(p_sequencer.a_sqr, this);
      sb.start(p_sequencer.b_sqr, this);
    join
  endtask

  // Waits until the scoreboard has checked `jobs` jobs, then until STATUS shows BUSY = 0.
  task wait_job(int unsigned jobs, int unsigned max_cycles);
    bit timeout = 1'b0;
    fork
      begin
        fork
          wait (p_sequencer.scb.jobs >= jobs);
          begin
            repeat (max_cycles) @(posedge p_sequencer.cfg.tb_vif.clk_sys);
            timeout = 1'b1;
          end
        join_any
        disable fork;
      end
    join
    if (timeout) begin
      `uvm_fatal("VSEQ", $sformatf("Job %0d not finished after %0d cycles", jobs, max_cycles))
    end
    wait_not_busy();
  endtask

  task wait_not_busy(int unsigned max_reads = 1000);
    uvm_reg_data_t v;
    repeat (max_reads) begin
      reg_read(p_sequencer.regmodel.status, v);
      if (v[0] == 1'b0) return;
    end
    `uvm_error("VSEQ", "STATUS.BUSY did not clear")
  endtask

  // A whole job, as software and the DMA would run it.
  task run_job(coproc_job j);
    int unsigned jobs = p_sequencer.scb.jobs + 1;
    j.make_matrices();
    `uvm_info("VSEQ", $sformatf("Job %0d: %s", jobs, j.convert2string()), UVM_MEDIUM)
    if (j.early_streams) begin
      fork
        stream_job(j);
        begin
          // Let the stream FIFOs fill before the job starts.
          repeat ($urandom_range(30, 1)) @(posedge p_sequencer.cfg.tb_vif.clk_sys);
          program_job(j);
          start_job();
        end
      join
    end else begin
      program_job(j);
      start_job();
      stream_job(j);
    end
    wait_job(jobs, j.max_cycles());
  endtask

endclass
