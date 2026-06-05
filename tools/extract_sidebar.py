#!/usr/bin/env python3
"""Extract sidebar from DEC0R and render with game palette.

Also exports raw binary sidebar data (32 bytes/row × 200 rows = 6400 bytes).
"""

import sys
import os
from PIL import Image

# Game palette (from SetupPalettes in App.Main.s)
GAME_PALETTE_IIgs = {
    0x0: 0x0000,  # black
    0x1: 0x0000,  # black (sidebar)
    0x2: 0x0466,  # blue-grey
    0x3: 0x0449,  # blue
    0x4: 0x0ADA,  # light green (checker)
    0x5: 0x0092,  # green
    0x6: 0x0640,  # red-brown
    0x7: 0x0699,  # blue-grey
    0x8: 0x0D94,  # orange/skin
    0x9: 0x0FD4,  # yellow
    0xA: 0x0D40,  # red-orange
    0xB: 0x069D,  # med blue
    0xC: 0x00D4,  # green
    0xD: 0x0062,  # dark green
    0xE: 0x07A7,  # sage/checker dark
    0xF: 0x0FFF,  # white
}

def iigs_to_rgb(word):
    r = word & 0xF
    g = (word >> 4) & 0xF
    b = (word >> 8) & 0xF
    return ((r * 255) // 15, (g * 255) // 15, (b * 255) // 15)

GAME_PALETTE = {k: iigs_to_rgb(v) for k, v in GAME_PALETTE_IIgs.items()}


def main():
    src_base = os.path.join(os.path.dirname(__file__),
                            '../../SpaceHarrierGSSource/Space.Harrier')
    decor_path = os.path.join(src_base, 'DEC0R')

    with open(decor_path, 'rb') as f:
        data = f.read()

    # Extract sidebar bytes: columns 128-159 (32 bytes per row) for 200 rows
    sidebar_bytes = bytearray()
    for row in range(200):
        row_start = row * 160 + 128
        sidebar_bytes.extend(data[row_start:row_start + 32])

    print(f"Sidebar: {len(sidebar_bytes)} bytes")

    # Save raw binary
    with open('SIDEBAR', 'wb') as f:
        f.write(sidebar_bytes)
    print(f"Saved: SIDEBAR ({len(sidebar_bytes)} bytes)")

    # Render with game palette
    scale = 2
    w = 64  # 32 bytes = 64 pixels
    h = 200
    img = Image.new('RGB', (w * scale, h * scale))

    for row in range(h):
        for col_byte in range(32):
            byte = sidebar_bytes[row * 32 + col_byte]
            px0 = (byte >> 4) & 0x0F
            px1 = byte & 0x0F
            x = col_byte * 2
            for px_off, idx in [(0, px0), (1, px1)]:
                rgb = GAME_PALETTE[idx]
                for sy in range(scale):
                    for sx in range(scale):
                        img.putpixel(((x + px_off) * scale + sx, row * scale + sy), rgb)

    img.save('sidebar_game_palette.png')
    print(f"Saved: sidebar_game_palette.png (with game palette)")

    # Also render with DEC0R's native palette for comparison
    def gs_to_rgb(val):
        return (val * 255) // 15

    decor_pal = []
    for c in range(16):
        off = 0x7E00 + c * 2
        lo = data[off]
        hi = data[off + 1]
        word = lo | (hi << 8)
        b = (word >> 8) & 0xF
        g = (word >> 4) & 0xF
        r = word & 0xF
        decor_pal.append((gs_to_rgb(r), gs_to_rgb(g), gs_to_rgb(b)))

    img2 = Image.new('RGB', (w * scale, h * scale))
    for row in range(h):
        for col_byte in range(32):
            byte = sidebar_bytes[row * 32 + col_byte]
            px0 = (byte >> 4) & 0x0F
            px1 = byte & 0x0F
            x = col_byte * 2
            for px_off, idx in [(0, px0), (1, px1)]:
                rgb = decor_pal[idx]
                for sy in range(scale):
                    for sx in range(scale):
                        img2.putpixel(((x + px_off) * scale + sx, row * scale + sy), rgb)

    img2.save('sidebar_decor_palette.png')
    print(f"Saved: sidebar_decor_palette.png (with DEC0R palette)")


if __name__ == '__main__':
    main()
