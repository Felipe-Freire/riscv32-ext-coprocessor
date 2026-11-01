# DMA

Three fixed channels move the matrices between the L2 SRAM and the coprocessor:

| Channel | Direction | Stream |
|---|---|---|
| 0 | L2 → coprocessor | A, 64-bit |
| 1 | L2 → coprocessor | B, 64-bit |
| 2 | Coprocessor → L2 | C, 128-bit |

Each channel transfers a 3D block: `CNT2` planes of `CNT1` rows of `LEN` bytes. Row `r` of plane
`p` starts at `ADDR + p·STRIDE2 + r·STRIDE1`; rows go first, then planes. A stride of 0 repeats
the same data. Channels 0 and 1 split each 128-bit word into two stream beats, low half first.
Rows become AXI4 INCR bursts that do not cross a 4 KiB boundary, and reads (channels 0 and 1) run
in parallel with writes (channel 2).

## Registers

Base `0x4000_1000`. Channel `n` (0–2) is at offset `0x20·n`:

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x00` | `ADDR` | RW | L2 start address, 16-byte aligned |
| `0x04` | `LEN` | RW | Bytes per row, multiple of 16 |
| `0x08` | `CNT1` | RW | Rows per plane, ≥ 1 |
| `0x0C` | `STRIDE1` | RW | Address step between rows, multiple of 16 |
| `0x10` | `CNT2` | RW | Planes, ≥ 1 |
| `0x14` | `STRIDE2` | RW | Address step between planes, multiple of 16 |
| `0x18` | `CTRL` | RW | Bit 0 `START` (write 1 to start, reads 0), bit 1 `IRQ_EN` |
| `0x1C` | `STATUS` | RO / W1C | Bit 0 `BUSY` (RO), bit 1 `DONE` (W1C), bit 2 `ERR` (W1C) |

`DONE` is set when the last beat is accepted by the stream (channels 0, 1) or written to L2
(channel 2). `ERR` is set on an AXI error response, and the channel stops. Writes to a busy
channel's registers are ignored. `irq_o` is high while any channel has `IRQ_EN` set together with
`DONE` or `ERR`.

## Ports

| Port | Dir | Description |
|---|---|---|
| `clk_i`, `rst_ni` | in | System clock and reset |
| `reg_req_i`, `reg_rsp_o` | in, out | AXI4-Lite slave: registers |
| `axi_req_o`, `axi_rsp_i` | out, in | AXI4 master, 128-bit: L2 |
| `a_tdata_o[63:0]`, `a_tvalid_o`, `a_tready_i` | out, out, in | A stream |
| `b_tdata_o[63:0]`, `b_tvalid_o`, `b_tready_i` | out, out, in | B stream |
| `c_tdata_i[127:0]`, `c_tvalid_i`, `c_tready_o` | in, in, out | C stream |
| `irq_o` | out | Interrupt to the core (`MEIP`) |

AXI4 and AXI4-Lite ports are packed request/response structs (`_req_t`, `_rsp_t`).

---
[← Back to RTL](../README.md)
