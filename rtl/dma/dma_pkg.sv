// DMA package: shared parameters, register offsets, configuration structs, FSM enums and
// default AXI4 / AXI4-Lite packed request/response structs.
package dma_pkg;

  // Bus and stream widths
  parameter int unsigned AXI_ADDR_W   = 32;
  parameter int unsigned AXI_DATA_W   = 128;
  parameter int unsigned AXI_STRB_W   = AXI_DATA_W / 8;  // 16 bytes per beat
  parameter int unsigned AXI_ID_W     = 2;
  parameter int unsigned AXIL_ADDR_W  = 12;              // 4 KiB register window
  parameter int unsigned AXIL_DATA_W  = 32;
  parameter int unsigned AXIL_STRB_W  = AXIL_DATA_W / 8;
  parameter int unsigned AB_STREAM_W  = 64;
  parameter int unsigned C_STREAM_W   = 128;

  // Channel configuration
  parameter int unsigned NUM_CHANNELS    = 3;
  parameter int unsigned CH_A            = 0;
  parameter int unsigned CH_B            = 1;
  parameter int unsigned CH_C            = 2;
  parameter int unsigned MAX_BURST_BEATS = 16;  // Up to 16 beats (256 B) per AXI4 INCR burst
  parameter int unsigned FIFO_DEPTH      = 16;  // Must be >= MAX_BURST_BEATS and power of 2

  // AXI4 fixed encodings
  parameter logic [1:0] AXI_RESP_OKAY   = 2'b00;
  parameter logic [1:0] AXI_RESP_SLVERR = 2'b10;
  parameter logic [1:0] AXI_RESP_DECERR = 2'b11;
  parameter logic [1:0] AXI_BURST_INCR  = 2'b01;
  parameter logic [2:0] AXI_SIZE_16B    = 3'd4;  // 2^4 = 16 bytes (128-bit)

  // Register offsets within each channel's 0x20-byte slice (base + 0x20 * ch)
  parameter logic [4:0] REG_ADDR    = 5'h00;
  parameter logic [4:0] REG_LEN     = 5'h04;
  parameter logic [4:0] REG_CNT1    = 5'h08;
  parameter logic [4:0] REG_STRIDE1 = 5'h0C;
  parameter logic [4:0] REG_CNT2    = 5'h10;
  parameter logic [4:0] REG_STRIDE2 = 5'h14;
  parameter logic [4:0] REG_CTRL    = 5'h18;
  parameter logic [4:0] REG_STATUS  = 5'h1C;

  // Bit positions in CTRL and STATUS
  parameter int unsigned CTRL_START_BIT  = 0;
  parameter int unsigned CTRL_IRQ_EN_BIT = 1;
  parameter int unsigned STAT_BUSY_BIT   = 0;
  parameter int unsigned STAT_DONE_BIT   = 1;
  parameter int unsigned STAT_ERR_BIT    = 2;

  // Per-channel 3D transfer descriptor
  typedef struct packed {
    logic [31:0] addr;
    logic [31:0] len;
    logic [31:0] cnt1;
    logic [31:0] stride1;
    logic [31:0] cnt2;
    logic [31:0] stride2;
  } dma_ch_cfg_t;

  // Default AXI4-Lite packed structs (PULP axi_lite field layout)
  typedef struct packed {
    logic [AXIL_ADDR_W-1:0] addr;
    logic [2:0]             prot;
  } dma_axil_aw_t;

  typedef struct packed {
    logic [AXIL_DATA_W-1:0] data;
    logic [AXIL_STRB_W-1:0] strb;
  } dma_axil_w_t;

  typedef struct packed {
    logic [1:0] resp;
  } dma_axil_b_t;

  typedef struct packed {
    logic [AXIL_ADDR_W-1:0] addr;
    logic [2:0]             prot;
  } dma_axil_ar_t;

  typedef struct packed {
    logic [AXIL_DATA_W-1:0] data;
    logic [1:0]             resp;
  } dma_axil_r_t;

  typedef struct packed {
    dma_axil_aw_t aw;
    logic         aw_valid;
    dma_axil_w_t  w;
    logic         w_valid;
    logic         b_ready;
    dma_axil_ar_t ar;
    logic         ar_valid;
    logic         r_ready;
  } dma_axil_req_t;

  typedef struct packed {
    logic        aw_ready;
    logic        w_ready;
    dma_axil_b_t b;
    logic        b_valid;
    logic        ar_ready;
    dma_axil_r_t r;
    logic        r_valid;
  } dma_axil_rsp_t;

  // Default AXI4 128-bit master packed structs (PULP axi field layout)
  typedef struct packed {
    logic [AXI_ID_W-1:0]   id;
    logic [AXI_ADDR_W-1:0] addr;
    logic [7:0]            len;
    logic [2:0]            size;
    logic [1:0]            burst;
    logic                  lock;
    logic [3:0]            cache;
    logic [2:0]            prot;
    logic [3:0]            qos;
    logic [3:0]            region;
  } dma_axi_aw_t;

  typedef struct packed {
    logic [AXI_DATA_W-1:0] data;
    logic [AXI_STRB_W-1:0] strb;
    logic                  last;
  } dma_axi_w_t;

  typedef struct packed {
    logic [AXI_ID_W-1:0] id;
    logic [1:0]          resp;
  } dma_axi_b_t;

  typedef struct packed {
    logic [AXI_ID_W-1:0]   id;
    logic [AXI_ADDR_W-1:0] addr;
    logic [7:0]            len;
    logic [2:0]            size;
    logic [1:0]            burst;
    logic                  lock;
    logic [3:0]            cache;
    logic [2:0]            prot;
    logic [3:0]            qos;
    logic [3:0]            region;
  } dma_axi_ar_t;

  typedef struct packed {
    logic [AXI_ID_W-1:0]   id;
    logic [AXI_DATA_W-1:0] data;
    logic [1:0]            resp;
    logic                  last;
  } dma_axi_r_t;

  typedef struct packed {
    dma_axi_aw_t aw;
    logic        aw_valid;
    dma_axi_w_t  w;
    logic        w_valid;
    logic        b_ready;
    dma_axi_ar_t ar;
    logic        ar_valid;
    logic        r_ready;
  } dma_axi_req_t;

  typedef struct packed {
    logic       aw_ready;
    logic       w_ready;
    dma_axi_b_t b;
    logic       b_valid;
    logic       ar_ready;
    dma_axi_r_t r;
    logic       r_valid;
  } dma_axi_rsp_t;

  // FSM state encodings
  typedef enum logic [0:0] {
    AddrIdle = 1'b0,
    AddrRun  = 1'b1
  } dma_addr_state_e;

  typedef enum logic [2:0] {
    RdIdle    = 3'd0,
    RdReqAr   = 3'd1,
    RdWaitR   = 3'd2,
    RdDrain   = 3'd3,
    RdErrDone = 3'd4
  } dma_rd_state_e;

  typedef enum logic [2:0] {
    WrIdle    = 3'd0,
    WrWaitDat = 3'd1,
    WrReqAw   = 3'd2,
    WrSendW   = 3'd3,
    WrWaitB   = 3'd4,
    WrErrDone = 3'd5
  } dma_wr_state_e;

endpackage
