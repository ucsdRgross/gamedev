#!/usr/bin/env python3
"""Bake the FX palette ramps (Shaders/Styles/*.png) that fire.gdshader samples as u_ramp.

The ramp is the WHOLE palette of an effect: u = heat (0 at the flame's cold outer edge, 1 at its
core), v = normalized stack level. Colour-per-stack is therefore one texture coordinate rather
than a second set of colour uniforms plus interpolation code (owner ruling 14), and the number of
bands is however many hard columns the image has rather than a fixed four.

Hard columns are the point: the banding is what reads as pixel art. The shader samples with
filter_nearest, so every column is a flat band with a crisp edge, and fx_bayer breaks that edge
without softening it.

Run: py solatro/tools/make_fx_ramp.py     (stdlib only — no PIL, no numpy)
Then reimport the project so Godot picks the .png up.
"""

import struct
import zlib
from pathlib import Path

WIDTH = 64      # heat resolution: plenty of room for the band edges to land where they should
HEIGHT = 16     # stack levels; sampled with filter_nearest, so 16 distinct looks from 1 to level_ref

# One band table per END of the level axis; every row between is interpolated. Each entry is
# (threshold, r, g, b, a) — the colour used from that threshold up to the next one. The first
# entry is the transparent cut: below it the flame simply is not there, which is what gives the
# tendrils their ragged outline.
COLD = [                    # v = 0: a few stacks. A small, deep, ordinary fire.
    (0.00, 0, 0, 0, 0),
    (0.18, 92, 20, 12, 255),
    (0.35, 190, 48, 20, 255),
    (0.55, 240, 120, 28, 255),
    (0.78, 255, 205, 90, 255),
]
HOT = [                     # v = 1: level_ref stacks. Terrifying, not merely brighter.
    (0.00, 0, 0, 0, 0),
    (0.14, 200, 60, 20, 255),
    (0.30, 255, 150, 40, 255),
    (0.50, 255, 236, 140, 255),
    (0.74, 235, 245, 255, 255),
]


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def band_colour(bands: list, heat: float) -> tuple:
    """The band `heat` falls in. Hard steps, never a gradient — that is the whole design."""
    chosen = bands[0]
    for entry in bands:
        if heat >= entry[0]:
            chosen = entry
    return chosen[1:]


def row(v: float) -> bytes:
    """One stack level: the two band tables blended at `v`, then sampled across the heat axis."""
    blended = []
    for cold, hot in zip(COLD, HOT):
        blended.append(tuple(lerp(cold[i], hot[i], v) for i in range(5)))
    out = bytearray()
    for x in range(WIDTH):
        heat = (x + 0.5) / WIDTH
        out += bytes(int(round(c)) for c in band_colour(blended, heat))
    return bytes(out)


def write_png(path: Path, rows: list) -> None:
    raw = b"".join(b"\x00" + r for r in rows)      # filter type 0 on every scanline

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 6, 0, 0, 0)   # 8-bit RGBA
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "Shaders" / "Styles" / "fire_ramp.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    write_png(out, [row(y / (HEIGHT - 1)) for y in range(HEIGHT)])
    print("wrote %s (%dx%d)" % (out, WIDTH, HEIGHT))


if __name__ == "__main__":
    main()
