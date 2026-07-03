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

---

## rst_n mixed sync/async usage (lint review, step 14)

Verilator flags `%Warning-SYNCASYNCNET`: `rst_n` is used as an async reset
(`always_ff @(posedge sys_clk or negedge rst_n)`) for the BRAM/fabric control registers in
`soc_top.sv`, but is consumed as a synchronous reset input (`resetn`) inside the vendored
`picorv32.v` core.

**Reviewed and accepted, not a bug.** This is the standard FPGA reset pattern: control/datapath
registers that need a defined value before the clock is running get an async reset; PicoRV32
(like most soft cores) expects a synchronous active-low `resetn` and handles it internally. Both
consumers see the same clean, board-level `rst_n` net — there's no second, independently-timed
reset source, so there's no metastability risk to synchronize away. Fixing this would mean
modifying `picorv32.v`, which is vendored and explicitly out of scope (see `CLAUDE.md`).
Hardware bring-up (bitstream on Nexys A7, WNS +0.420 ns @ 65 MHz) already exercises this reset
path with no observed issue.

---

## Player input via push-buttons (2026-07-02)

Added 5 Nexys A7 push-buttons (BTNU/D/L/R/C) as real player input, replacing the firmware's
auto-rotate-only loop. Pin numbers (M18/P18/P17/M17/N17) came from Digilent's
`Nexys-A7-100T-Master.xdc`, not guessed.

**Wiring:** `fpga_top.sv` owns the async→sys_clk 2-flop synchronizer (buttons are the only
non-reset async board input); the synchronized 5-bit bus threads straight through
`soc_top` → `gpu_top` → `gpu_mmio` as a plain `buttons` port, surfacing as a new read-only
`BUTTONS` register at GPU MMIO offset `0x1C`.

**Why 0x1C:** the GPU MMIO AXI slave is a hard 32-byte window (`axi4lite_fabric.sv`:
`0x30000000`–`0x3000001F`), and `gpu_mmio.sv` decodes on `s_araddr[4:0]` — only 8 word slots
exist. 0x1C was the only one not already used by a real register (see the DMA_CTRL note in
`CLAUDE.md` — that offset was documented but never implemented).

**Firmware:** `main.c` polls `GPU_BUTTONS` once per frame; BTNL/BTNR turn, BTNU/BTND translate
along the current facing direction using a 256-entry Q16.16 sine LUT (`trig_lut.h`, generated
by `gen_trig_lut.py` — same "generate a table, check it in" convention as `map.hex`). All index
math stays in `uint32_t` (no 64-bit ops) since PicoRV32 here is `rv32im`, not `rv32imaf`.

**Wall collision (Step 14c, same day):** `gen_map_hex.py` now emits `map_data.h` alongside
`map.hex` — same `MAP_STR`, same row-major layout, so there's no drift risk between what's
baked into hardware `map_bram` and what firmware checks against. `main.c`'s `tile_is_wall()`
tests the destination tile before committing a move, checking X and Y independently so the
player slides along a wall rather than stopping dead at an angle.

**Verification:** only the RTL wiring and existing `sim/tb_soc` regression (828 cycles, 80/80
PASS, unaffected since it drives the AXI stub path, not real firmware) and a firmware
compile (`make all`, clean under `-Wall`) were checked. No Verilator model of the real
`picorv32.v` + `firmware.hex` exists in this repo, so the button/movement C logic has **not**
been exercised in simulation — it needs real hardware bring-up to confirm.

---

## Real 3D wall-height rendering (2026-07-03)

Before this, "ASCII Doom" wasn't actually 3D. Traced the render path and found
`gpu_collector.sv` wrote exactly one byte per column (`m_awaddr = VGA_FB_BASE + col`, no row
term), so only row 0 of the 80×45 char grid was ever populated — the rest silently stayed at
its reset value (space). What was on screen was a one-character-tall strip of distance-shaded
ASCII across the top of the display, not a Wolfenstein-style view with near walls looming tall.

### Design

`dda_core.sv` already computed `perp_corrected` (the fisheye-corrected perpendicular wall
distance) right before throwing it away on a single `dist_to_ascii()` character choice — that
value is exactly what a classic `h = SCREEN_ROWS / perp_dist` projection needs.

- **Hoisted** the perp-distance calc (`perp_raw`/`fish_mul`/`perp_corrected`) from a local
  variable inside the MARCH branch to module-level combinational signals, so it can also drive
  a divider's denominator the same cycle a wall hit is detected.
- **Added an `fpdiv` instance per core** (`rtl/lib/fpdiv.sv` — already in the tree, unit-tested,
  but never actually instantiated anywhere in the synthesized design before this). Feeding a
  Q16.16 `HEIGHT_CONST_Q = NUM_ROWS<<16` as numerator and `perp_corrected` as denominator gives
  a Q16.16 row count directly, since `fpdiv` computes `(numerator<<16)/denominator`. New
  `HEIGHT_WAIT` FSM state added after `MARCH`'s wall-hit branch; `fpdiv` is 34 cycles and
  strictly multi-cycle, so it never touches the combinational critical path (though see
  Timing below — the *overall* design got tighter anyway, elsewhere).
