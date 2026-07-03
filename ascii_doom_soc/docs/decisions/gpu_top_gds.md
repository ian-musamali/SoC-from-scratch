# Step 15 — GPU Block OpenLane GDS Flow (2026-07-03)

Full ASIC hardening of `gpu_top.sv` (dispatcher + 4× `dda_core` + collector + MMIO)
through OpenLane2 / sky130A (`sky130_fd_sc_hd`), 20 MHz target (50 ns period).
Config: `gds/config/config.json`. Run: `gds/config/runs/RUN_2026-07-03_16-17-31/`.
Final GDSII: `gds/config/runs/RUN_2026-07-03_16-17-31/final/gds/gpu_top.gds` (263 MB).

## Environment setup

- OpenLane2 (`v2.3.10`, pip-installed) has no native Yosys/OpenROAD/Magic/Netgen —
  the local pip package expects either Nix or `--dockerized` mode. Used
  `--docker-no-tty --dockerized` (non-interactive session, no TTY available).
- The invoking user wasn't in the `docker` group; fixed with
  `sudo usermod -aG docker $USER`, picked up mid-session via `sg docker -c "..."`
  (no need to restart the session).
- PDK (sky130A + all variants) auto-installed via Volare on first run, no manual
  step needed.

## Two real Yosys-incompatibilities found in existing RTL (not new bugs — this RTL
## was already verified correct in simulation and on real Nexys A7 hardware; these
## are ASIC-synthesis-specific gaps, found by actually running Yosys, not guessed)

### 1. `return` statements inside functions

`dda_core.sv`'s `dist_to_ascii()` used `return X;` per branch of an if/else-if
chain. Verified directly against Yosys 0.46 with a 4-line repro — unconditionally
unsupported (`ERROR: syntax error, unexpected TOK_CONSTVAL`), not a flag/mode
issue. Fixed by converting to the classic `dist_to_ascii = X;` assignment style,
which every branch already had trivially available since the branches are
mutually exclusive (if/else-if/else, nothing after) — zero behavioral change,
also supported by Verilator/Vivado.

### 2. `$sin`/`$cos`/`$atan2`/`$rtoi` in an `initial` block for ROM/LUT generation

`dda_core.sv` computed 6 tables (`sin_table[256]`, `fov_table`, `fisheye_table`,
`fov_sin_table`, `ddx_table`, `ddy_table[80]` each) via real-valued math system
functions inside an `initial` block. Vivado tolerates this (constant-folds
`initial` blocks into BRAM init values); Yosys does not implement these
functions for synthesis at all (`ERROR: syntax error, unexpected TOK_AUTOMATIC`
on the `automatic real` locals, confirming the whole construct is rejected, not
just one function).

**Fix:** froze the values into `$readmemh`-loadable hex files
(`rtl/gpu/luts/*.hex`), the same idiom the project already uses for
`fonts/font8x8.hex` and `software/firmware/map.hex`. Critically, the hex files
were **not** regenerated from a fresh Python reimplementation of the math (risk
of floating-point library drift between whatever computed the original values —
Verilator's libm — and Python's libm producing subtly different rounding at the
LSB) — instead, captured bit-exact from the *existing, already-verified* RTL via
a temporary `$writememh` dump added to the same `initial` block, built+run once
with the standalone `sim/unit/dda_core` testbench, then removed. Verified
bit-identical before/after via the standalone testbench (still `PASS: RTL output
matches Python reference exactly`). A regeneration script,
`rtl/gpu/gen_dda_luts.sh`, keeps the original real-math generation logic
available (in a throwaway Verilator sim) in case `TOTAL_COLS` or the LUT
formulas ever change — confirmed to reproduce bit-identical hex output.

## Structural fix: unpacked-array module ports

Yosys 0.46 hard-rejects unpacked dimensions on ports: `ERROR: input/output/inout
ports cannot have unpacked dimensions` (confirmed with a minimal repro, both
ANSI and non-ANSI port styles — not a syntax quirk, an intentional restriction).
`gpu_dispatcher.sv`, `gpu_collector.sv`, and `gpu_top.sv`'s own top-level ports
all used `type [W-1:0] name [0:NUM_CORES-1]` for per-core buses
(`core_col`/`core_px`/`core_py`/`core_pang`/`core_char`/`core_wall_top`/
`core_wall_height`/`map_read_addr`/`map_read_data`).

