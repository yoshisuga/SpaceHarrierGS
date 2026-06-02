#!/usr/bin/env python3
"""Convert FTA Space Harrier .SHP sprite files to PNG sprite sheets.

Usage:
    python3 shp2png.py <shape_name> [shp_file] [output.png]

    shape_name: tree, explo, tir, pierre, ombre, buisson, ship, trident
    shp_file:   path to .SHP binary (default: looks in ../SpaceHarrierGSSource)
    output.png: output path (default: <shape_name>.png)

Each sprite is drawn side by side on the sheet with a 1px gap.
Color 0 is rendered as magenta (transparent indicator).
"""

import sys
import os
from PIL import Image

# FTA game palette (from SetupPalettes in App.Main.s)
# Format: index -> (R, G, B) scaled from 0-15 to 0-255
PALETTE = {
    0x0: (0, 0, 0),       # black (transparent)
    0x1: (0, 0, 0),       # black (sidebar)
    0x2: (68, 102, 102),   # blue-grey
    0x3: (68, 68, 153),    # blue
    0x4: (238, 238, 170),  # pale cream (checker)
    0x5: (0, 153, 34),     # green
    0x6: (102, 68, 0),     # red-brown
    0x7: (102, 153, 153),  # blue-grey
    0x8: (221, 153, 68),   # orange/skin
    0x9: (255, 221, 68),   # bright yellow
    0xA: (221, 68, 0),     # red-orange
    0xB: (102, 153, 221),  # medium blue
    0xC: (0, 221, 68),     # green
    0xD: (0, 102, 34),     # dark green
    0xE: (170, 170, 85),   # sage (checker)
    0xF: (255, 255, 255),  # white
}

# Transparent color for display (magenta)
TRANSPARENT = (255, 0, 255)

# Sprite tables from SPACE.S — each entry: (offset, rows, cols_bytes)
# cols_bytes = number of bytes per row (2 pixels per byte)
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

# Default .SHP file paths
SHP_PATHS = {
    'tree':    'PIC/TREE.SHAPE',
    'explo':   'PIC/EXPLO.SHP',
    'tir':     'PIC/TIR.SHP',
    'pierre':  'PIC/PIERRE.SHP',
    'ombre':   'PIC/OMBRE.SHP',
    'buisson': 'PIC/BUISSON.SHP',
    'ship':    'PIC2/SHIP.SHP',
    'trident': 'PIC2/TRIDENT.SHP',
}

# Whether this shape type has 4-byte headers per sprite
# Tree uses a different format (no headers, raw data at offsets)
HEADER_SIZE = 4


def decode_sprite(data, offset, rows, cols_bytes):
    """Decode one sprite from SHP data.
    Returns list of rows, each row is a list of pixel color indices (0-15).
    """
    pixel_width = cols_bytes * 2  # 2 pixels per byte
    pixels = []

    # Try with 4-byte header first
    data_offset = offset + HEADER_SIZE

    # Sanity check: if offset+header+data exceeds file, try without header
    if data_offset + rows * cols_bytes > len(data):
        data_offset = offset  # no header

    if data_offset + rows * cols_bytes > len(data):
        print(f"  Warning: sprite at offset {offset} exceeds file size, skipping")
        return None

    for row in range(rows):
        row_pixels = []
        for col in range(cols_bytes):
            byte = data[data_offset + row * cols_bytes + col]
            row_pixels.append((byte >> 4) & 0x0F)  # high nibble = left pixel
            row_pixels.append(byte & 0x0F)           # low nibble = right pixel
        pixels.append(row_pixels)

    return pixels


def sprite_to_image(pixels, scale=1):
    """Convert pixel array to PIL Image."""
    if not pixels:
        return None
    h = len(pixels)
    w = len(pixels[0])
    img = Image.new('RGB', (w * scale, h * scale))

    for y, row in enumerate(pixels):
        for x, color_idx in enumerate(row):
            if color_idx == 0:
                rgb = TRANSPARENT
            else:
                rgb = PALETTE.get(color_idx, (0, 0, 0))
            for sy in range(scale):
                for sx in range(scale):
                    img.putpixel((x * scale + sx, y * scale + sy), rgb)

    return img


def make_sprite_sheet(data, table, scale=2):
    """Create a sprite sheet with all sprites side by side."""
    sprites = []
    max_h = 0
    total_w = 0
    gap = 2 * scale

    for i, (offset, rows, cols) in enumerate(table):
        pixels = decode_sprite(data, offset, rows, cols)
        if pixels is None:
            continue
        img = sprite_to_image(pixels, scale)
        sprites.append((img, i))
        max_h = max(max_h, img.height)
        total_w += img.width + gap

    if not sprites:
        print("No sprites decoded!")
        return None

    total_w -= gap  # no gap after last sprite

    sheet = Image.new('RGB', (total_w, max_h + 20 * scale), (64, 64, 64))
    x = 0
    for img, idx in sprites:
        # Bottom-align sprites (like they sit on a ground line)
        y = max_h - img.height
        sheet.paste(img, (x, y))
        x += img.width + gap

    return sheet


def export_individual(data, table, name, output_dir, scale=2):
    """Export each sprite as a separate PNG file."""
    os.makedirs(output_dir, exist_ok=True)

    for i, (offset, rows, cols) in enumerate(table):
        pixels = decode_sprite(data, offset, rows, cols)
        if pixels is None:
            continue
        img = sprite_to_image(pixels, scale)
        path = os.path.join(output_dir, f"{name}_{i:02d}.png")
        img.save(path)
        w = cols * 2
        print(f"  [{i:2d}] {w}x{rows} px  ->  {path}")


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print(__doc__)
        print("Available shapes:", ', '.join(SPRITE_TABLES.keys()))
        sys.exit(0)

    shape_name = sys.argv[1].lower()
    if shape_name not in SPRITE_TABLES:
        print(f"Unknown shape: {shape_name}")
        print("Available:", ', '.join(SPRITE_TABLES.keys()))
        sys.exit(1)

    # Find .SHP file
    src_base = os.path.join(os.path.dirname(__file__),
                            '../../SpaceHarrierGSSource/Space.Harrier')
    default_path = os.path.join(src_base, SHP_PATHS[shape_name])

    shp_path = sys.argv[2] if len(sys.argv) > 2 else default_path
    if not os.path.exists(shp_path):
        print(f"SHP file not found: {shp_path}")
        sys.exit(1)

    output = sys.argv[3] if len(sys.argv) > 3 else f"{shape_name}.png"

    with open(shp_path, 'rb') as f:
        data = f.read()

    table = SPRITE_TABLES[shape_name]
    print(f"Shape: {shape_name} ({len(table)} sprites, {len(data)} bytes)")

    # Export sprite sheet
    sheet = make_sprite_sheet(data, table, scale=2)
    if sheet:
        sheet.save(output)
        print(f"Sprite sheet saved: {output}")

    # Also export individual sprites
    ind_dir = f"{shape_name}_sprites"
    export_individual(data, table, shape_name, ind_dir, scale=2)


if __name__ == '__main__':
    main()
