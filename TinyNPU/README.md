# TinyNPU

A self-contained FPGA neural processing unit that classifies 32×32 RGB images
(cat / truck / plane / ship) using a 64-lane integer MAC array.

**Status: all 8 phases complete.** Architecture contract, bit-exact Python
golden models, full RTL datapath (MAC array → convolution engine → NPU core →
FPGA wrapper), three UVM 1.2 environments plus a wrapper smoke test
(12 tests total), and an Arty A7-35T board build. The demo bitstream runs a
CIFAR-shaped 5-layer network with seeded-random weights; dropping in trained
weights is a content change only (`model/gen_fpga_mem.py`).

## Layout

```
rtl/       tinynpu_pkg.sv, mac_array.sv, conv_engine.sv, npu_core.sv,
           byte_rom.sv, fm_buffer.sv, btn_debounce.sv, display_stub.sv,
           tinynpu_top.sv
uvm/       Phase-3 MAC env (tb/, agents/, env/, seq/, tests/),
           conv/ (isolated conv env), npu/ (full-system env),
           common/ (behavioral memory interfaces)
model/     golden_mac_model.py, golden_conv_model.py (bit-exact references),
           gen_vectors.py, gen_conv_vectors.py, gen_fpga_mem.py
vectors/   generated MAC vectors + conv/ and npu/ case directories
fpga/      mem/ (generated ROM images + layer program), tb/ (wrapper smoke),
           arty_a7/ (board shim, pins, Vivado build script)
sim/       VCS Makefile + filelists (mac_tb.f, conv_tb.f, npu_tb.f, top_tb.f)
docs/      architecture.md, verification_plan.md
```

## Simulation (requires Synopsys VCS with UVM 1.2)

```sh
cd sim
make vectors          # regenerate all golden vectors + FPGA demo memories
make mac_unit_smoke_test              # run any single test by name
make regress_mac | regress_conv | regress_npu | regress_top
make regress          # all 12 tests + pass/fail summary
```

| Suite | Tests |
|-------|-------|
| MAC array (Phase 3) | `mac_unit_smoke_test`, `mac_unit_random_test`, `mac_unit_overflow_test`, `mac_unit_reset_test` |
| Conv engine (Phase 4) | `conv_unit_smoke_test`, `conv_unit_stride_pad_test`, `conv_unit_multichannel_test`, `conv_unit_random_test` |
| Full system (Phase 6) | `npu_smoke_test`, `npu_multilayer_test`, `npu_random_test` |
| FPGA wrapper (Phase 7) | `top_smoke_test` |

All checks compare DUT outputs against files produced by the Python golden
models — the math is never re-derived in SystemVerilog. See
`docs/verification_plan.md`.

## FPGA build (Arty A7-35T, Vivado)

```sh
cd TinyNPU
vivado -mode batch -source fpga/arty_a7/build.tcl
# bitstream + reports in fpga/arty_a7/build/
```

On the board: **BTN0** = reset, **BTN1** = classify. LD4–LD7 show the class
one-hot; LD0 green = busy, LD0 red = saturation occurred. The core runs at
50 MHz (MMCM in the shim; the MAC's 4-stage pipelined adder tree closes
timing there on the -1L speed grade). Porting to another board = one new shim + xdc under
`fpga/<board>/`; nothing else is board-specific.

## Golden models

```sh
cd model
python3 golden_mac_model.py     # self-tests
python3 golden_conv_model.py
python3 gen_vectors.py --outdir ../vectors --seed 1
python3 gen_conv_vectors.py --outdir ../vectors --seed 1
python3 gen_fpga_mem.py --outdir ../fpga/mem --seed 7
```
