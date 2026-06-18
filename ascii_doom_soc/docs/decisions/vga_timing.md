# VGA Timing

## Timing Parameters (VESA 640×480 @ 60 Hz)

| Parameter | Value | Notes |
|-----------|-------|-------|
| Pixel clock | 25.175 MHz | From MMCM (100 MHz ÷ 3.976, closest achievable) |
| Horizontal total | 800 pixels | Active + front porch + sync + back porch |
| H active | 640 | Visible pixels per line |
| H front porch | 16 | Pixels before sync |
| H sync pulse | 96 | Active-low, ~3.81 µs |
| H back porch | 48 | Pixels after sync |
| Vertical total | 525 lines | |
| V active | 480 | Visible lines |
| V front porch | 10 | Lines before sync |
| V sync pulse | 2 | Active-low, ~63.56 µs |
| V back porch | 33 | Lines after sync |
| Frame rate | 59.94 Hz | 25.175 MHz / (800 × 525) |

## Pixel Clock Generation

Vivado MMCM generates 25.175 MHz from the 100 MHz Nexys A7 oscillator:
- CLKFBOUT_MULT_F = 10.0 (VCO = 1000 MHz)
- CLKOUT0_DIVIDE_F = 39.75 (closest to 1000/25.175 ≈ 39.72)
- Actual output ≈ 25.157 MHz (0.07% error — within VGA monitor tolerance)

## Character Grid Mapping

The 80×45 ASCII grid occupies the top 640×360 pixels:
- 80 columns × 8 pixels/column = 640 pixels wide (fills entire active width)
- 45 rows × 8 pixels/row = 360 pixels tall
- Bottom 120 lines (pixels 360–479): blanked to black (font_pixel = 0)

Address formula: `fb_addr = (pixel_y >> 3) * 80 + (pixel_x >> 3)`

This maps pixel coordinates to the char_framebuffer byte at the corresponding character cell.

## VGA Pipeline

The render pipeline takes 2 cycles due to BRAM read latency:

```
Cycle N:   Compute fb_addr from pixel_x/y  →  char_framebuffer read port
Cycle N+1: Receive char byte               →  font_rom read port (using sub-pixel row)
Cycle N+2: Receive glyph row byte          →  extract bit → RGB output
```

The 2-cycle latency shifts the displayed image 2 pixels to the right. The horizontal front porch (16 pixels) provides margin; a 2-pixel shift is imperceptible.

## BRAM Utilization Estimate

- `char_framebuffer`: 3600 bytes → 1× BRAM36 (36 Kbit, used at 10%)
- `font_rom`: 1024 bytes → 1× BRAM36 (used at 2.8%)
- Total: 2× BRAM36 for the entire display subsystem

## Simulation Results

| Test | Expected | Result |
|------|----------|--------|
| hsync pulse width | 96 ticks | 96 ticks — PASS |
| vsync pulse width | 2 lines | 2 lines — PASS |
| Lines per frame | 525 | 525 — PASS |
