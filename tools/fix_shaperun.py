#!/usr/bin/env python3
"""Remap color $0 -> $1 in SHAPE.RUN pixel data.

Color $0 is the Harrier's outline (drawn opaquely by compiled sprites).
In sky palettes, color $0 = sky gradient, making the outline invisible.
Color $1 = black in ALL palettes (set for sidebar), so the outline stays visible.

SHAPE.RUN format: 4-byte header, then 19 frames of 768 bytes each,
with 4-byte headers between frames.
"""

import sys
import os

NUM_FRAMES = 19
HEADER_SIZE = 4
FRAME_DATA = 48 * 16  # 768 bytes per frame

def main():
    src_base = os.path.join(os.path.dirname(__file__),
                            '../../SpaceHarrierGSSource/Space.Harrier')
    src_path = os.path.join(src_base, 'SHAPE.RUN')
    dst_path = src_path  # overwrite in place

    with open(src_path, 'rb') as f:
        data = bytearray(f.read())

    print(f"SHAPE.RUN: {len(data)} bytes")

    changed = 0
    for frame in range(NUM_FRAMES):
        offset = HEADER_SIZE + frame * (FRAME_DATA + HEADER_SIZE)
        for i in range(FRAME_DATA):
            byte = data[offset + i]
            hi = (byte >> 4) & 0x0F
            lo = byte & 0x0F
            new_hi = 1 if hi == 0 else hi
            new_lo = 1 if lo == 0 else lo
            new_byte = (new_hi << 4) | new_lo
            if new_byte != byte:
                data[offset + i] = new_byte
                changed += 1

    print(f"Remapped {changed} bytes (color $0 -> $1)")

    with open(dst_path, 'wb') as f:
        f.write(data)
    print(f"Saved: {dst_path}")


if __name__ == '__main__':
    main()
