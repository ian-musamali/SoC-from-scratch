# ASCII Doom SoC v2 — Project Identity

Board:         Nexys A7 — Artix-7 XC7A100T, 100 MHz onboard oscillator
RISC-V core:   PicoRV32 with AXI4-Lite wrapper (external source, do not modify)
Bus:           AXI4-Lite — 2 masters (CPU, DMA), 4 slaves: BRAM, UART, VGA framebuffer, GPU MMIO
GPU:           Parallel DDA raycaster — 4 cores default, parameterized to 8
               Static dispatch: column N → core (N mod NUM_CORES)
               Dispatcher → [DDA core × NUM_CORES] → collector → framebuffer write
Display:       VGA 640×480 @ 60 Hz, 25.175 MHz pixel clock via MMCM
               ASCII renderer: 8×8 font ROM, 80×45 character grid
               80×45 grid uses 640×360 of 480 active lines; 120 lines blank at bottom
Fixed-point:   Q16.16 throughout all ray math
DMA:           Custom AXI DMA controller — autonomous GPU data movement, CPU not in loop
Toolchain:     Vivado 2024.x, Verilator, cocotb, riscv64-unknown-elf-gcc
Physical:      OpenLane2 → Yosys → OpenROAD → Magic (DRC) → Netgen (LVS) → GDS
               Target: GPU block only (not full SoC), 20 MHz conservative target
RTL language:  SystemVerilog (.sv) everywhere. No .v except PicoRV32 source.
Style:         snake_case signals/modules, SCREAMING_SNAKE_CASE parameters
               No #delay in RTL. No initial blocks in RTL. All registers fully reset.

## AXI Address Map

| Slave           | Base       | Size   |
|-----------------|------------|--------|
| BRAM (instr+data)| 0x00000000 | 256 KB |
| UART (debug)    | 0x10000000 | 4 KB   |
| VGA framebuffer | 0x20000000 | 4 KB   |
| GPU MMIO        | 0x30000000 | 32 B   |

## GPU MMIO Registers

| Register   | Offset | Description                                  |
|------------|--------|----------------------------------------------|
| GPU_CTRL   | 0x00   | bit0=frame_start(w), bit1=frame_done(r)      |
| GPU_STATUS | 0x04   | bits[3:0]=per-core busy flags                |
| PLAYER_X   | 0x08   | Q16.16 player X                              |
| PLAYER_Y   | 0x0C   | Q16.16 player Y                              |
| PLAYER_ANG | 0x10   | Q16.16 player angle (0=east, CCW positive)   |
| GPU_CYCLES | 0x14   | cycle count for last frame                   |
| CORE_UTIL  | 0x18   | per-core utilization [3:0]                   |
| DMA_CTRL   | 0x1C   | bit0=start, bit1=done                        |
| DMA_SRC    | 0x20   | source address                               |
| DMA_DST    | 0x24   | destination address                          |
| DMA_LEN    | 0x28   | transfer length in bytes                     |
