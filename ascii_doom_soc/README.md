# ASCII Doom SoC v2

A multi-core DDA raycasting GPU paired with a PicoRV32 RISC-V core on Nexys A7 (Artix-7 XC7A100T), rendering a first-person ASCII Doom-like scene over VGA.

## Board
Nexys A7 — Artix-7 XC7A100T, 100 MHz

## Architecture
<!-- Block diagram placeholder — see docs/arch/soc_hierarchy.md -->

## Key Features
- PicoRV32 RISC-V soft core with AXI4-Lite bus
- Parallel DDA raycasting GPU (4 cores, parameterizable to 8)
- VGA 640×480 @ 60 Hz with 80×45 ASCII character display
- Custom AXI DMA controller for autonomous data movement
- Q16.16 fixed-point arithmetic throughout
- GDS tape-out ready (GPU block, sky130A PDK)

## Quick Start

### Simulate
```bash
# Unit tests
cd sim/unit && make

# Integration sim
cd sim/integration && make
```

### Deploy to Nexys A7
```bash
# TODO: add Vivado flow commands after synthesis
```

### GDS Flow
```bash
# TODO: add OpenLane2 commands after Step 15
```

## Performance
<!-- To be filled after synthesis -->
- FPS: TBD
- LUT: TBD%  FF: TBD%  BRAM: TBD%  DSP: TBD%
- Max GPU frequency: TBD MHz
- Gate count: TBD

## Documentation
- [Architecture](docs/arch/soc_hierarchy.md)
- [Fixed-Point Math](docs/decisions/fixed_point.md)
- [VGA Timing](docs/decisions/vga_timing.md)
- [AXI Fabric](docs/decisions/axi_fabric.md)
- [Parallel DDA](docs/decisions/parallel_dda.md)
- [DMA Controller](docs/decisions/dma_controller.md)
- [GDS Flow](docs/decisions/gds_flow.md)
