# SoC Top Integration — Architecture Decisions

## map_read_req: MAP_WAIT prefetch (dda_core.sv)

**Bug:** `assign map_read_req = (state == MARCH)` caused stale BRAM data at the start of each new
raycasting round.

**Root cause:** The per-core map BRAMs have registered (synchronous) outputs.  On the first MARCH
step of a new round, the BRAM output register still held the value latched during the *previous*
round's last MAP_WAIT→MARCH transition.  If that last cell was a wall (`map_data = 1`), the DDA
immediately reported a false hit, producing `'#'` (distance < 1.0) in only ~8 cycles.  Rounds that
completed abnormally fast created a secondary problem: the gpu_collector's `pend_valid` guard
(`if (core_done[i] && !pend_valid[i])`) dropped the short-round results for cores that still had
unserviced previous-round results pending.

**Fix (line ~80, dda_core.sv):**
```sv
assign map_read_req = (state == MAP_WAIT) | (state == MARCH);
```
MAP_WAIT now issues the read one cycle early, so by the time MARCH executes the BRAM output
register holds current-cell data.  The pipeline is:
```
MAP_WAIT_k  → BRAM latches map[cell_k]
MARCH_k     → reads map[cell_k]   ✓
```

**Verification:** `sim/tb_soc/tb_soc_top.cpp` — 80/80 columns match `software/ref/raycaster_ref.py`
for player at (2.5, 2.5), angle = 0.  Frame completes in 828 cycles.

---

## GPU collector bypass (soc_top.sv)

The GPU collector writes directly to `char_framebuffer` — it is NOT routed through the AXI fabric.
This avoids fabric arbitration latency during the per-column write bursts, and the collector's own
AXI FSM (W_IDLE → W_ADDR → W_DATA → W_RESP) is sufficient for the single-master write stream.

Address translation: `cfb_awaddr_w = gcoll_awaddr[11:0]` strips the `VGA_FB_BASE` (0x20000000)
prefix that the collector sets; the framebuffer slave sees a 12-bit offset.

---

## Simulation CPU bypass (SIMULATION generate block)

When `GSIMULATION=1`, `soc_top` exposes four port groups:
- `sim_cpu_aw/w/b/ar/r` — direct AXI4-Lite master ports replacing PicoRV32
- `sim_map_addr/wdata/wen/core` — backdoor write ports into each core's map BRAM

This lets the testbench load the map in O(n) cycles (no AXI overhead) and write GPU MMIO
registers without a real firmware image.

---

## Frame-done polling strategy

The testbench monitors `soc_top__DOT__u_gpu__DOT__frame_done` directly via Verilator's
`--public-flat-rw` rather than polling `GPU_CTRL.frame_done` over AXI.  This avoids dozens of
AXI read transactions (each taking ~5 cycles through the fabric) per polling interval.
