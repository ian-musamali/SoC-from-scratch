# AXI DMA Controller — Design Decisions

## Purpose

The DMA controller moves word-aligned blocks of data between any two AXI4-Lite addresses without CPU involvement. Primary use: the GPU firmware loop writes player state to GPU MMIO, triggers a frame, and then the DMA copies the finished ASCII framebuffer from GPU BRAM to the VGA framebuffer address (0x20000000) while the CPU prepares the next frame.

## Interface

```
start       — one-cycle pulse: begin transfer
src_addr    — source byte address (word-aligned)
dst_addr    — destination byte address (word-aligned)
byte_len    — byte count, must be multiple of 4
done        — one-cycle pulse: transfer complete
```

Plus AXI4-Lite read master (AR/R) and write master (AW/W/B).

## State Machine

```
IDLE → RD_ADDR → RD_DATA → WR_ADDR → WR_DATA → WR_RESP → (RD_ADDR or DONE_ST)
```

| State    | Action                                               |
|----------|------------------------------------------------------|
| IDLE     | Waits for start; latches src, dst, words_rem         |
| RD_ADDR  | If words_rem=0 → DONE_ST. Else presents AR; →RD_DATA|
| RD_DATA  | Waits for AR handshake, then R handshake; →WR_ADDR   |
| WR_ADDR  | Presents AW and W simultaneously; →WR_DATA           |
| WR_DATA  | Waits for both AW and W handshakes; →WR_RESP         |
| WR_RESP  | Waits for B handshake; advances pointers; →RD_ADDR   |
| DONE_ST  | Pulses done for one cycle; →IDLE                    |

## Key Design Decision: WR_DATA Transition Condition

Non-blocking assignments (NBA) in SystemVerilog mean that after `if (m_aw_ready) m_aw_valid <= 0`, the register `m_aw_valid` still reads as 1 within the same always block. A naive check `if (!m_aw_valid && !m_w_valid)` would therefore never fire in the cycle where the last channel is accepted.

**Fix**: re-express the condition using current (pre-NBA) values:

```sv
// "Channel is done" = already idle OR being accepted right now
if ((!m_aw_valid || m_aw_ready) && (!m_w_valid || m_w_ready))
    state <= WR_RESP;
```

This correctly handles all cases:
- Both channels accepted simultaneously (m_aw_ready && m_w_ready both 1)
- AW accepted first, W accepted in a later cycle
- W accepted first (same logic)
- Either channel already cleared from a previous cycle

## Testbench AXI Slave Model

The DMA transitions WR_DATA→WR_RESP in the **same** cycle that the W channel is accepted. Therefore bvalid must appear in the **next** cycle (when the DMA is in WR_RESP). Using a `b_hold` flag:

```
Cycle N:   m_w_ready=1, W fires → set b_hold=true, m_b_valid=0
Cycle N+1: m_b_valid=1 (from b_hold) → DMA in WR_RESP sees bvalid → advances
```

A zero-latency bvalid (same cycle as W) is silently ignored by WR_DATA and then missed in WR_RESP.

## Simulation Results

| Test                    | Result |
|-------------------------|--------|
| 4-word transfer (done)  | PASS   |
| 4-word word 0 data      | PASS   |
| 4-word word 1 data      | PASS   |
| 4-word word 2 data      | PASS   |
| 4-word word 3 data      | PASS   |
| zero-length done        | PASS   |
| single-word done        | PASS   |
| single-word data        | PASS   |

8/8 PASS.

## Cycles Per Transfer

- Zero-length: ~3 cycles (IDLE→RD_ADDR→DONE_ST→IDLE)
- Per word: ~8 cycles (AR handshake + R handshake + WR_ADDR + WR_DATA + WR_RESP + RD_ADDR overhead)
- 80-column ASCII frame: 80 words × ~8 cycles = ~640 cycles (~6.4 µs @ 100 MHz)
