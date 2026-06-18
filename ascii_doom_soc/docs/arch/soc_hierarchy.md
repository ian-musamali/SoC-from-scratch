# ASCII Doom SoC v2 — Architecture

## Module Hierarchy

```
soc_top
├── u_clk_mmcm          [Xilinx MMCM primitive]  100 MHz → 25.175 MHz pixel clock
│
├── u_picorv32_axi      [rtl/core/picorv32_axi_wrap.sv]  RISC-V CPU, AXI4-Lite master
│
├── u_axi_dma           [rtl/dma/axi_dma.sv]             DMA engine, AXI4-Lite master
│
├── u_axi_fabric        [rtl/bus/axi4lite_fabric.sv]      2M × 4S AXI4-Lite crossbar
│   ├── MASTER 0: CPU  (u_picorv32_axi)
│   ├── MASTER 1: DMA  (u_axi_dma)
│   ├── SLAVE  0: BRAM       0x00000000 – 0x0003FFFF  (256 KB)
│   ├── SLAVE  1: UART       0x10000000 – 0x10000FFF  (4 KB)
│   ├── SLAVE  2: VGA FB     0x20000000 – 0x20000FFF  (4 KB)
│   └── SLAVE  3: GPU MMIO   0x30000000 – 0x3000001F  (32 B)
│
├── u_bram              [Xilinx BRAM36 primitive]         256 KB unified instr+data
│
├── u_uart              [rtl/core/uart_tx.sv]             TX-only debug UART
│
├── u_char_framebuffer  [rtl/vga/char_framebuffer.sv]     80×45 byte BRAM
│   ├── AXI4-Lite write port  ← fabric SLAVE 2
│   └── Sync read port        → u_vga_top
│
├── u_gpu_top           [rtl/gpu/gpu_top.sv]
│   ├── AXI4-Lite slave       ← fabric SLAVE 3  (GPU MMIO registers)
│   ├── Framebuffer write     → u_char_framebuffer
│   │
│   ├── u_gpu_mmio      [rtl/gpu/gpu_mmio.sv]
│   │   └── GPU_CTRL / GPU_STATUS / PLAYER_X,Y,ANG / GPU_CYCLES / CORE_UTIL / DMA_*
│   │
│   ├── u_gpu_dispatcher [rtl/gpu/gpu_dispatcher.sv]  NUM_CORES=4
│   │   └── column N → core (N % NUM_CORES), static dispatch
│   │
│   ├── u_dda_core_0 … u_dda_core_3  [rtl/gpu/dda_core.sv]
│   │   ├── fpmul [rtl/lib/fpmul.sv]  Q16.16 multiply
│   │   ├── fpdiv [rtl/lib/fpdiv.sv]  Q16.16 divide
│   │   └── Map RAM read port (combinational addr, sync data from BRAM)
│   │
│   └── u_gpu_collector  [rtl/gpu/gpu_collector.sv]
│       └── Aggregates done pulses → framebuffer write stream
│
└── u_vga_top           [rtl/vga/vga_top.sv]   *** PIXEL CLOCK DOMAIN (25.175 MHz) ***
    ├── u_vga_sync      [rtl/vga/vga_sync.sv]   H/V counters, sync signals
    ├── u_font_rom      [rtl/lib/font_rom.sv]   128 chars × 8 rows BRAM ROM
    └── u_char_fb_read  ← sync read port from u_char_framebuffer
        └── Outputs: vga_r[3:0], vga_g[3:0], vga_b[3:0], vga_hsync, vga_vsync
```

## AXI Connection Table

| Master | Direction | Slave | Channel |
|--------|-----------|-------|---------|
| CPU    | → fabric  | BRAM  | AW/W/B (write), AR/R (read) |
| CPU    | → fabric  | UART  | AW/W/B |
| CPU    | → fabric  | VGA FB| AW/W/B |
| CPU    | → fabric  | GPU MMIO | AW/W/B, AR/R |
| DMA    | → fabric  | BRAM  | AR/R (source read) |
| DMA    | → fabric  | VGA FB| AW/W/B (destination write) |
| DMA    | → fabric  | GPU MMIO | AW/W/B (register config from CPU via DMA) |

## Clock Domains

```
                    ┌─────────────────────────────────────────────────────┐
100 MHz (sys_clk)   │  soc_top, picorv32, axi_dma, axi_fabric, bram,     │
                    │  uart, char_framebuffer (write port), gpu_top,       │
                    │  gpu_dispatcher, dda_core × 4, gpu_collector,        │
                    │  gpu_mmio, fpmul, fpdiv                              │
                    └───────────────────┬─────────────────────────────────┘
                                        │
                              MMCM (100 → 25.175 MHz)
                                        │
                    ┌───────────────────▼─────────────────────────────────┐
25.175 MHz (pix_clk)│  vga_sync, font_rom, vga_top pixel pipeline         │
                    │  char_framebuffer READ port (async BRAM — no CDC    │
                    │  needed: write and read addresses never alias during │
                    │  the same cycle by design — GPU writes row 0..44    │
                    │  sequentially, VGA reads row/col from pixel counters)│
                    └─────────────────────────────────────────────────────┘
```

### CDC Boundary Detail

The `char_framebuffer` is a true dual-port BRAM:
- **Write port**: clocked by `sys_clk` (100 MHz), driven by GPU collector
- **Read port**: clocked by `pix_clk` (25.175 MHz), driven by VGA pixel counters

Xilinx BRAM36 supports independent port clocks (TRUE_DP mode). The only data
hazard is a simultaneous read/write to the same address. By design this cannot
produce a corrupted display frame — the GPU writes each frame top-to-bottom in
80 columns × 1 row, while the VGA raster scans the same grid once per 1/60 s.
Any torn frame shows at most one stale row, which is visually acceptable.
No synchronizer chain is needed because the BRAM output is registered and the
VGA pipeline treats it as read-only during raster scan.

## GPU Dispatch and Collection Timing

```
frame_start asserted (1 cycle)
     │
     ▼
gpu_dispatcher:
  cycle 0: start core_0 with col=0, core_1 with col=1, core_2 with col=2, core_3 with col=3
  cycle 1: start core_0 with col=4, ... (core N gets col = 4k + N)
  ...after 20 cycles: all 80 columns dispatched (20 rounds × 4 cores)

Each dda_core: variable latency (depends on wall distance), ~10–200 cycles
  → done pulse + ascii_char[7:0] + col_index[6:0]

gpu_collector: accepts done pulses from any core, writes to char_framebuffer
  frame_done asserted when 80 done pulses received
```

## Memory Map Rationale

- BRAM at 0x00000000: PicoRV32 default reset vector, simplest linker script
- UART at 0x10000000: upper nibble decode, no aliasing with code space
- VGA FB at 0x20000000: CPU writes ASCII characters directly to framebuffer
- GPU MMIO at 0x30000000: 32-byte register file, address decode on bits[31:28]
