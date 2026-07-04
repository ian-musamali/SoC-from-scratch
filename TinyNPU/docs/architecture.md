# TinyNPU Architecture

TinyNPU classifies 32×32 RGB images into 4 classes (cat, truck, plane, ship)
using integer-only arithmetic. This document covers the whole datapath:
the parameter contract, the 64-lane MAC array (Phase 3), the convolution
engine (Phase 4), the NPU core (Phase 5), and the FPGA wrapper (Phase 7).
Each layer reuses the interfaces below it unmodified.

## Parameters (`rtl/tinynpu_pkg.sv`)

| Parameter      | Default | Meaning                                  |
|----------------|---------|------------------------------------------|
| `IMG_WIDTH`    | 32      | input image width                        |
| `IMG_HEIGHT`   | 32      | input image height                       |
| `NUM_CHANNELS` | 3       | RGB                                      |
| `NUM_LANES`    | 64      | parallel MAC lanes per transaction       |
| `DATA_W`       | 8       | signed activation/weight width (int8)    |
| `ACC_W`        | 32      | signed accumulator width (int32)         |
| `NUM_CLASSES`  | 4       | classifier outputs                       |

## MAC array (`rtl/mac_array.sv`)

One transaction = one 64-element signed dot product chained onto a running
accumulator:

```
            +--------------------------------------------------+
 in_valid ->|  64x  (act_i * wgt_i)   int8 x int8 -> int16      |-> out_valid
 in_ready <-|        \ adder tree /   exact, 22-bit             |<- out_ready
      act ->|             +  acc_in   exact, 33-bit             |
      wgt ->|         saturate to ACC_W  -> acc_out, sat_flag   |
   acc_in ->|                                                   |
            +--------------------------------------------------+
```

Math (must match `model/golden_mac_model.py` bit-for-bit):

1. `dot  = Σ act[i]·wgt[i]` — products are exact int16; the sum is computed in
   `2*DATA_W + clog2(NUM_LANES)` = 22 bits, wide enough that it never wraps.
2. `full = dot + acc_in` — computed in `max(22, ACC_W) + 1` = 33 signed bits,
   wide enough that it never wraps.
3. `acc_out = clamp(full, -2^(ACC_W-1), 2^(ACC_W-1)-1)`; `sat_flag = 1` iff
   clamping occurred.

With the default parameters the dot product alone (|dot| ≤ 2^20) cannot
saturate int32; saturation is reached via `acc_in` near the rails, which is
exactly how chained multi-pass accumulation can overflow in a real layer.

### Handshake protocol

Valid/ready on both sides, 4-stage pipeline (DSP products → half the adder
tree → other half → accumulate + saturate), latency 4, full throughput:

- `in_ready = !out_valid || out_ready` (the whole pipeline advances whenever
  the output register is empty or being drained the same cycle; otherwise
  everything in flight stalls together).
- Results appear strictly in acceptance order; `out_valid` holds until
  `out_ready` and data is stable while `out_valid` is high.
- `in_valid` must not depend combinationally on `in_ready` (standard rule).
- Async active-low reset `rst_n`: all in-flight transactions are discarded.
- Consumers must be latency-agnostic (wait on `out_valid`, never count
  cycles) — the conv engine and both UVM scoreboards already are.

The dot product is summed in a balanced heap-indexed adder tree split across
two pipeline stages; every partial sum is exact in the 22-bit domain, so the
result is bit-identical to a linear sum. (A fully combinational 64-lane MAC
— serial chain, balanced tree, or DSP-based — misses even 50 MHz on Artix-7
by tens of ns; the pipeline is what closes timing.)

### Lane packing

`act`/`wgt` are flat packed buses; lane *i* is `bus[i*DATA_W +: DATA_W]`,
signed two's complement. Lane 0 sits in the LSBs. Vector files list lane 0
first; the UVM driver packs field *i* into lane *i*.

## Convolution engine (`rtl/conv_engine.sv`, Phase 4)

A window-walker that owns no math: it gathers 3×3×in_ch tap windows and
masters the MAC array interface. One `start` = one output channel.

