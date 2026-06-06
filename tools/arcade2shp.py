#!/usr/bin/env python3
"""Convert an arcade sprite image to IIgs depth-scaled sprites.

Usage:
    python3 arcade2shp.py <source_image> [--type tree|ship|rock|bush] [--output dir]

Takes a source sprite image (any size), removes the background, quantizes
to the IIgs 16-color game palette, and scales to all depth levels matching
the specified shape type's dimensions.

Outputs individual PNGs for review plus a packed .SHP binary.
"""

import sys
import os
import argparse
from PIL import Image

# IIgs game palette — usable colors for sprites
# Color $0: avoid (sky gradient in sky palettes)
# Color $4: avoid (sky gradient in sky palettes)
# Color $E: transparent (auto-masked by compiled sprite engine)
PALETTE = {
    0x1: (0, 0, 0),         # black (outlines)
    0x2: (68, 102, 102),     # blue-grey dark
    0x3: (68, 68, 153),      # blue
    0x5: (0, 153, 34),       # green
    0x6: (102, 68, 0),       # red-brown
    0x7: (102, 153, 153),    # blue-grey light
    0x8: (221, 153, 68),     # orange/skin
    0x9: (255, 221, 68),     # yellow
    0xA: (221, 68, 0),       # red-orange
    0xB: (102, 153, 221),    # medium blue
    0xC: (0, 221, 68),       # bright green
    0xD: (0, 102, 34),       # dark green
    0xF: (255, 255, 255),    # white
}

TRANSPARENT_IDX = 0xE

# Depth size tables: list of (rows, cols_bytes) per depth level
# cols_bytes × 2 = pixel width
SIZE_TABLES = {
    'tree': [
        (121, 32), (80, 22), (60, 16), (48, 12), (40, 10), (33, 10),
        (29, 8), (25, 8), (23, 6), (20, 6), (19, 6), (17, 6),
        (17, 4), (16, 4), (15, 4), (14, 4),
    ],
    'enemy': [
        (96, 30), (72, 24), (56, 18), (42, 14), (34, 12), (28, 10),
        (23, 8), (19, 8), (16, 6), (14, 6), (11, 6), (9, 4),
        (8, 4), (6, 4), (5, 4),
    ],
    'ship': [
        (35, 46), (22, 30), (16, 24), (13, 18), (10, 16), (9, 14),
        (7, 12), (6, 10), (6, 8), (5, 8), (4, 8), (4, 8),
        (4, 6), (3, 6), (3, 6),
    ],
    'rock': [
        (29, 38), (20, 24), (14, 18), (11, 16), (10, 14), (9, 12),
        (7, 10), (6, 10),
    ],
    'bush': [
        (29, 36), (18, 24), (14, 18), (11, 14), (9, 12), (8, 10),
        (7, 10), (6, 8), (5, 8), (5, 6), (4, 6), (4, 6),
        (4, 6), (2, 6),
    ],
}


def color_distance(c1, c2):
    """Weighted Euclidean distance (human perception)."""
    dr = c1[0] - c2[0]
    dg = c1[1] - c2[1]
    db = c1[2] - c2[2]
    return dr*dr*3 + dg*dg*4 + db*db*2  # weight green highest


def nearest_palette_color(r, g, b):
    """Find closest IIgs palette index for an RGB color."""
    best_idx = 0x1
    best_dist = float('inf')
    for idx, pal_rgb in PALETTE.items():
        d = color_distance((r, g, b), pal_rgb)
        if d < best_dist:
            best_dist = d
            best_idx = idx
    return best_idx


def detect_background(img):
    """Detect background color from corners."""
    w, h = img.size
    corners = [img.getpixel((0, 0)), img.getpixel((w-1, 0)),
               img.getpixel((0, h-1)), img.getpixel((w-1, h-1))]
    # Use most common corner color
    from collections import Counter
    bg = Counter(corners).most_common(1)[0][0]
    return bg[:3]  # strip alpha if present


def remove_background(img, bg_color, threshold=80):
    """Replace background pixels with transparent marker."""
    pixels = img.load()
    w, h = img.size
    result = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    rpix = result.load()
    for y in range(h):
        for x in range(w):
            p = pixels[x, y]
            r, g, b = p[0], p[1], p[2]
            dr = r - bg_color[0]
            dg = g - bg_color[1]
            db = b - bg_color[2]
            dist = dr*dr + dg*dg + db*db
            if dist < threshold * threshold:
                rpix[x, y] = (0, 0, 0, 0)  # transparent
            else:
                rpix[x, y] = (r, g, b, 255)
    return result


def crop_to_content(img):
    """Crop image to non-transparent bounding box."""
    bbox = img.getbbox()
    if bbox:
        return img.crop(bbox)
    return img


def quantize_frame(img, target_w, target_h):
    """Scale image to target size and quantize to IIgs palette.
    Returns list of rows, each row is list of palette indices.
    """
    # Scale with high-quality resampling
    scaled = img.resize((target_w, target_h), Image.LANCZOS)
    pixels = scaled.load()

    result = []
    for y in range(target_h):
        row = []
        for x in range(target_w):
            r, g, b, a = pixels[x, y]
            if a < 128:
                row.append(TRANSPARENT_IDX)
            else:
                row.append(nearest_palette_color(r, g, b))
        result.append(row)
    return result


