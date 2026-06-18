#!/usr/bin/env python3
"""Convert a RISC-V ELF binary to a $readmemh hex file for a 32-bit wide BRAM.
Each output line is one 32-bit word (8 hex chars), little-endian byte order.
The output file is padded to BRAM_WORDS words.
Usage: python3 elf2hex.py firmware.bin firmware.hex [bram_words]
"""
import struct, sys

src  = sys.argv[1]
dst  = sys.argv[2]
size = int(sys.argv[3]) if len(sys.argv) > 3 else 65536  # default 256 KB

with open(src, "rb") as f:
    data = f.read()

# Pad to 4-byte boundary then to full BRAM size
data += b"\x00" * (-len(data) % 4)
words = struct.unpack_from("<" + "I" * (len(data) // 4), data)

if len(words) > size:
    print(f"WARNING: firmware ({len(words)} words) exceeds BRAM ({size} words)", file=sys.stderr)

with open(dst, "w") as f:
    for i in range(size):
        w = words[i] if i < len(words) else 0
        f.write(f"{w:08x}\n")

print(f"Wrote {dst}: {len(words)} firmware words + {size - len(words)} padding = {size} total")
