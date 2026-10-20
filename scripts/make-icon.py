#!/usr/bin/env python3
"""Render the omp-ui source icon (1024x1024 PNG) with no image dependencies."""

import struct
import zlib

SIZE = 1024
BG = (16, 19, 23, 255)
RING = (242, 169, 60, 255)
CORE = (242, 169, 60, 255)

RADIUS = 224
RING_OUTER = 300
RING_INNER = 252
DOT_RADIUS = 74


def rounded_rect_alpha(x: float, y: float) -> bool:
    """Inside a rounded square with corner radius RADIUS."""
    cx = min(max(x, RADIUS), SIZE - RADIUS)
    cy = min(max(y, RADIUS), SIZE - RADIUS)
    dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= RADIUS * RADIUS


def ring_alpha(x: float, y: float) -> bool:
    dx, dy = x - SIZE / 2, y - SIZE / 2
    d = (dx * dx + dy * dy) ** 0.5
    return RING_INNER <= d <= RING_OUTER


def dot_alpha(x: float, y: float) -> bool:
    dx, dy = x - SIZE / 2, y - SIZE / 2
    return dx * dx + dy * dy <= DOT_RADIUS * DOT_RADIUS


def blend(dst: tuple, src: tuple) -> tuple:
    """Source-over alpha compositing."""
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    out_a = sa / 255 + da / 255 * (1 - sa / 255)
    if out_a == 0:
        return (0, 0, 0, 0)
    out_r = (sr * sa / 255 + dr * da / 255 * (1 - sa / 255)) / out_a
    out_g = (sg * sa / 255 + dg * da / 255 * (1 - sa / 255)) / out_a
    out_b = (sb * sa / 255 + db * da / 255 * (1 - sa / 255)) / out_a
    return (int(out_r), int(out_g), int(out_b), int(out_a * 255))


def build_rows() -> list[bytes]:
    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            px = (0, 0, 0, 0)
            if rounded_rect_alpha(x + 0.5, y + 0.5):
                px = BG
            if ring_alpha(x + 0.5, y + 0.5):
                px = blend(px, RING)
            if dot_alpha(x + 0.5, y + 0.5):
                px = blend(px, CORE)
            row += bytes(px)
        rows.append(bytes(row))
    return rows


def chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def main() -> None:
    rows = build_rows()
    raw = b"".join(b"\x00" + row for row in rows)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    with open("app-icon.png", "wb") as handle:
        handle.write(png)
    print(f"wrote app-icon.png ({len(png)} bytes)")


if __name__ == "__main__":
    main()