- Row count clamped to `[1, NUM_ROWS]`; `wall_top = (NUM_ROWS - height) >> 1` centers the band
  vertically. New `dda_core` outputs: `wall_top[5:0]`, `wall_height[5:0]` (ascii_char unchanged).
- **`gpu_collector.sv` rewritten**: instead of one AXI write per column, it now loops
  `NUM_ROWS` (45) single-byte writes per column — blank ceiling above `wall_top`, the wall's
  shade glyph across the band, blank floor below. `active_col/active_char/active_wtop/
  active_wheight` hold the in-service column's data steady across the whole loop, decoupled
  from the `pend_*` per-core latches so a later pend entry for the same core can't corrupt it
  mid-drain.

### Bug 1 — collector backpressure, take 1 (insufficient)

Draining one column now takes ~45 AXI writes instead of one (~180 cycles vs ~4), but
`gpu_dispatcher.sv` only waited for `core_done`, not for the collector to actually consume the
result, before firing the next round. A core could — and reproducibly did — finish its *next*
column before the collector had even picked up its *previous* one. The per-core latch guard
(`if (core_done[i] && !pend_valid[i])`) then silently dropped the new result, since
`pend_valid[i]` was still 1 from the still-queued old one. Result: 17/80 columns went
completely blank (all rows stayed at reset-value space) with no error, no hang, no lint warning
— just wrong-looking output.

First fix attempt: added a `queue_empty` output from the collector (`~|pend_valid`) and gated
`gpu_dispatcher`'s round-advance on it. Reduced but didn't eliminate the failures (17 → 14
blank columns) — `pend_valid` clears the instant an entry is *accepted* into service
(`W_IDLE`→`W_ADDR`), not when its 45-row drain actually finishes, so `queue_empty` could read
true while a previous entry was still mid-drain.

### Bug 2 — collector backpressure, take 2 (found via cycle-level tracing)

Added a temporary instrumented copy of `tb_soc_top.cpp` printing `pend_valid`, `w_state`, and
`round` on every change (not kept in the tree — throwaway debug harness). Traced one
specific always-blank column (13) back to its source: `dda_core` computed it correctly
(`wtop=16 wheight=13`, checked via `--public-flat-rw`), but its `done` pulse arrived while
`pend_valid[1]` was still occupied by an *earlier* round's undrained result for that same core.

Root cause was a one-cycle staleness race, not a logic error in the guard itself: the
dispatcher's `WAIT` state checked `collector_ready` in the **same cycle** it captured this
round's own last done pulses into the collector's queue. `collector_ready` at that cycle
reflects the state from *before* that same edge's capture — so if the collector happened to be
idle a moment earlier, the round was allowed to launch even though the capture happening on
that very edge was about to make the collector busy again. `w_state==W_IDLE` (added for take 1)
didn't help because IDLE-with-a-fresh-pend-entry looks identical, for one cycle, to
genuinely-idle.

**Fix:** split `gpu_dispatcher`'s `WAIT` into `WAIT` (accumulate `done_accum`) and a new
`DRAIN_WAIT` state, entered only *after* `done_accum` reaches all-ones. `collector_ready` is
now checked in `DRAIN_WAIT`, on a cycle strictly later than the one that captured this round's
pulses — by then `pend_valid`/`w_state` correctly reflect the just-filled queue, so
`collector_ready` reads false until the real drain completes. Verified: 80/80 columns correct
after this fix (was 63/80, then 66/80 after take 1).

### Verification

`software/ref/raycaster_ref.py` was **not** used to regenerate the golden reference — its own
map differs from the real one (`gen_map_hex.py`'s `MAP_STR`, also embedded in
`tb_soc_top.cpp`), a pre-existing drift this session didn't fix (out of scope; noted for
later). Instead:
- **Character selection** (`dist_to_ascii`) is completely unchanged logic — still bit-exact
  matchable against the existing golden 80-character string. Extraction changed: scan each
  column's 45 rows for the (uniform) non-space band instead of assuming row 0.
- **Wall height** has no practical bit-exact Python reference (would mean porting the LUT
  generation and the 34-cycle fixed-point divider into Python for one continuous metric).
  Instead, `sim/tb_soc/tb_soc_top.cpp` checks each column's height against a `floor(45/d)`
  range per `dist_to_ascii` bucket, widened a few rows to absorb Q16.16/LUT quantization noise.
  Both checks: 80/80 PASS.
- `sim/unit/dda_core/tb_dda_core.cpp` (single-core, no dispatcher/collector involved) still
  passes 80/80 unmodified — confirms the character path is correct in isolation, which is what
  let debugging focus on the multi-core collector/dispatcher interaction instead of `dda_core`
  itself.

### Timing impact — WNS dropped to +0.020 ns (was +0.420 ns)

