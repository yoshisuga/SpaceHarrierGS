#!/usr/bin/env python3
"""Export DEC0R (full SHR screen) to PNG and extract sidebar data.

Usage:
    python3 decor2png.py [decor_file] [output.png]

DEC0R is a raw 32768-byte SHR screen image (160 bytes/row × 200 rows + 512 SCB/palette bytes).
"""

import sys
import os
from PIL import Image

# IIgs 4-bit color component to 8-bit
def gs_to_rgb(val):
    """Convert a 4-bit IIgs color value (0-15) to 8-bit (0-255)."""
    return (val * 255) // 15

def read_palettes(data):
    """Read the 16 palettes from SCB/palette area at offset $7E00."""
    palettes = []
    palette_base = 0x7E00
    for p in range(16):
        pal = []
        for c in range(16):
            off = palette_base + p * 32 + c * 2
            lo = data[off]
            hi = data[off + 1]
            word = lo | (hi << 8)
            b = (word >> 8) & 0xF
            g = (word >> 4) & 0xF
            r = word & 0xF
            pal.append((gs_to_rgb(r), gs_to_rgb(g), gs_to_rgb(b)))
        palettes.append(pal)
    return palettes

def read_scbs(data):
    """Read SCB for each scanline (200 bytes at $7D00)."""
    scbs = []
    for row in range(200):
        scbs.append(data[0x7D00 + row])
    return scbs

def main():
    src_base = os.path.join(os.path.dirname(__file__),
                            '../../SpaceHarrierGSSource/Space.Harrier')
    default_path = os.path.join(src_base, 'DEC0R')

    decor_path = sys.argv[1] if len(sys.argv) > 1 else default_path
    output_path = sys.argv[2] if len(sys.argv) > 2 else 'decor.png'

    if not os.path.exists(decor_path):
        print(f"DEC0R not found: {decor_path}")
        sys.exit(1)

    with open(decor_path, 'rb') as f:
        data = f.read()

    print(f"DEC0R: {len(data)} bytes")

    palettes = read_palettes(data)
    scbs = read_scbs(data)

    # Render full screen
    scale = 2
    img = Image.new('RGB', (320 * scale, 200 * scale))

    for row in range(200):
        pal_idx = scbs[row] & 0x0F
        pal = palettes[pal_idx]
        for col_byte in range(160):
            byte = data[row * 160 + col_byte]
            px0 = (byte >> 4) & 0x0F
            px1 = byte & 0x0F
            x = col_byte * 2
            for px, idx in [(x, px0), (x + 1, px1)]:
                rgb = pal[idx]
                for sy in range(scale):
                    for sx in range(scale):
                        img.putpixel((px * scale + sx, row * scale + sy), rgb)

    img.save(output_path)
    print(f"Saved full screen: {output_path} ({img.width}x{img.height})")

    # Also save just the sidebar (columns 128-159, i.e. pixels 256-319)
    sidebar_px_start = 256
    sidebar_px_end = 320
    sidebar_w = sidebar_px_end - sidebar_px_start
    sidebar_img = Image.new('RGB', (sidebar_w * scale, 200 * scale))

    for row in range(200):
        pal_idx = scbs[row] & 0x0F
        pal = palettes[pal_idx]
        for col_byte in range(128, 160):
            byte = data[row * 160 + col_byte]
            px0 = (byte >> 4) & 0x0F
            px1 = byte & 0x0F
            x = (col_byte - 128) * 2
            for px, idx in [(x, px0), (x + 1, px1)]:
                rgb = pal[idx]
                for sy in range(scale):
                    for sx in range(scale):
                        sidebar_img.putpixel((px * scale + sx, row * scale + sy), rgb)

    sidebar_path = output_path.replace('.png', '_sidebar.png')
    sidebar_img.save(sidebar_path)
    print(f"Saved sidebar: {sidebar_path} ({sidebar_img.width}x{sidebar_img.height})")

    # Print palette 0 for reference
    print("\nPalette 0:")
    for i, rgb in enumerate(palettes[0]):
        print(f"  ${i:X}: ({rgb[0]:3d}, {rgb[1]:3d}, {rgb[2]:3d})")

    # Print SCB info
    print(f"\nSCBs: {set(scbs)}")


if __name__ == '__main__':
    main()