- Config (sampled on start): image dims (≤32), in_ch (≤8), stride 1/2,
  zero-pad 0/1, requantization shift, ifm/ofm/wgt base addresses, `acc_init`
  (bias hook, feeds the first MAC pass).
- Tap order `t = (ch*3 + ky)*3 + kx`; tap `t` → MAC pass `t/64`, lane `t%64`;
  passes chained through `acc_in` (in_ch=8 → 72 taps → 2 passes). Padding taps
  contribute zero lanes.
- Each pixel's final accumulator is requantized: arithmetic `>>> out_shift`,
  then saturate to int8 — needed so layer N+1 can consume layer N's output.
  `sat_seen` is sticky per start (MAC saturation OR int8 clamp).
- Memory ports are simple 1-cycle-latency read ports (ifm, weights) plus an
  int8 write port (ofm). Memories themselves are external (Phase 7).

## NPU core (`rtl/npu_core.sv`, Phase 5)

Control FSM sequencing a packed `layer_desc_t` table (≤6 layers): for each
layer, for each output channel, it derives `wgt_base + oc*taps` and
`ofm_base + oc*out_w*out_h`, starts the conv engine, and waits for done. The
conv engine's MAC port is wired directly to the Phase-3 `mac_array` inside.
Feature maps live in one unified int8 buffer (1R + 1W port, 16K deep) —
descriptors ping-pong `ifm_base`/`ofm_base` between regions 0 and 8192. A
CIFAR-shaped program (five stride-2 layers, 32×32×3 → 1×1×4) fits this
architecture and is exercised in the Phase-6 regression with random weights.

## FPGA wrapper (`rtl/tinynpu_top.sv` + `fpga/`, Phase 7)

Board-agnostic top that runs one classification of a built-in demo image per
debounced button press:

```
button ─▶ T_IDLE ─▶ T_LOAD ─▶ T_START ─▶ T_RUN ─▶ T_READ ─▶ T_SHOW ─▶ idle
                copy img_rom   pulse      npu_core   signed     latch class
                into fm buffer npu start  runs the   argmax of  to display,
                (1 B/cycle)               program    4 results  one-hot LEDs
```

- **Memories**: `byte_rom` (image ROM 3 KiB, weight ROM ≤4 KiB, `$readmemh`
  init) and `fm_buffer` (16 KiB, 1R+1W) — BRAM-inferable implementations of
  the exact read-first 1-cycle contract modeled by `uvm/common/mem_if.sv`,
  so the verified RTL sees identical memory behavior on the board.
- **Layer program**: `fpga/mem/layer_prog.svh`, generated by
  `model/gen_fpga_mem.py` from the golden model (the CIFAR-shaped 5-layer
  program, 32×32×3 → 1×1×4). Same generator emits the ROM images and the
  expected class, so RTL and expectation cannot drift.
- **Port muxing**: the loader owns the fm write port in T_LOAD, `npu_core`
  owns all memory ports in T_RUN, the argmax readout owns the fm read port
  in T_READ.
- **Display stub** (`display_stub.sv`): latches the one-hot class onto 4
  LEDs plus busy/saturation indicators — the seam for a real display later.
- **Board isolation**: every board-specific decision (pins, polarity, LED
  mapping, clocking) lives in `fpga/arty_a7/` (`arty_a7_top.sv` shim +
  `arty_a7.xdc` + `build.tcl` for a batch Vivado bitstream build, part
  xc7a35ticsg324-1L). The shim's MMCM runs the core at 50 MHz, where the
  pipelined MAC datapath closes timing on the -1L speed grade. Porting to another board means one new shim + xdc, nothing
  else.

## Forward-compatibility hooks

- `acc_in` chaining is what makes >64-tap layers work (72-tap layers run as
  two chained passes today); the 3072-input classifier case follows the same
  pattern.
- The demo weights are seeded-random (architecture bring-up); trained weights
  drop in by regenerating `fpga/mem/` with `gen_fpga_mem.py` — no RTL change.
- All sizing flows from `tinynpu_pkg`; later work adds parameters, never
  repurposes these.