Ran full `impl_nexys_a7.tcl` (place + route + bitstream, not just synthesis) after this change:
still closes at 65 MHz, 0 failing endpoints, bitstream generated successfully. But the margin
is now razor-thin (`synth/out/timing_summary_impl.rpt`), down from the already-tight +0.420 ns
baseline. Resource cost was cheap (LUTs 5500→6770 ~9%→10.7%, FFs 2200→3323 ~2%→2.6%, DSP48
56→60 ~23%→25%, BRAM 66→69.5 tiles ~49%→51.5%, IO 17→22 for the buttons) — the real risk here
is timing, not area. Follow-up before touching this path again: identify the actual critical
path with `report_timing -max_paths 10` on the impl run (not yet done this session) — likely
candidates are the new `row_char` combinational mux in `gpu_collector.sv` or increased fanout
from the per-core `wall_top`/`wall_height` buses, not `fpdiv` itself (multi-cycle, registered
in/out). If it regresses further, dropping `sys_clk` a few hundred kHz is the cheap fix; the
harder fix is pipelining the offending combinational path.

---

## `dda_core.sv` direction pipeline split (2026-07-03, follow-up)

The "likely candidates" guess above (`gpu_collector` row_char mux / `wall_top`/`wall_height`
fanout) was **wrong**. Reading `synth/out/timing_summary_impl.rpt`'s actual worst path (not
just its WNS number) found the real critical path entirely inside `dda_core.sv`, in the
per-column ray-direction setup that predates the wall-height work:

```
Source:      gen_cores[2].u_core/player_idx_reg__6/C     (INIT state, registered)
Destination: gen_cores[2].u_core/ddx_reg[30]/D            (PREP state, registered)
Data path:   15.230ns, 17 logic levels (CARRY4×10, DSP48E1×1, LUT2/4/5/6)
```

`player_idx` (registered in `INIT`) feeds, all combinationally within the *same* cycle that
lands on the `PREP`-state `ddx`/`ddy` registers: a `sin_table` lookup for `player_cos`/
`player_sin` → a signed 64-bit multiply (`rdx_mul_a = player_cos * fisheye_table[col_r]`,
mapped to a DSP48E1) → a subtract (`rdx_comb`) → `PREP`'s own conditional two's-complement
negate + magnitude compare + table-select mux that produces `ddx`. None of that chain is new
this session — it's been there since the original DDA implementation — but it was apparently
always the tightest path in the design; the wall-height rendering work just ate enough of the
remaining slack (+0.420ns → +0.020ns) to make it visible as the binding constraint.

**Fix:** added a new FSM state `DIR_WAIT` between `INIT` and `PREP`. `DIR_WAIT` does nothing but
register `rdx_comb`/`rdy_comb` into new `rdx_lat`/`rdy_lat` signals; `PREP` then reads
`rdx_lat`/`rdy_lat` instead of the raw combinational `rdx_comb`/`rdy_comb` for the abs/compare/
mux that produces `ddx`, `ddy`, `step_x_neg`, `step_y_neg`. This splits the sin-lookup+multiply
+subtract off from the abs+compare+mux, putting a register boundary between them instead of
letting both settle in one clock period. Cost: one extra cycle per column in the one-time
per-column setup (not the ~90-cycle MARCH loop), invisible at the frame level.

**Verification:**
- Verilator lint (`--lint-only -Wall`): zero warnings referencing `dda_core.sv`/`DIR_WAIT`/
  `rdx_lat`/`rdy_lat` — no latch inference, no combinational loop, enum still fits its 3-bit
  encoding (8 states).
- `sim/tb_soc` regression: 80/80 wall characters + 80/80 wall heights still PASS; frame cycle
  count went from ~16170 to 16190 (+20, consistent with the extra `DIR_WAIT` cycle × however
  many of the 80 columns actually transit it across 4 cores) — purely a latency change, no
  functional difference.
- Full `impl_nexys_a7.tcl` re-run: **WNS improved +0.020ns → +0.180ns** (9x), 0 failing
  endpoints out of 9828, 0 errors/critical warnings, bitstream regenerated
  (`synth/out/ascii_doom_soc.bit`). Utilization essentially unchanged (LUTs 6770→6745, FFs
  3323→3491, BRAM/DSP48 identical) — the FF increase is a bit more than the ~64 bits of new
  state (2×32-bit `rdx_lat`/`rdy_lat`), likely additional retiming around the new state.

**New critical path** (still worth knowing before the next GPU change): now in the per-core
`fpdiv` (`u_height_div`) added for wall-height rendering — `ddx_reg[2]/C` →
`u_height_div/result_reg[23]/CE`, 14.873ns, 11 logic levels through `fish_mul`'s DSP48E1 and
the divider's control logic. This matches what `docs/HANDOFF.md`'s Known Issues section already
predicted (`fpdiv`/`fpmul` pipelining as the next timing lever) — not yet addressed, margin is
healthy again (+0.180ns) so no immediate action needed.

**Not yet done:** bitstream has not been reflashed to the physical Nexys A7 board — this fix,
like everything from movement-input onward, is simulation + place-and-route verified only.
