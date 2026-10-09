#!/usr/bin/env python3
"""Pack the generated PNG icon sizes into a macOS ICNS container."""

import struct
import sys
from pathlib import Path


ICON_CHUNKS = (
    ("icp4", "icon_16x16.png", 16),
    ("icp5", "icon_16x16@2x.png", 32),
    ("icp6", "icon_32x32@2x.png", 64),
    ("ic07", "icon_128x128.png", 128),
    ("ic08", "icon_128x128@2x.png", 256),
    ("ic09", "icon_256x256@2x.png", 512),
    ("ic10", "icon_512x512@2x.png", 1024),
)


def png_dimensions(data: bytes, path: Path) -> tuple[int, int]:
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"{path} is not a valid PNG")
    return struct.unpack(">II", data[16:24])


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make_icns.py ICONSET_DIR OUTPUT.icns")

    iconset = Path(sys.argv[1])
    output = Path(sys.argv[2])
    chunks = []
    for chunk_type, filename, expected_size in ICON_CHUNKS:
        path = iconset / filename
        png = path.read_bytes()
        dimensions = png_dimensions(png, path)
        if dimensions != (expected_size, expected_size):
            raise ValueError(f"{path} is {dimensions[0]}x{dimensions[1]}, expected {expected_size}x{expected_size}")
        chunks.append(chunk_type.encode("ascii") + struct.pack(">I", len(png) + 8) + png)

    payload = b"".join(chunks)
    output.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
    print(f"ICNS generated: {output}")


if __name__ == "__main__":
    main()
