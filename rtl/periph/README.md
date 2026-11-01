# Peripherals

## Timer

RISC-V machine timer. `mtime` counts `clk_i` cycles, and `irq_o` (`MTIP`) is high while
`mtime ≥ mtimecmp`.

Base `0x4000_0000`:

| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| `0x00` | `MTIME_LO` | RW | 0 | `mtime[31:0]` |
| `0x04` | `MTIME_HI` | RW | 0 | `mtime[63:32]` |
| `0x08` | `MTIMECMP_LO` | RW | `0xFFFF_FFFF` | `mtimecmp[31:0]` |
| `0x0C` | `MTIMECMP_HI` | RW | `0xFFFF_FFFF` | `mtimecmp[63:32]` |

Ports: `clk_i`, `rst_ni`, AXI4-Lite slave (`reg_req_i`, `reg_rsp_o`) and `irq_o`.

---
[← Back to RTL](../README.md)
