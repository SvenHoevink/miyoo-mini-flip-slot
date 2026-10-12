#!/usr/bin/env python3
"""Turn a raw framebuffer page into a PNG.

The software backend writes XRGB8888 (B,G,R,X in memory). `task shot` points
slot at a plain file with SLOT_FB_SIZE and this reads page 0 back out, so the
rasteriser can be inspected without the handheld. Stdlib only, no Pillow.

usage: fb2png.py <raw> <WxH> <page> <out.png>
"""
import struct
import sys
import zlib


def main() -> int:
    if len(sys.argv) != 5:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    path, size, page, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    w, h = (int(v) for v in size.lower().split("x"))

    data = open(path, "rb").read()
    off = page * w * h * 4
    if len(data) < off + w * h * 4:
        print(f"{path}: too short for page {page} of {w}x{h}", file=sys.stderr)
        return 1

    raw = bytearray()
    lit = 0
    for y in range(h):
        raw.append(0)  # PNG filter: none
        row = data[off + y * w * 4 : off + (y + 1) * w * 4]
        for x in range(w):
            b, g, r, _ = row[x * 4 : x * 4 + 4]
            lit += bool(b or g or r)
            raw += bytes((r, g, b))

    def chunk(tag: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + tag
            + body
            + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
        )

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        + chunk(b"IEND", b"")
    )
    open(out, "wb").write(png)
    print(f"{out}: {lit}/{w * h} lit pixels ({100 * lit / (w * h):.1f}%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
