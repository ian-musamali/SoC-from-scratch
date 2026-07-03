#!/usr/bin/env python3
"""Generate font8x8.hex: a 128-glyph x 8-row 8x8 bitmap font for font_rom.sv.

The checked-in font8x8.hex was previously a placeholder (every glyph slot held
the same 0xaa/0x55 checkerboard byte pair) — real hardware VGA output would
have shown garbage instead of legible characters. This renders each printable
ASCII glyph (0x20-0x7e) from a real TTF (DejaVu Sans Mono Bold, downsampled to
8x8 and thresholded to 1-bit) with a shared baseline for consistent alignment;
0x00-0x1f and 0x7f (non-printable) are left blank.

Addressing matches font_rom.sv: addr[9:0] = {char_index[6:0], row[2:0]}, one
line per row, bit 7 = leftmost pixel, 8 rows per glyph, 128 glyphs = 1024 lines.
"""
from PIL import Image, ImageDraw, ImageFont

FONT_TTF = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
SUPERSAMPLE = 4
CANVAS = 8 * SUPERSAMPLE
THRESHOLD = 100

font = ImageFont.truetype(FONT_TTF, int(7.2 * SUPERSAMPLE))
ascent, descent = font.getmetrics()
baseline_y = (CANVAS - (ascent + descent)) // 2 + ascent


def render_glyph(ch):
    img = Image.new("L", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), ch, font=font)
    w = bbox[2] - bbox[0]
    x = (CANVAS - w) // 2 - bbox[0]
    draw.text((x, baseline_y), ch, fill=255, font=font, anchor="ls")
    small = img.resize((8, 8), Image.LANCZOS)
    rows = []
    for ry in range(8):
        b = 0
        for rx in range(8):
            if small.getpixel((rx, ry)) > THRESHOLD:
                b |= (0x80 >> rx)
        rows.append(b)
    return rows


with open("font8x8.hex", "w") as f:
    for code in range(128):
        if 0x20 <= code <= 0x7e:
            rows = render_glyph(chr(code))
        else:
            rows = [0] * 8
        for b in rows:
            f.write(f"{b:02x}\n")

print("Wrote font8x8.hex (128 glyphs x 8 rows)")
