# ASCII Doom SoC — Session Handoff
_Date: 2026-06-13_

## What was done this session

### Steps completed
| Step | Work |
|------|------|
| 12 (sim debug) | Fixed `dda_core.sv` stale-BRAM bug; simulation now 80/80 vs Python reference |
| 12 (cleanup) | Removed all debug output from `sim/tb_soc/tb_soc_top.cpp`; PASS still holds |
| 13 (constraints) | `constraints/nexys_a7.xdc` — all pins for XC7A100T-CSG324 |
| 13 (FPGA wrapper) | `rtl/fpga_top.sv` — MMCM generates 65 MHz sys_clk + 25 MHz pix_clk |
| 13 (synthesis) | Vivado 2025.2 synthesis: clean, no errors, no CRITICAL WARNINGs |
| 13 (implementation) | **WNS = +0.420 ns @ 65 MHz**, 0 failing endpoints, timing closed |
| 13 (board) | Bitstream programmed to Nexys A7 via JTAG |
| firmware | Real PicoRV32 fetched, firmware built (601 bytes), pre-loaded into BRAM |

### RTL bugs fixed
1. **`dda_core.sv`** — `map_read_req = (state == MARCH)` caused stale BRAM data between
   rounds. Fix: `map_read_req = (state == MAP_WAIT) | (state == MARCH)`.
2. **`soc_top.sv` main BRAM** — async reset in data block blocked Xilinx BRAM inference
   (256 KB = fatal). Fix: split into control-with-reset + data-no-reset always_ff blocks.
3. **`soc_top.sv` map_bram** — 2D array inferred as "3D-RAM" (131K FFs). Fix: per-core
   1D arrays in generate block.
4. **`char_framebuffer.sv`** — async reset in data block + multi-address byte-lane writes
   blocked BRAM inference (32K FFs). Fix: separate blocks, single-byte write at `aw_addr_r`.
5. **`char_framebuffer.sv` CDC** — Port B (VGA read) was on sys_clk; `vga_top` drives
   `vga_addr` on pix_clk → 11 CDC timing violations. Fix: added `pix_clk` port, Port B now
   a true dual-port BRAM with independent clock.
6. **`gpu_mmio.sv`** — `reg_ctrl[1]` driven by two always_ff blocks (CRITICAL WARNING).
   Fix: inject `frame_done` live into the AXI read mux; remove the hardware-update path.
7. **`picorv32_axi.sv` stub** — missing `mem_axi_awprot`, `mem_axi_arprot` and parameters.
   Fix: stub updated to match real `picorv32_axi` interface.

### New files
```
rtl/fpga_top.sv                        MMCM + soc_top wrapper for Nexys A7
rtl/core/picorv32.v                    Real PicoRV32 (fetched from YosysHQ/picorv32)
constraints/nexys_a7.xdc               Pin + clock constraints
synth/synth_nexys_a7.tcl               Synthesis-only TCL
synth/impl_nexys_a7.tcl                Synth + impl + bitstream TCL
synth/program_nexys_a7.tcl             JTAG programming TCL
synth/out/ascii_doom_soc.bit           Programmed bitstream (65 MHz)
software/firmware/startup.S            PicoRV32 reset handler
software/firmware/main.c               Game loop (rotate angle, trigger GPU, UART heartbeat)
software/firmware/linker.ld            BRAM layout (text+data+bss, stack at top)
software/firmware/Makefile             Build: make all → firmware.hex + map.hex
software/firmware/elf2hex.py           ELF binary → 32-bit $readmemh hex
software/firmware/gen_map_hex.py       MAP_STR → 8-bit $readmemh hex
software/firmware/firmware.hex         Pre-built firmware (65536 words, ~601 bytes used)
software/firmware/map.hex              Pre-built map BRAM init (4096 bytes)
docs/decisions/soc_top.md             Architecture decisions + map_read_req fix writeup
```

---

## Current hardware state

**Board:** Nexys A7 programmed with `synth/out/ascii_doom_soc.bit`.

**What should be running:**
- PicoRV32 @ 65 MHz boots from address 0, sets player at (2.5, 2.5), triggers GPU frames
  in a loop, rotating the angle by ~1 degree per frame.
- 4-core DDA GPU renders 80 columns/frame; char_framebuffer updated each frame.
- VGA 640×480 @ 60 Hz scans character grid via font ROM.
- UART prints `frame 0xNNN  cycles=0xNNN` every 64 frames.

**UART:** `/dev/ttyUSB0`, 115200 8N1.  
`screen` not installed; use `picocom /dev/ttyUSB0 -b 115200` or `minicom`.

---

## Resource utilization (post-route, 65 MHz)

