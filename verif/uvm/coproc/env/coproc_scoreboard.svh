// Checks coproc_top against the golden model (verif/models/coproc). The model is fed with what the
// monitors saw: every completed AXI4-Lite access, and every A and B beat the block took. Each C
// beat is compared, word by word, with the model's next C words; each register response and read
// value is compared with the model's.
//
// The model has no time, so one thing needs care: the end of a job. The block clears BUSY and sets
// DONE when the last C beat leaves the core, which can be before or after that beat has crossed
// the C FIFO and reached the monitor. So while a job is open, a STATUS read may show the block
// still busy (BUSY = 1, DONE = 0) or already finished (BUSY = 0) when the model says otherwise.
// A job closes once the model has every C word and a STATUS read has shown BUSY = 0; from then on
// STATUS must match exactly. A START written before the previous job has closed is an error of
// the test, not of the block: the block may or may not take it.

`uvm_analysis_imp_decl(_reg)
`uvm_analysis_imp_decl(_a)
`uvm_analysis_imp_decl(_b)
`uvm_analysis_imp_decl(_c)

class coproc_scoreboard extends uvm_component;

  uvm_analysis_imp_reg #(axil_item, coproc_scoreboard) reg_export;
  uvm_analysis_imp_a #(axis_item, coproc_scoreboard)   a_export;
  uvm_analysis_imp_b #(axis_item, coproc_scoreboard)   b_export;
  uvm_analysis_imp_c #(axis_item, coproc_scoreboard)   c_export;
  uvm_analysis_port #(coproc_job_info)                 job_ap;

  coproc_env_cfg cfg;

  localparam int unsigned WordsPerBeat = 128 / coproc_pkg::ACC_W;
  localparam int unsigned Dim          = coproc_pkg::ARRAY_DIM;

  chandle model;

  // Counters for the report; jobs is also what the sequences wait on.
  int unsigned jobs;
  int unsigned c_words;
  int unsigned reg_accesses;

  bit             job_open;       // from an accepted START until the job has closed
  bit             busy_low_seen;  // a STATUS read showed BUSY = 0 since that START
  bit             ran_since_reset;
  coproc_job_info info;

  `uvm_component_utils(coproc_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    reg_export = new("reg_export", this);
    a_export   = new("a_export", this);
    b_export   = new("b_export", this);
    c_export   = new("c_export", this);
    job_ap     = new("job_ap", this);
    model      = coproc_model_new(Dim, coproc_pkg::DIM_CNT_W);
    if (model == null) begin
      `uvm_fatal("SCB", "Could not create the golden model")
    end
  endfunction

  // A reset of the block resets the model: queued beats and the running job are gone.
  task run_phase(uvm_phase phase);
    forever begin
      @(negedge cfg.tb_vif.rst_n);
      coproc_model_reset(model);
      job_open        = 1'b0;
      busy_low_seen   = 1'b0;
      ran_since_reset = 1'b0;
      info            = null;
      `uvm_info("SCB", "Reset: golden model reset", UVM_MEDIUM)
    end
  endtask

  // ---- Registers ---------------------------------------------------------------------------

  function void write_reg(axil_item t);
    int unsigned off = t.addr & 'hFFF;
    int unsigned exp_resp, exp_data;
    bit          was_busy = coproc_model_busy(model);

    reg_accesses++;
    if (was_busy && info != null) info.busy_accesses++;

    if (t.kind == AxilWrite) begin
      if ((off & ~3) == COPROC_REG_CTRL && t.strb[0] && t.data[0] && job_open && !was_busy) begin
        `uvm_error("SCB", "START written before STATUS showed that the previous job had ended")
      end
      exp_resp = coproc_model_reg_write(model, off, t.data, t.strb);
      check_resp(t, exp_resp);
      if (!was_busy && coproc_model_busy(model)) begin
        job_started();
      end
    end else begin
      exp_resp = coproc_model_reg_read(model, off, exp_data);
      check_resp(t, exp_resp);
      if ((off & ~3) == COPROC_REG_STATUS && exp_resp == COPROC_RESP_OKAY) begin
        check_status(t.data, exp_data);
      end else if (t.data !== exp_data) begin
        `uvm_error("SCB", $sformatf("Read 0x%03h = 0x%08h, expected 0x%08h", off, t.data, exp_data))
      end
    end
  endfunction

  function void check_resp(axil_item t, int unsigned exp_resp);
    if (t.resp !== exp_resp[1:0]) begin
      `uvm_error("SCB", $sformatf("%s: response %0d, expected %0d", t.convert2string(), t.resp,
                                  exp_resp))
    end
  endfunction

  function void check_status(bit [31:0] got, int unsigned exp);
    bit model_busy = coproc_model_busy(model);
    bit ok;
    if (!job_open) begin
      ok = (got == exp);
    end else begin
      if (got[0] == 1'b0) busy_low_seen = 1'b1;
      ok = (got == exp)                             // block and model agree
        || (got == 32'h1)                           // the end has not crossed back yet
        || (model_busy && got[31:2] == 0 && !got[0]);  // C words still in the C FIFO
      if (!model_busy && busy_low_seen) job_open = 1'b0;
    end
    if (!ok) begin
      `uvm_error("SCB", $sformatf("STATUS = 0x%08h, expected 0x%08h (job %s)", got, exp,
                                  job_open ? "running" : "closed"))
    end
  endfunction

  function void job_started();
    int unsigned d;
    info = coproc_job_info::type_id::create("info");
    void'(coproc_model_reg_read(model, COPROC_REG_DIM_M, d)); info.m = d;
    void'(coproc_model_reg_read(model, COPROC_REG_DIM_N, d)); info.n = d;
    void'(coproc_model_reg_read(model, COPROC_REG_DIM_K, d)); info.k = d;
    info.tiles_m     = (info.m / Dim == 0) ? 1 : info.m / Dim;
    info.tiles_n     = (info.n / Dim == 0) ? 1 : info.n / Dim;
    info.early_a     = coproc_model_pending_a(model);
    info.early_b     = coproc_model_pending_b(model);
    info.clk_ratio   = cfg.tb_vif.acc_period / cfg.tb_vif.sys_period;
    info.consecutive = ran_since_reset;
    info.start_time  = $time;
    job_open         = 1'b1;
    busy_low_seen    = 1'b0;
    `uvm_info("SCB", $sformatf("Job %0d started: %s", jobs, info.convert2string()), UVM_HIGH)
  endfunction

  // ---- Streams -----------------------------------------------------------------------------

  function void write_a(axis_item t);
    coproc_model_push_a(model, t.data[63:0]);
    if (info != null && t.gap > 0) info.a_gaps++;
  endfunction

  function void write_b(axis_item t);
    coproc_model_push_b(model, t.data[63:0]);
    if (info != null && t.gap > 0) info.b_gaps++;
  endfunction

  function void write_c(axis_item t);
    int unsigned exp_word, ti, tj, row, col;
    bit [31:0]   got;
    bit          was_busy = coproc_model_busy(model);

    if (info != null && t.stall > 0) info.c_stalls++;
    for (int w = 0; w < int'(WordsPerBeat); w++) begin
      coproc_model_c_pos(model, ti, tj, row, col);
      if (!coproc_model_pop_c(model, exp_word)) begin
        `uvm_error("SCB", $sformatf("C beat with no expected data (%s)",
                   coproc_model_busy(model) ? "the A and B beats of the tile are not all in"
                                            : "no job is running"))
        return;
      end
      c_words++;
      got = t.data[32*w +: 32];
      if (got !== exp_word) begin
        `uvm_error("SCB", $sformatf("C[%0d][%0d] (tile %0d,%0d) = %0d, expected %0d",
                                    Dim*ti + row, Dim*tj + col, ti, tj, $signed(got),
                                    $signed(exp_word)))
      end
    end
    if (was_busy && !coproc_model_busy(model)) begin
      job_ended();
    end
  endfunction

  function void job_ended();
    jobs++;
    ran_since_reset = 1'b1;
    if (busy_low_seen) job_open = 1'b0;
    if (info != null) begin
      info.end_time = $time;
      `uvm_info("SCB", $sformatf("Job %0d checked: %s", jobs, info.convert2string()), UVM_MEDIUM)
      job_ap.write(info);
    end
    info = null;
  endfunction

  // ---- End of test -------------------------------------------------------------------------

  function void check_phase(uvm_phase phase);
    if (coproc_model_busy(model)) begin
      `uvm_error("SCB", "A job was still running at the end of the test: C words missing")
    end
    if (coproc_model_pending_a(model) != 0 || coproc_model_pending_b(model) != 0) begin
      `uvm_error("SCB", $sformatf("%0d A and %0d B beats were taken but used by no job",
                                  coproc_model_pending_a(model), coproc_model_pending_b(model)))
    end
    if (jobs < cfg.min_jobs) begin
      `uvm_error("SCB", $sformatf("%0d jobs checked, expected at least %0d", jobs, cfg.min_jobs))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB", $sformatf("%0d jobs, %0d C words and %0d register accesses checked", jobs,
                               c_words, reg_accesses), UVM_NONE)
  endfunction

  function void final_phase(uvm_phase phase);
    coproc_model_free(model);
  endfunction

endclass
