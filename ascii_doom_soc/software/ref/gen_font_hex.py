"""
gen_font_hex.py — Generate checkerboard placeholder font for ASCII Doom SoC
128 ASCII chars × 8 rows × 1 byte = 1024 bytes
Output: fonts/font8x8.hex (relative to project root, two levels up from software/ref/)
"""

import os

def main():
    # Resolve output path relative to this script's location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(script_dir, '..', '..', 'fonts', 'font8x8.hex')
    out_path = os.path.normpath(out_path)

    # Ensure output directory exists
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    lines = []
    for char_idx in range(128):       # 128 ASCII characters
        for row in range(8):          # 8 rows per character
            byte = 0xAA if (row % 2 == 0) else 0x55
            lines.append(f'{byte:02x}')

    with open(out_path, 'w') as f:
        f.write('\n'.join(lines) + '\n')

    print(f"Generated fonts/font8x8.hex: {len(lines)} bytes")


if __name__ == '__main__':
    main()