def frame_to_image(frame, scale=2):
    """Convert palette-indexed frame to PNG for preview."""
    display_pal = dict(PALETTE)
    display_pal[TRANSPARENT_IDX] = (170, 170, 85)  # sage for transparent
    display_pal[0x0] = (0, 0, 0)

    h = len(frame)
    w = len(frame[0]) if frame else 0
    img = Image.new('RGB', (w * scale, h * scale))
    for y, row in enumerate(frame):
        for x, idx in enumerate(row):
            if idx == TRANSPARENT_IDX:
                rgb = (255, 0, 255)  # magenta = transparent
            else:
                rgb = display_pal.get(idx, (0, 0, 0))
            for sy in range(scale):
                for sx in range(scale):
                    img.putpixel((x * scale + sx, y * scale + sy), rgb)
    return img


def pack_shp(frames, sizes):
    """Pack frames into .SHP binary format matching FTA's layout.

    Format: 4-byte file header + raw pixel data for all frames.
    No per-frame headers — the game reads dimensions from Tbl_* tables.
    The game skips the file header (+4 in shape address equates).

    Returns (shp_bytes, offsets_list) where offsets are relative to after header.
    """
    # 4-byte file header: type byte, zero, rows of first frame, cols of first frame
    header = bytearray([0x01, 0x00, sizes[0][0] & 0xFF, sizes[0][1] & 0xFF])
    pixel_data = bytearray()
    offsets = []

    for i, (frame, (rows, cols_bytes)) in enumerate(zip(frames, sizes)):
        px_w = cols_bytes * 2
        offsets.append(len(pixel_data))
        # Raw pixel data: pack 2 pixels per byte
        for row in frame:
            for x in range(0, px_w, 2):
                hi = row[x] if x < len(row) else TRANSPARENT_IDX
                lo = row[x+1] if x+1 < len(row) else TRANSPARENT_IDX
                pixel_data.append(((hi & 0xF) << 4) | (lo & 0xF))

    return bytes(header + pixel_data), offsets


def main():
    parser = argparse.ArgumentParser(description='Convert arcade sprite to IIgs depth-scaled sprites')
    parser.add_argument('source', help='Source sprite image')
    parser.add_argument('--type', '-t', default='tree', choices=SIZE_TABLES.keys(),
                        help='Shape type for depth sizes (default: tree)')
    parser.add_argument('--output', '-o', default=None,
                        help='Output directory (default: <source_name>_iigs/)')
    parser.add_argument('--bg-threshold', type=int, default=100,
                        help='Background detection threshold (default: 100)')
    parser.add_argument('--bg-color', default=None,
                        help='Background color as R,G,B (e.g. "65,7,245"). Auto-detect if omitted.')
    parser.add_argument('--scale', type=int, default=2,
                        help='Preview PNG scale factor (default: 2)')
    parser.add_argument('--shp', default=None,
                        help='Output .SHP filename (default: <name>.SHP)')
    args = parser.parse_args()

    # Load source
    src = Image.open(args.source).convert('RGBA')
    print(f"Source: {src.size[0]}x{src.size[1]} pixels")

    # Detect and remove background
    if args.bg_color:
        bg = tuple(int(x) for x in args.bg_color.split(','))
    else:
        bg = detect_background(src)
    print(f"Background color: RGB({bg[0]}, {bg[1]}, {bg[2]})")
    src = remove_background(src, bg, args.bg_threshold)
    src = crop_to_content(src)
    print(f"Cropped to content: {src.size[0]}x{src.size[1]} pixels")

    # Get size table
    sizes = SIZE_TABLES[args.type]
    print(f"Shape type: {args.type} ({len(sizes)} depth levels)")

    # Output directory
    base_name = os.path.splitext(os.path.basename(args.source))[0]
    out_dir = args.output or f"{base_name}_iigs"
    os.makedirs(out_dir, exist_ok=True)

    # Generate each depth level
    frames = []
    for i, (rows, cols_bytes) in enumerate(sizes):
        px_w = cols_bytes * 2
        frame = quantize_frame(src, px_w, rows)
        frames.append(frame)

        # Save preview PNG
        img = frame_to_image(frame, args.scale)
        path = os.path.join(out_dir, f"depth_{i:02d}_{px_w}x{rows}.png")
        img.save(path)
        print(f"  depth {i:2d}: {px_w:3d}x{rows:3d} -> {path}")

    # Save sprite sheet (all depths side by side)
    gap = 4
    total_w = sum(len(f[0]) for f in frames) * args.scale + gap * (len(frames) - 1)
    max_h = max(len(f) for f in frames) * args.scale
    sheet = Image.new('RGB', (total_w, max_h), (64, 64, 64))
    x = 0
    for frame in frames:
        img = frame_to_image(frame, args.scale)
        y = max_h - img.height  # bottom-align
        sheet.paste(img, (x, y))
        x += img.width + gap
    sheet_path = os.path.join(out_dir, "sprite_sheet.png")
    sheet.save(sheet_path)
    print(f"Sprite sheet: {sheet_path}")

    # Pack .SHP binary
    shp_name = args.shp or f"{base_name.upper()}.SHP"
    shp_path = os.path.join(out_dir, shp_name)
    shp_data, offsets = pack_shp(frames, sizes)
    with open(shp_path, 'wb') as f:
        f.write(shp_data)
    print(f"SHP binary: {shp_path} ({len(shp_data)} bytes)")

    # Print Merlin32 table for copy-paste into App.Main.s
    print(f"\n; --- Merlin32 frame table (paste into App.Main.s) ---")
    print(f"Nb_Robot        equ  {len(sizes)}")
    print(f"Tbl_Robot")
    for i, ((rows, cols_bytes), off) in enumerate(zip(sizes, offsets)):
        print(f"            da     ${off:04X},${rows:02X},${cols_bytes:02X}"
              f"    ; depth {i}: {cols_bytes*2}x{rows}")

    print(f"\nDone! Review PNGs in {out_dir}/, edit in GIMP if needed.")
    print(f"Magenta = transparent (color $E)")


if __name__ == '__main__':
    main()
