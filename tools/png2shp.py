#!/usr/bin/env python3
"""Convert PNG sprite images back to FTA Space Harrier .SHP binary format.

Usage:
    python3 png2shp.py <shape_name> <input_dir> [output.shp]

    shape_name: tree, explo, tir, pierre, ombre, buisson, ship, trident
    input_dir:  directory with individual PNGs (e.g. pierre_sprites/)
                files named <shape>_00.png, <shape>_01.png, etc.
    output.shp: output path (default: <shape_name>.SHP)

Workflow:
    1. Run shp2png.py to export sprites to PNG
    2. Edit PNGs in GIMP (keep same dimensions, use palette colors)
    3. Run png2shp.py to convert back to .SHP

Color matching:
    - Magenta (#FF00FF) → color 0 (transparent)
    - Other colors → nearest palette match
    - Keep sprites at 2x scale (same as export), tool auto-detects scale
"""

import sys
import os
import math
from PIL import Image

# Same palette as shp2png.py
PALETTE = {
    0x0: (0, 0, 0),
    0x1: (0, 0, 0),
    0x2: (68, 102, 102),
    0x3: (68, 68, 153),
    0x4: (238, 238, 170),
    0x5: (0, 153, 34),
    0x6: (102, 68, 0),
    0x7: (102, 153, 153),
    0x8: (221, 153, 68),
    0x9: (255, 221, 68),
    0xA: (221, 68, 0),
    0xB: (102, 153, 221),
    0xC: (0, 221, 68),
    0xD: (0, 102, 34),
    0xE: (170, 170, 85),
    0xF: (255, 255, 255),
}

TRANSPARENT = (255, 0, 255)

# Sprite tables (same as shp2png.py)
SPRITE_TABLES = {
    'tree': [
        (0x0000, 0x79, 0x20), (0x0F30, 0x50, 0x16), (0x1620, 0x3C, 0x10),
        (0x19F0, 0x30, 0x0C), (0x1C40, 0x28, 0x0A), (0x1DE0, 0x21, 0x0A),
        (0x1F30, 0x1D, 0x08), (0x2020, 0x19, 0x08), (0x20F0, 0x17, 0x06),
        (0x2180, 0x14, 0x06), (0x2200, 0x13, 0x06), (0x2278, 0x11, 0x06),
        (0x22E8, 0x11, 0x04), (0x2330, 0x10, 0x04), (0x2378, 0x0F, 0x04),
        (0x23C0, 0x0E, 0x04),
    ],
    'explo': [
        (0, 36, 48), (1732, 29, 44), (3012, 23, 32), (3752, 19, 30),
        (4326, 18, 24), (4762, 15, 22), (5096, 14, 20), (5380, 12, 16),
        (5576, 10, 14), (5720, 9, 12), (5832, 8, 12),
    ],
    'tir': [
        (0, 14, 16), (228, 14, 14), (428, 10, 10), (532, 8, 8),
        (600, 7, 6), (646, 6, 6), (686, 5, 6), (720, 4, 4),
        (740, 4, 4), (760, 4, 4), (780, 3, 3),
    ],
    'pierre': [
        (0, 29, 38), (1106, 20, 24), (1590, 14, 18), (1846, 11, 16),
        (2026, 10, 14), (2170, 9, 12), (2282, 7, 10), (2356, 6, 10),
    ],
    'ombre': [
        (0, 12, 26), (316, 9, 18), (482, 6, 14), (570, 5, 10),
        (624, 4, 8), (660, 3, 8), (688, 2, 6), (704, 1, 6),
    ],
    'buisson': [
        (0, 29, 36), (1048, 18, 24), (1484, 14, 18), (1740, 11, 14),
        (1898, 9, 12), (2010, 8, 10), (2094, 7, 10), (2168, 6, 8),
        (2220, 5, 8), (2264, 5, 6), (2298, 4, 6), (2326, 4, 6),
        (2354, 4, 6), (2383, 2, 6),
    ],
    'ship': [
        (0, 35, 46), (1614, 22, 30), (2278, 16, 24), (2666, 13, 18),
        (2904, 10, 16), (3068, 9, 14), (3198, 7, 12), (3286, 6, 10),
        (3350, 6, 8), (3402, 5, 8), (3446, 4, 8), (3482, 4, 8),
        (3518, 4, 6), (3546, 3, 6), (3568, 3, 6),
    ],
    'trident': [
        (0, 48, 32), (1540, 42, 28), (2720, 34, 24), (3540, 23, 16),
        (3912, 18, 14), (4168, 15, 12), (4352, 12, 10), (4476, 11, 8),
        (4568, 7, 4),
    ],
}

