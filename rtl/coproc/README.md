# Matrix multiplication coprocessor

An 8×8 output-stationary systolic array that computes `C = A·B` from signed int8 inputs into int32
results (wrap-around, no saturation). `M`, `N` and `K` must be multiples of 8. Each processing
element adds `a·b` to its accumulator and passes `a` east and `b` south through registers, so the
critical path is one int8 multiply plus one int32 add.

The array runs on its own clock (`clk_acc_i`). The asynchronous FIFOs on the streams and the CDC
on the register port belong to this block, so all its other ports are in the system clock domain.

## Operation

After `START`, the array computes the 8×8 tiles of C in row-major tile order: (0,0), (0,1), …,
(M/8−1, N/8−1). For each tile it takes K beats from the A stream and K beats from the B stream,
one of each per step, then sends the tile's 16 beats on the C stream. It stalls while an input
FIFO is empty or the C FIFO is full. `DONE` is set after the last C beat.

## Modules

| Module | Function |
|---|---|
| `coproc_pkg` | Datapath types (`data_t` int8, `acc_t` int32) and the array size `ARRAY_DIM` |
| `coproc_mac` | `acc = acc + a*b`, one accumulator, cleared at the first step of a tile |
| `coproc_pe` | Processing element: a `coproc_mac` plus the registers that pass `a` east and `b` south |
| `coproc_demux` | One-hot fan-out, used to load one edge of the array per cycle from a single port |
| `coproc_pe_array` | `Dim x Dim` PEs with the `clr` pulse pipelined along the same diagonal as the operands |

`coproc_pe_array` computes one tile from already-skewed edge streams: `a_i[r]` carries `A[r][k]`
at step `k+r` and `b_i[c]` carries `B[k][c]` at step `k+c`, and a tile is `K` steps of data plus
`2*(Dim-1)` drain steps. The skew and drain logic, the tile sequencer that walks the tiles of C,
the AXI4-Lite registers, the stream FIFOs and the CDC are not written yet.

## Matrix layout

The matrices are stored in the order the array consumes them:

| Matrix | Stored as | Byte offset in its buffer |
|---|---|---|
| A (M×K, int8) | M/8 panels of 8 rows, each panel column-major | `A[8i+r][k]` → `8K·i + 8k + r` |
| B (K×N, int8) | N/8 panels of 8 columns, each panel row-major | `B[k][8j+c]` → `8K·j + 8k + c` |
| C (M×N, int32) | 8×8 tiles in row-major tile order, each tile row-major | `C[8i+r][8j+c]` → `256·(i·N/8 + j) + 4·(8r + c)` |

One A beat holds `A[8i..8i+7][k]`, one B beat holds `B[k][8j..8j+7]` and two C beats hold one row
of a tile. Buffer addresses: [SoC memory map](../top/README.md#matrix-buffers-in-l2).

## Registers

Base `0x4000_2000`:

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x00` | `CTRL` | RW | Bit 0 `START` (write 1 to start, reads 0) |
| `0x04` | `STATUS` | RO / W1C | Bit 0 `BUSY` (RO), bit 1 `DONE` (W1C) |
| `0x08` | `DIM_M` | RW | Rows of A and C |
| `0x0C` | `DIM_N` | RW | Columns of B and C |
| `0x10` | `DIM_K` | RW | Columns of A, rows of B |

Writes to `DIM_*` while `BUSY` is set are ignored. The coprocessor has no interrupt: software waits
for DMA channel 2, which finishes after the last C beat is in L2.

## Ports

| Port | Dir | Description |
|---|---|---|
| `clk_i`, `rst_ni` | in | System clock and reset (register and stream ports) |
| `clk_acc_i`, `rst_acc_ni` | in | Array clock and reset |
| `reg_req_i`, `reg_rsp_o` | in, out | AXI4-Lite slave: registers |
| `a_tdata_i[63:0]`, `a_tvalid_i`, `a_tready_o` | in, in, out | A stream |
| `b_tdata_i[63:0]`, `b_tvalid_i`, `b_tready_o` | in, in, out | B stream |
| `c_tdata_o[127:0]`, `c_tvalid_o`, `c_tready_i` | out, out, in | C stream |

---
[← Back to RTL](../README.md)
