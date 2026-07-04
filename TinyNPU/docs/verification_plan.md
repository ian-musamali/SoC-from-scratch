# TinyNPU Verification Plan

Covers all module-level and system-level environments: the MAC array
(Phase 3), the isolated conv engine (Phase 4), the full-system NPU core
(Phase 6), and the FPGA wrapper smoke test (Phase 7).

## Strategy

All expected results come from the Phase 2 Python golden model
(`model/golden_mac_model.py`), emitted into `vectors/*.txt` by
`model/gen_vectors.py`. **The UVM scoreboard reads expected values from those
files; it never re-derives the math in SystemVerilog.** Data-level randomness
lives in the (seeded) Python generator; protocol-level randomness (idle gaps,
output backpressure) is SystemVerilog constrained-random in the sequences and
driver so handshake corner cases are exercised independently of data.

## Environment

```
tb_top ── mac_if ── DUT (mac_array)
   │
 mac_env
   ├── mac_agent
   │     ├── mac_sequencer ── sequences (read vectors/*.txt)
   │     ├── mac_driver    (drives in_valid/act/wgt/acc_in, random out_ready)
   │     └── mac_monitor   (captures accepted inputs, completed outputs, resets)
   ├── mac_scoreboard      (pairs file expectations with DUT outputs)
   └── mac_coverage        (functional coverage subscriber)
```

Scoreboard pairing rule: each *accepted input* (in_valid && in_ready) consumes
the next expected line from the vector file and pushes it onto a pending
queue; each *completed output* (out_valid && out_ready) pops and compares
`acc_out` and `sat_flag`. A reset flushes the pending queue, so transactions
killed in flight are not falsely flagged.

## Vector file format

One transaction per line, 131 whitespace-separated hex fields
(`#` lines are comments): 64× act (2 hex), 64× wgt (2 hex), acc_in (8 hex),
expected acc_out (8 hex), expected sat_flag (1 digit). Two's complement.

## Tests

| Test                    | Vectors        | Purpose                                  |
|-------------------------|----------------|-------------------------------------------|
| `mac_unit_smoke_test`   | `smoke.txt`    | 12 directed known-answer cases            |
| `mac_unit_random_test`  | `random.txt`   | 500 constrained-random + random handshake |
| `mac_unit_overflow_test`| `overflow.txt` | saturation both rails + exact boundaries  |
| `mac_unit_reset_test`   | `reset.txt`    | reset mid-stream, recovery, no false fails|

## Functional coverage (`mac_coverage`)

- Activation/weight value classes per transaction: min, negative, zero,
  positive, max present in the lane vector.
- `acc_in` bins: min rail, large negative, zero, moderate, large positive,
  max rail.
- `sat_flag` observed both 0 and 1; cross of saturation with acc_in sign.
- Reset asserted while a transaction is pending (reset-during-active).
- Handshake: input stall (valid && !ready), output backpressure
  (out_valid && !out_ready) each covered.

## Pass criteria

A test passes iff UVM_ERROR == 0, UVM_FATAL == 0, and the scoreboard compared
at least one transaction (an env that silently checks nothing must fail).
The base test prints `TINYNPU TEST PASSED` / `TINYNPU TEST FAILED`; the
Makefile `regress` target greps for it and prints the summary table.

## Conv engine environment (Phase 4, isolated)

DUT = `conv_engine` alone. Because its MAC request stream is fully
deterministic given config + memories, the golden model emits the exact
expected request/response trace per case; a **reactive MAC responder** checks
every request (act/wgt lanes, acc_in — this is where padding/stride/window
bugs surface) against `mac_trace.txt` and replies with the golden response.
The scoreboard independently checks the int8 output writes against
`ofm_trace.txt` in order. Behavioral memories (`uvm/common/mem_if.sv`) are
loaded per case from `.memh` files. Cases live in `vectors/conv/<case>/`,
selected by `+CONV_DIR` + `+CONV_MANIFEST`.

Tests: `conv_unit_smoke_test` (directed identity kernel),
`conv_unit_stride_pad_test` (all stride×pad combos incl. 1×1 image),
`conv_unit_multichannel_test` (3ch, 8ch→2-pass chaining, near-rail
saturation), `conv_unit_random_test` (8 random cases). Coverage: stride×pad
cross, in_ch bins (incl. multi-pass), shift bins, acc_init sign, sat_seen,
MAC backpressure.

## Full-system environment (Phase 6)

DUT = `npu_core` (conv engine + MAC array + sequencing FSM). Per case
(`vectors/npu/<case>/`, `+NPU_DIR`/`+NPU_MANIFEST`): descriptors driven from
`descs.txt`, memories loaded from `.memh`, then two independent checks —
every fm write compared in order against the golden `write_trace.txt`, and
after done a full 16K-entry compare of the fm buffer against
`fm_final.memh` (catches stray writes anywhere). Tests: `npu_smoke_test`,
`npu_multilayer_test` (3-layer ping-pong + CIFAR-shaped 5-layer 32×32×3→1×1×4
program), `npu_random_test` (random chained programs). Coverage: layer count,
per-layer stride×pad/in_ch/out_ch/shift, sat_seen.

## Wrapper smoke test (Phase 7)

`top_smoke_test` (plain SV, `fpga/tb/tinynpu_top_tb.sv`): presses the
classify button on `tinynpu_top` and checks the one-hot class LEDs against
the golden expected class (`+EXP_CLASS`, line 1 of `fpga/mem/expected.txt` —
produced by the same golden-model run that generated the ROM images). This
exercises the debouncer, the image-load FSM, the memory port muxing, a full
5-layer inference through the BRAM-contract memories, and the argmax readout.
It prints the same `TINYNPU TEST PASSED` banner as the UVM tests so
`make regress` treats it uniformly. Board synthesis is validated separately
by `fpga/arty_a7/build.tcl` (Vivado, bitstream + timing/utilization reports).

## Regression

`sim/Makefile` (VCS): `make regress` runs all 12 tests (4 MAC + 4 conv +
3 NPU + 1 top smoke) and prints the pass/fail table; per-suite targets
`regress_mac` / `regress_conv` / `regress_npu` / `regress_top`; `make
vectors` regenerates every golden artifact (vector suites + FPGA demo
memories) from the seeded Python models.

## Future work

Trained weights (content only — regenerate `fpga/mem/`), a real display
controller behind `display_stub`, and deepening the MAC pipeline if a future
board target needs the core above 50 MHz (the 4-stage pipeline closes 50 MHz
on the Arty A7's -1L speed grade; every consumer and scoreboard is already
latency-agnostic, so adding stages is a local change).