| Resource | Used | Available | % |
|----------|------|-----------|---|
| LUTs | ~5 500 | 63 400 | ~9% |
| FFs | ~2 200 | 126 800 | ~2% |
| BRAM tiles | ~66 | 135 | ~49% |
| DSP48 | ~56 | 240 | ~23% |
| MMCM | 1 | 6 | 17% |
| IO | 17 | 210 | 8% |

> The 64 RAMB36 tiles are consumed by the 256 KB instruction/data BRAM.
> Reduce `BRAM_WORDS` from 65536 to 16384 (64 KB) to free ~48 tiles if needed.

---

## Known issues / pending work

### Timing (100 MHz target not met)
The DDA fixed-point arithmetic (fpdiv/fpmul) has a ~14.5 ns critical path.  
At 65 MHz (15.4 ns period) timing closes; 100 MHz requires pipelining the multipliers.  
The fix: add one registered pipeline stage inside `rtl/lib/fpmul.sv` and `rtl/lib/fpdiv.sv`
and update DDA state-machine wait states accordingly.

### Synthesis warning (harmless)
`synth_nexys_a7.tcl` still reads `picorv32_axi.sv` (stub) then overwrites with `picorv32.v`
→ "overwriting previous definition" warning.  
`impl_nexys_a7.tcl` is already fixed (reads `uart_lite.sv` only, skips the stub).  
Fix `synth_nexys_a7.tcl` the same way when you re-run synthesis.

### UART bitstream output unconfirmed
UART RX/TX pins and `uart_lite.sv` logic haven't been end-to-end verified on hardware yet.
Check with `picocom /dev/ttyUSB0 -b 115200` after reprogramming.

---

## Remaining project steps

| Step | Description |
|------|-------------|
| 14 | RTL polish — run Verible lint on all modules, fix warnings |
| 15 | OpenLane GDS — GPU block only (`gpu_top.sv` + sub-modules), 20 MHz target |
| 16 | Portfolio package — update README, add demo GIF/screenshot, timing/area tables |

---

## Quick rebuild reference

```bash
# Firmware (after editing main.c)
cd software/firmware && make all

# Full FPGA flow from project root
vivado -mode batch -source synth/impl_nexys_a7.tcl \
    -log synth/out/impl.log -journal synth/out/impl.jou

# Program board (hw_server must be running)
/tools/2025.2/Vivado/bin/hw_server &
vivado -mode batch -source synth/program_nexys_a7.tcl -nolog -nojournal

# Simulation regression
cd sim/tb_soc/obj_dir && ./Vsoc_top
# Expected: Frame completed in 828 cycles / PASS: soc_top 80/80
```

## Build from scratch (after RTL changes)
```bash
cd /home/ian/SoC-from-scratch/ascii_doom_soc

# 1. Rebuild firmware if main.c changed
make -C software/firmware all

# 2. Verilator sim (SIMULATION=1, uses stub CPU)
rm -rf sim/tb_soc/obj_dir && mkdir -p sim/tb_soc/obj_dir
verilator --cc -Wall --Wno-fatal --public-flat-rw --top-module soc_top -GSIMULATION=1 \
    -Mdir sim/tb_soc/obj_dir \
    rtl/lib/fpdiv.sv rtl/lib/fpmul.sv rtl/lib/font_rom.sv \
    rtl/bus/axi4lite_fabric.sv \
    rtl/vga/vga_sync.sv rtl/vga/char_framebuffer.sv rtl/vga/vga_top.sv \
    rtl/gpu/dda_core.sv rtl/gpu/gpu_dispatcher.sv rtl/gpu/gpu_collector.sv \
    rtl/gpu/gpu_mmio.sv rtl/gpu/gpu_top.sv \
    rtl/dma/axi_dma.sv rtl/core/uart_lite.sv rtl/core/picorv32_axi.sv \
    rtl/soc_top.sv
cd sim/tb_soc/obj_dir
make -f Vsoc_top.mk -s
g++ -std=c++17 -O2 -I . -I /usr/share/verilator/include -I /usr/share/verilator/include/vltstd \
    -c -o tb_soc_top.o ../tb_soc_top.cpp
g++ -std=c++17 -O2 -o Vsoc_top tb_soc_top.o verilated.o verilated_dpi.o verilated_threads.o \
    Vsoc_top__ALL.a -lpthread
./Vsoc_top   # must print PASS: soc_top 80/80

# 3. Vivado impl + program
cd /home/ian/SoC-from-scratch/ascii_doom_soc
vivado -mode batch -source synth/impl_nexys_a7.tcl -log synth/out/impl.log -journal synth/out/impl.jou
/tools/2025.2/Vivado/bin/hw_server &
vivado -mode batch -source synth/program_nexys_a7.tcl -nolog -nojournal
```