**Fix:** flattened every port with a multi-bit-per-core payload to a packed bus
(`[NUM_CORES*W-1:0] name_flat`, sliced `name_flat[i*W +: W]` per core).
`map_read_req`/`core_start`/`core_done` didn't need this — they're 1 bit/core,
which is already a plain packed vector (`[NUM_CORES-1:0]`), not an unpacked
array; only the declaration style changed there, no logic. Internal per-core
arrays inside `gpu_top.sv` (used for the `dda_core` generate-loop instances)
stayed as unpacked arrays — only the module **boundaries** needed flattening,
with small pack/unpack `assign` statements added at each boundary
(`gpu_top.sv`'s `gen_cores` loop, `soc_top.sv`'s `gen_map` loop). Purely
representational — same bits, different bus shape. Touches `soc_top.sv` too
(the FPGA-targeted top level), since it instantiates the same `gpu_top.sv`.

**Verification:** full `sim/tb_soc` regression re-run after all of the above —
still 16190 cycles, 80/80 wall characters + 80/80 wall heights PASS (bit-exact/
range-exact, unchanged), zero new Verilator lint warnings anywhere near the
touched files.

## OpenLane results

| Check | Result |
|---|---|
| Yosys synthesis | Clean — ~101.6K std cells post-techmap (2158 `dfrtp`+172 `dfstp` = 2330 FFs), no `readmemh` errors, `latch.rpt` shows "No latch inferred" for every candidate signal (no unintended latches) |
| Timing (10 PVT corners, 50 ns/20 MHz) | **Worst setup slack +12.48 ns** (tt/ss/ff × 3 temp/voltage corners × min/max/nom parasitics), **worst hold slack +0.10 ns**, **0 setup violations, 0 hold violations** everywhere |
| Magic DRC | **Passed** |
| KLayout DRC | **Passed** |
| KLayout vs. Magic XOR | **Passed** (clear) |
| Netgen LVS | **Passed** |
| Die area / utilization | 2,971,350 µm² die (≈1.72 mm × 1.72 mm), 2,911,290 µm² core, 30.36% utilization at `FP_CORE_UTIL=35`/`PL_TARGET_DENSITY=0.40` |
| GDSII | Generated: `gpu_top.gds`, 263 MB |
| Total runtime | 1h18m (dockerized, single machine — synthesis alone ≈9.5 min, Magic DRC ≈15 min, KLayout DRC ≈12 min) |

### Known follow-up (not blocking — standard DFM issues, not correctness bugs)

- **Antenna violations**: 215 pin / 192 net violations reported by
  `OpenROAD.CheckAntennas` (partial charge ratios up to ~12x the 400 ratio
  limit on some `met2`/`met3` nets, e.g. `core_char`/`core_py`/`core_px`
  fanout nets). A real tapeout needs antenna diode insertion tuned for this —
  wasn't configured in this minimal config (no `GRT_REPAIR_ANTENNAS`/diode
  strategy set). `OpenLane` did run an automatic `RepairAntennas` pass
  mid-flow, but violations remained afterward. Follow-up: tune diode
  insertion strategy and re-run just the routing→signoff tail.
- **Max slew / max cap violations**: flagged (as warnings, not flow-failing
  errors) in all 9 non-default PVT corners. With +12.48 ns of setup margin at
  a very conservative 20 MHz, there's ample room to insert buffers on the
  offending high-fanout nets without touching timing closure — not
  investigated further this session (didn't identify the specific nets, only
  confirmed the corners affected).

Both are addressable in a follow-up pass without re-touching the RTL — they're
placement/routing/buffering tuning, not functional bugs. Given LVS + DRC +
timing all cleared cleanly, this milestone (Step 15: prove `gpu_top` is
synthesizable and physically implementable in a real ASIC flow) is complete;
antenna/slew/cap polish is worth doing before treating this GDS as tapeout-ready,
but doesn't block calling Step 15 done for portfolio purposes.