HEADER_SIZE = 4


def color_distance(c1, c2):
    """Euclidean distance between two RGB tuples."""
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(c1, c2)))


def rgb_to_index(rgb):
    """Map an RGB pixel to the nearest palette index."""
    r, g, b = rgb[:3]  # handle RGBA

    # Magenta = transparent
    if (r, g, b) == TRANSPARENT or (r > 200 and g < 50 and b > 200):
        return 0

    # Black = 0 (transparent)
    if r < 10 and g < 10 and b < 10:
        return 0

    # Find nearest palette color (skip index 0 and 1 which are both black)
    best_idx = 0
    best_dist = float('inf')
    for idx in range(2, 16):
        d = color_distance((r, g, b), PALETTE[idx])
        if d < best_dist:
            best_dist = d
            best_idx = idx

    return best_idx


def detect_scale(img_w, img_h, expected_w, expected_h):
    """Auto-detect the scale factor of the PNG."""
    sx = img_w / expected_w
    sy = img_h / expected_h
    scale = round((sx + sy) / 2)
    if scale < 1:
        scale = 1
    return scale


def png_to_sprite(img_path, expected_rows, expected_cols_bytes):
    """Convert a PNG back to sprite pixel data (list of bytes)."""
    img = Image.open(img_path).convert('RGB')
    expected_w = expected_cols_bytes * 2  # pixels
    expected_h = expected_rows

    scale = detect_scale(img.width, img.height, expected_w, expected_h)

    if img.width != expected_w * scale or img.height != expected_h * scale:
        print(f"  Warning: {img_path} is {img.width}x{img.height}, "
              f"expected {expected_w * scale}x{expected_h * scale} at {scale}x")

    sprite_bytes = []
    for row in range(expected_h):
        for col_byte in range(expected_cols_bytes):
            px_x = col_byte * 2
            # Sample center of each scaled pixel
            x0 = px_x * scale + scale // 2
            x1 = (px_x + 1) * scale + scale // 2
            y = row * scale + scale // 2

            # Clamp to image bounds
            x0 = min(x0, img.width - 1)
            x1 = min(x1, img.width - 1)
            y = min(y, img.height - 1)

            hi = rgb_to_index(img.getpixel((x0, y)))
            lo = rgb_to_index(img.getpixel((x1, y)))
            sprite_bytes.append((hi << 4) | lo)

    return bytes(sprite_bytes)


def build_shp(shape_name, input_dir, output_path):
    """Build a .SHP file from individual PNGs."""
    table = SPRITE_TABLES[shape_name]

    # Calculate total file size from the last sprite's offset + data
    last = table[-1]
    last_offset, last_rows, last_cols = last
    total_size = last_offset + HEADER_SIZE + last_rows * last_cols

    shp_data = bytearray(total_size)

    for i, (offset, rows, cols) in enumerate(table):
        png_path = os.path.join(input_dir, f"{shape_name}_{i:02d}.png")
        if not os.path.exists(png_path):
            print(f"  [{i:2d}] MISSING: {png_path}")
            continue

        sprite_data = png_to_sprite(png_path, rows, cols)

        # Write 4-byte header (use simple format: 0, 0, rows, cols)
        shp_data[offset] = 0
        shp_data[offset + 1] = 0
        shp_data[offset + 2] = rows & 0xFF
        shp_data[offset + 3] = cols & 0xFF

        # Write pixel data after header
        data_start = offset + HEADER_SIZE
        for j, b in enumerate(sprite_data):
            if data_start + j < len(shp_data):
                shp_data[data_start + j] = b

        w = cols * 2
        print(f"  [{i:2d}] {w}x{rows} px  <-  {png_path}")

    with open(output_path, 'wb') as f:
        f.write(shp_data)

    print(f"\nWrote {len(shp_data)} bytes to {output_path}")


def main():
    if len(sys.argv) < 3 or sys.argv[1] in ('-h', '--help'):
        print(__doc__)
        print("Available shapes:", ', '.join(SPRITE_TABLES.keys()))
        sys.exit(0)

    shape_name = sys.argv[1].lower()
    if shape_name not in SPRITE_TABLES:
        print(f"Unknown shape: {shape_name}")
        print("Available:", ', '.join(SPRITE_TABLES.keys()))
        sys.exit(1)

    input_dir = sys.argv[2]
    output = sys.argv[3] if len(sys.argv) > 3 else f"{shape_name}.SHP"

    if not os.path.isdir(input_dir):
        print(f"Input directory not found: {input_dir}")
        sys.exit(1)

    build_shp(shape_name, input_dir, output)


if __name__ == '__main__':
    main()
