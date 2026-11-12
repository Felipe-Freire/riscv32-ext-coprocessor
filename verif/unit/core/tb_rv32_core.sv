// rv32_core: runs tb_rv32_core.mem, a directed, self-checking program built from tb_rv32_core.S
// (coverage and rebuild commands are in that file).
//
// The program stores (checks passed << 1) | pass to TOHOST, and word 1 of the image holds the
// number of checks, so a check skipped by a broken branch also fails. The image is read from the
// directory of this file; +MEM=<path> selects another one.
//
// Memory map. Instructions: 1 KiB at address 0. Data: TCM answers at once, BUS grants after 2
// cycles and answers 2 cycles later, MMIO holds TOHOST (+0), clears irq_timer (+4) and raises it a
// few cycles later (+8), and any other address answers with an error.
module tb_rv32_core;
  import rv32_pkg::*;

  localparam int          ImemWords  = 256;
  localparam logic [15:0] TcmRegion  = 16'h0000;   // address bits 31:16
  localparam logic [15:0] BusRegion  = 16'h0001;
  localparam logic [15:0] MmioRegion = 16'h0002;

  logic        clk = 1'b0, rst_n = 1'b0;
  logic        instr_req, instr_err;
  logic [31:0] instr_addr, instr_rdata;
  logic        data_req, data_gnt, data_we, data_rvalid, data_err;
  logic [31:0] data_addr, data_wdata, data_rdata;
  logic [3:0]  data_be;
  logic        irq_timer;

  always #5 clk = ~clk;

  rv32_core dut (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .instr_req_o   (instr_req),
    .instr_addr_o  (instr_addr),
    .instr_rdata_i (instr_rdata),
    .instr_err_i   (instr_err),
    .data_req_o    (data_req),
    .data_gnt_i    (data_gnt),
    .data_addr_o   (data_addr),
    .data_we_o     (data_we),
    .data_be_o     (data_be),
    .data_wdata_o  (data_wdata),
    .data_rvalid_i (data_rvalid),
    .data_rdata_i  (data_rdata),
    .data_err_i    (data_err),
    .irq_timer_i   (irq_timer),
    .irq_external_i(1'b0)
  );

  // ---- Instruction memory: data one cycle after the request, held while the request is low

  logic [31:0] imem [ImemWords];

  always_ff @(posedge clk) begin
    if (instr_req) begin
      instr_err   <= instr_addr[31:2] >= ImemWords;
      instr_rdata <= instr_addr[31:2] < ImemWords ? imem[instr_addr[31:2]] : '0;
    end
  end

  // ---- Data memory (TCM and BUS share the words) and MMIO

  logic [31:0] dmem [256];
  logic        is_bus, pending, tohost_valid;
  logic [31:0] tohost, rsp_data;
  int          gnt_wait, rsp_wait, irq_delay;

  assign is_bus      = data_addr[31:16] == BusRegion;
  assign data_gnt    = data_req & (~is_bus | gnt_wait == 2);
  assign data_rvalid = pending & rsp_wait == 0;
  assign data_rdata  = data_rvalid ? rsp_data : 32'hDEAD_BEEF;   // valid only with rvalid

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pending      <= 1'b0;
      gnt_wait     <= 0;
      irq_timer    <= 1'b0;
      irq_delay    <= 0;
      tohost_valid <= 1'b0;
    end else begin
      gnt_wait <= (data_req && !data_gnt) ? gnt_wait + 1 : 0;
      if (data_rvalid)  pending  <= 1'b0;
      else if (pending) rsp_wait <= rsp_wait - 1;
      if (irq_delay == 1) irq_timer <= 1'b1;
      if (irq_delay != 0) irq_delay <= irq_delay - 1;

      if (data_req && data_gnt) begin
        pending    <= 1'b1;
        rsp_wait   <= is_bus ? 2 : 0;
        data_err   <= !(data_addr[31:16] inside {TcmRegion, BusRegion, MmioRegion});
        rsp_data   <= dmem[data_addr[9:2]];
        if (data_we && data_addr[31:16] inside {TcmRegion, BusRegion}) begin
          for (int b = 0; b < 4; b++) begin
            if (data_be[b]) dmem[data_addr[9:2]][8*b +: 8] <= data_wdata[8*b +: 8];
          end
        end
        if (data_we && data_addr[31:16] == MmioRegion) begin
          unique case (data_addr[3:2])
            2'd0: begin
              tohost       <= data_wdata;
              tohost_valid <= 1'b1;
            end
            2'd1:    irq_timer <= 1'b0;
            default: irq_delay <= 5;
          endcase
        end
      end
    end
  end

  // ---- OBI: a request stays, unchanged, until it is granted

  int errors = 0;

  always @(posedge clk) begin
    if (rst_n && data_req && !data_gnt) begin
      logic [31:0] addr;
      addr = data_addr;
      @(negedge clk);
      if (!data_req || data_addr !== addr) begin
        errors++;
        $display("FAIL: data request dropped or changed before its grant at %0t", $time);
      end
    end
  end

  // Next to this file, unless +MEM=<path> is given.
  function automatic string image_path();
    string path, file;
    if ($value$plusargs("MEM=%s", path)) return path;
    file = `__FILE__;
    for (int i = file.len() - 1; i >= 0; i--) begin
      if (file[i] == "/") return {file.substr(0, i), "tb_rv32_core.mem"};
    end
    return "tb_rv32_core.mem";
  endfunction

  initial begin
    string image;
    int    fd, cycles;

    image = image_path();
    fd = $fopen(image, "r");
    if (fd == 0) begin
      $display("FAIL: cannot open %s", image);
      $finish;
    end
    $fclose(fd);
    imem = '{default: '0};   // past the program: illegal instruction, not X
    $readmemh(image, imem);

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    for (cycles = 0; cycles < 5000 && !tohost_valid; cycles++) @(negedge clk);

    if (!tohost_valid) begin
      $display("FAIL: timeout after %0d cycles", cycles);
    end else if (!tohost[0]) begin
      $display("FAIL: check %0d failed", tohost[31:1] + 1);
    end else if (tohost[31:1] != imem[1]) begin
      $display("FAIL: %0d of %0d checks ran", tohost[31:1], imem[1]);
    end else if (errors != 0) begin
      $display("FAIL: %0d bus errors", errors);
    end else begin
      $display("PASS: %0d checks, %0d cycles", imem[1], cycles);
    end
    $finish;
  end

endmodule
