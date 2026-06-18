# AXI4-Lite Fabric

## Why AXI4-Lite

| Criterion | Rationale |
|-----------|-----------|
| PicoRV32 native | PicoRV32 has an optional AXI4-Lite master port; no adapter needed |
| IP compatibility | All Xilinx peripherals (UART, BRAM controller) offer AXI4-Lite slave interfaces |
| No burst needed | All accesses are register-sized (32-bit); burst adds complexity with zero benefit here |
| Correctness | 5 independent channels decouple address, data, and response handshakes — no deadlock from backpressure |
| Simplicity | AXI4-Lite omits bursts, narrow transfers, and out-of-order IDs; the full spec fits in ~200 lines of RTL |

## Address Map

| Slave | Base | Size | Bits [31:28] |
|-------|------|------|--------------|
| BRAM (instr+data) | 0x00000000 | 256 KB | 0x0 |
| UART (debug TX) | 0x10000000 | 4 KB | 0x1 |
| VGA framebuffer | 0x20000000 | 4 KB | 0x2 |
| GPU MMIO | 0x30000000 | 32 B | 0x3 |

Address decode uses bits [31:28] only — upper nibble decode. This leaves bits [27:0] as the byte offset within each slave, simplifying slave address receivers.

## 5-Channel Summary

| Channel | Direction | Purpose |
|---------|-----------|---------|
| AW (Write Address) | Master → Slave | Delivers write target address and transaction ID |
| W (Write Data) | Master → Slave | Delivers write data and byte strobes |
| B (Write Response) | Slave → Master | Slave confirms write with OKAY/SLVERR response code |
| AR (Read Address) | Master → Slave | Delivers read target address |
| R (Read Data) | Slave → Master | Slave returns read data and response code |

## 2-Master Arbitration

**Write channels (AW/W/B) and read channels (AR/R) are arbitrated independently.**

Algorithm: round-robin with DMA priority on tie.
- `w_last_grant` / `r_last_grant` bit tracks which master was last served.
- When both masters request simultaneously, M1 (DMA) wins if `w_last_grant == 0` (M0 was last).
- When only one master requests, it is served immediately.
- The grant is locked for the duration of the transaction (from AW accept to B handshake).

**Rationale for DMA priority on tie**: GPU frame rendering stalls CPU execution anyway (CPU polls `frame_done`). Giving DMA the tie-break keeps the GPU data path moving without introducing a separate priority scheme.

**No deadlock**: Write and read arbiters are independent. A stalled write cannot block a read from completing. Each slave has separate AW/W/B and AR/R ports.

## Simulation Results

All 33 routing checks PASS:
- M0 write routes to each of S0, S1, S2, S3 correctly
- M1 write routes to S0 correctly
- Simultaneous M0+M1 write: M1 wins, M0 stalled (awready=0)
- M0 read from S0: arvalid, arready, rvalid, rdata all correct
