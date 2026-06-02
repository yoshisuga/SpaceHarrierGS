#!/usr/bin/env python3
"""Convert FTA Space Harrier MOUNT (mountain backdrop) to PNG.

Usage:
    python3 mount2png.py [mount_file] [output.png]

    mount_file: path to MOUNT binary (default: looks in SpaceHarrierGSSource)
    output.png: output path (default: mount.png)

The MOUNT file contains two 14-row frames (for sub-pixel parallax scrolling).
Each frame is 256 bytes/row (512 pixels wide, wrapping for horizontal scroll).
Frame 2 is shifted 1 pixel right relative to Frame 1.

Output: a PNG showing both frames stacked vertically, at 2x scale.
You can edit Frame 1 in GIMP; the converter will auto-generate Frame 2.
"""

import sys
import os
from PIL import Image

# Game palette (same as shp2png.py)
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
BYTES_PER_ROW = 256    # 512 pixels wide
FRAME_SIZE = ROWS * BYTES_PER_ROW  # 3584 bytes
TOTAL_SIZE = FRAME_SIZE * 2        # 7168 bytes


def decode_frame(data, frame_offset):
    """Decode one frame of mountain data to pixel array."""
    pixels = []
    for row in range(ROWS):
        row_pixels = []
        for col in range(BYTES_PER_ROW):
            byte = data[frame_offset + row * BYTES_PER_ROW + col]
            row_pixels.append((byte >> 4) & 0x0F)
            row_pixels.append(byte & 0x0F)
        pixels.append(row_pixels)
    return pixels


def pixels_to_image(pixels, scale=2):
    """Convert pixel array to PIL Image."""
    h = len(pixels)
    w = len(pixels[0])
    img = Image.new('RGB', (w * scale, h * scale))

    for y, row in enumerate(pixels):
        for x, idx in enumerate(row):
            rgb = PALETTE.get(idx, (0, 0, 0))
            for sy in range(scale):
                for sx in range(scale):
                    img.putpixel((x * scale + sx, y * scale + sy), rgb)
    return img


def main():
    src_base = os.path.join(os.path.dirname(__file__),
                            '../../SpaceHarrierGSSource/Space.Harrier')
    default_path = os.path.join(src_base, 'MOUNT')

    mount_path = sys.argv[1] if len(sys.argv) > 1 else default_path
    output = sys.argv[2] if len(sys.argv) > 2 else 'mount.png'

    if not os.path.exists(mount_path):
        print(f"MOUNT file not found: {mount_path}")
        sys.exit(1)

    with open(mount_path, 'rb') as f:
        data = f.read()

    print(f"MOUNT file: {len(data)} bytes")
    if len(data) < TOTAL_SIZE:
        print(f"Warning: expected {TOTAL_SIZE} bytes, got {len(data)}")

    scale = 2

    # Decode both frames
    frame1 = decode_frame(data, 0)
    frame2 = decode_frame(data, FRAME_SIZE)

    img1 = pixels_to_image(frame1, scale)
    img2 = pixels_to_image(frame2, scale)

    # Stack vertically with a separator
    gap = 4
    combined = Image.new('RGB', (img1.width, img1.height + gap + img2.height), (64, 64, 64))
    combined.paste(img1, (0, 0))
    combined.paste(img2, (0, img1.height + gap))
    combined.save(output)
    print(f"Saved {output} ({combined.width}x{combined.height})")
    print(f"  Frame 1 (top):    {img1.width}x{img1.height} — edit this one")
    print(f"  Frame 2 (bottom): {img2.width}x{img2.height} — auto-generated on re-import")

    # Also export just frame 1 for editing
    frame1_path = output.replace('.png', '_frame1.png')
    img1.save(frame1_path)
    print(f"  Frame 1 only: {frame1_path}")


if __name__ == '__main__':
    main()
