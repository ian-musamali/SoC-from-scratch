#!/usr/bin/env python3
"""Regenerate docs/images/screenshot.png from a captured frame dump.

Rasterizes an 80x45 char_framebuffer dump using the real font_rom.sv bitmaps
(fonts/font8x8.hex), so the screenshot matches exactly what the VGA output
shows for that frame (not a mockup).

Usage:
    1. Capture a frame dump from the sim regression:
         cd ascii_doom_soc
         DUMP_FRAME_GRID=/tmp/frame_grid.txt ./sim/tb_soc/obj_dir/Vsoc_top
       (env var opt-in, see sim/tb_soc/tb_soc_top.cpp — no effect on the
       regression's PASS/FAIL result)
    2. python3 docs/images/gen_screenshot.py /tmp/frame_grid.txt
"""
import sys
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
FONT_HEX = REPO_ROOT / "fonts" / "font8x8.hex"
OUT_PNG = Path(__file__).resolve().parent / "screenshot.png"

NUM_ROWS, NUM_COLS = 45, 80
SCALE = 2  # 8x8 glyph -> 16x16px/cell; 1280x720 output
FG = (60, 220, 90)  # classic green phosphor VGA text look


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <frame_grid.txt>", file=sys.stderr)
        sys.exit(1)
    grid_path = Path(sys.argv[1])

    with open(FONT_HEX) as f:
        font_rows = [int(l.strip(), 16) for l in f if l.strip()]

    with open(grid_path) as f:
        grid = [[int(tok, 16) for tok in line.split()] for line in f if line.strip()]
    assert len(grid) == NUM_ROWS and all(len(r) == NUM_COLS for r in grid)

    w, h = NUM_COLS * 8 * SCALE, NUM_ROWS * 8 * SCALE
    img = Image.new("RGB", (w, h), (0, 0, 0))
    px = img.load()

    for r in range(NUM_ROWS):
        for c in range(NUM_COLS):
            ch = grid[r][c]
            rows = font_rows[ch * 8:ch * 8 + 8]
            for gy, bits in enumerate(rows):
                for gx in range(8):
                    if bits & (0x80 >> gx):
                        x0 = (c * 8 + gx) * SCALE
                        y0 = (r * 8 + gy) * SCALE
                        for dy in range(SCALE):
                            for dx in range(SCALE):
                                px[x0 + dx, y0 + dy] = FG

    img.save(OUT_PNG)
    print(f"Wrote {OUT_PNG} ({w}x{h})")


if __name__ == "__main__":
    main()
