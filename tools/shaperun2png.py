#!/usr/bin/env python3
"""Export all 19 Harrier frames from SHAPE.RUN to individual PNGs.

Usage:
    python3 shaperun2png.py [shape_run_file] [output_dir]

    shape_run_file: path to SHAPE.RUN (default: SpaceHarrierGSSource)
    output_dir:     output directory (default: harrier_sprites/)

SHAPE.RUN format:
    - 4-byte header at start of file
    - 19 frames, each 48 rows x 16 bytes (32 pixels wide, 4bpp SHR)
    - 4-byte header between each frame
"""

import sys
import os
from PIL import Image

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

# Magenta for transparent (color 0)
TRANSPARENT = (255, 0, 255)

NUM_FRAMES = 19
ROWS = 48
COLS_BYTES = 16  # 32 pixels wide
HEADER_SIZE = 4
FRAME_DATA = ROWS * COLS_BYTES  # 768 bytes


def decode_frame(data, offset):
    """Decode one frame to pixel indices."""
    pixels = []
    for row in range(ROWS):
        row_pixels = []
        for col in range(COLS_BYTES):
            byte = data[offset + row * COLS_BYTES + col]
            row_pixels.append((byte >> 4) & 0x0F)
            row_pixels.append(byte & 0x0F)
        pixels.append(row_pixels)
    return pixels


def pixels_to_image(pixels, scale=2):
    """Convert pixel array to PIL Image with transparency shown as magenta."""
    h = len(pixels)
    w = len(pixels[0])
    img = Image.new('RGB', (w * scale, h * scale))

    for y, row in enumerate(pixels):
        for x, idx in enumerate(row):
            if idx == 0:
                rgb = TRANSPARENT
            else:
                rgb = PALETTE.get(idx, (0, 0, 0))
            for sy in range(scale):
                for sx in range(scale):
                    img.putpixel((x * scale + sx, y * scale + sy), rgb)
    return img


def main():
    src_base = os.path.join(os.path.dirname(__file__),
                            '../../SpaceHarrierGSSource/Space.Harrier')
    default_path = os.path.join(src_base, 'SHAPE.RUN')

    shape_path = sys.argv[1] if len(sys.argv) > 1 else default_path
    output_dir = sys.argv[2] if len(sys.argv) > 2 else 'harrier_sprites'

    if not os.path.exists(shape_path):
        print(f"SHAPE.RUN not found: {shape_path}")
        sys.exit(1)

    with open(shape_path, 'rb') as f:
        data = f.read()

    print(f"SHAPE.RUN: {len(data)} bytes")

    os.makedirs(output_dir, exist_ok=True)

    offset = HEADER_SIZE  # skip initial 4-byte header
    scale = 3

    for i in range(NUM_FRAMES):
        if offset + FRAME_DATA > len(data):
            print(f"  Frame {i:02d}: not enough data (offset {offset})")
            break

        pixels = decode_frame(data, offset)
        img = pixels_to_image(pixels, scale)

        out_path = os.path.join(output_dir, f'harrier_{i:02d}.png')
        img.save(out_path)
        print(f"  Frame {i:02d}: offset 0x{offset:04X} -> {out_path}")

        offset += FRAME_DATA + HEADER_SIZE  # advance past data + next header

    # Also make a contact sheet
    sheet_cols = 8
    sheet_rows = (NUM_FRAMES + sheet_cols - 1) // sheet_cols
    pw = COLS_BYTES * 2 * scale  # pixel width per frame
    ph = ROWS * scale
    gap = 4
    sheet = Image.new('RGB', (
        sheet_cols * pw + (sheet_cols - 1) * gap,
        sheet_rows * ph + (sheet_rows - 1) * gap
    ), (64, 64, 64))

    offset = HEADER_SIZE
    for i in range(NUM_FRAMES):
        if offset + FRAME_DATA > len(data):
            break
        pixels = decode_frame(data, offset)
        img = pixels_to_image(pixels, scale)
        col = i % sheet_cols
        row = i // sheet_cols
        sheet.paste(img, (col * (pw + gap), row * (ph + gap)))
        offset += FRAME_DATA + HEADER_SIZE

    sheet_path = os.path.join(output_dir, 'harrier_sheet.png')
    sheet.save(sheet_path)
    print(f"\n  Contact sheet: {sheet_path} ({sheet.width}x{sheet.height})")


if __name__ == '__main__':
    main()
