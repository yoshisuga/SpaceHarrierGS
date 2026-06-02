#!/usr/bin/env python3
"""Convert a PNG mountain backdrop back to FTA MOUNT binary format.

Usage:
    python3 png2mount.py <input.png> [output_mount]

    input.png:    PNG of Frame 1 (512px wide × 14px tall at 1x, or scaled)
    output_mount: output path (default: MOUNT)

The tool reads Frame 1 from the PNG and auto-generates Frame 2
(shifted 1 pixel right, with wrapping) for smooth parallax scrolling.

Edit workflow:
    1. Run mount2png.py to export → mount_frame1.png
    2. Edit in GIMP (keep 1024x28 at 2x, or 512x14 at 1x)
    3. Run png2mount.py mount_frame1.png MOUNT
    4. Copy MOUNT to source folder, rebuild
"""

import sys
import os
import math
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

ROWS = 14
PIXELS_PER_ROW = 512   # 256 bytes × 2 pixels/byte
BYTES_PER_ROW = 256
FRAME_SIZE = ROWS * BYTES_PER_ROW


def color_distance(c1, c2):
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(c1, c2)))


def rgb_to_index(rgb):
    r, g, b = rgb[:3]
    if r < 10 and g < 10 and b < 10:
        return 0
    best_idx = 0
    best_dist = float('inf')
    for idx in range(16):
        d = color_distance((r, g, b), PALETTE[idx])
        if d < best_dist:
            best_dist = d
            best_idx = idx
    return best_idx


def read_frame(img):
    """Read Frame 1 pixel indices from PNG. Returns 2D array [row][col] of color indices."""
    # Detect scale
    scale_x = img.width / PIXELS_PER_ROW
    scale_y = img.height / ROWS
    scale = round((scale_x + scale_y) / 2)
    if scale < 1:
        scale = 1

    print(f"  Image: {img.width}x{img.height}, detected scale: {scale}x")

    pixels = []
    for row in range(ROWS):
        row_pixels = []
        for px in range(PIXELS_PER_ROW):
            x = px * scale + scale // 2
            y = row * scale + scale // 2
            x = min(x, img.width - 1)
            y = min(y, img.height - 1)
            idx = rgb_to_index(img.getpixel((x, y)))
            row_pixels.append(idx)
        pixels.append(row_pixels)
    return pixels


def frame_to_bytes(pixels):
    """Convert pixel indices to SHR byte data."""
    data = bytearray(FRAME_SIZE)
    for row in range(ROWS):
        for col_byte in range(BYTES_PER_ROW):
            px0 = pixels[row][col_byte * 2]
            px1 = pixels[row][col_byte * 2 + 1]
            data[row * BYTES_PER_ROW + col_byte] = (px0 << 4) | px1
    return data


def shift_frame(pixels):
    """Generate Frame 2 by shifting Frame 1 right by 1 pixel (with wrap)."""
    shifted = []
    for row in pixels:
        # Shift right: last pixel wraps to first position
        shifted_row = [row[-1]] + row[:-1]
        shifted.append(shifted_row)
    return shifted


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print(__doc__)
        sys.exit(0)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else 'MOUNT'

    if not os.path.exists(input_path):
        print(f"Input file not found: {input_path}")
        sys.exit(1)

    img = Image.open(input_path).convert('RGB')
    print(f"Reading Frame 1 from {input_path}")

    frame1_pixels = read_frame(img)
    frame1_data = frame_to_bytes(frame1_pixels)

    # Auto-generate Frame 2 (1 pixel right shift)
    frame2_pixels = shift_frame(frame1_pixels)
    frame2_data = frame_to_bytes(frame2_pixels)

    mount_data = frame1_data + frame2_data

    with open(output_path, 'wb') as f:
        f.write(mount_data)

    print(f"Wrote {len(mount_data)} bytes to {output_path}")
    print(f"  Frame 1: bytes 0x0000-0x{FRAME_SIZE-1:04X}")
    print(f"  Frame 2: bytes 0x{FRAME_SIZE:04X}-0x{len(mount_data)-1:04X} (auto-shifted)")


if __name__ == '__main__':
    main()
