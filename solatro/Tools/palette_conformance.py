#!/usr/bin/env python3
"""Report every rendered pixel that is NOT an entry of the universal palette.

This is the only check that actually measures "universal palette" end to end: it reads the PNGs the
snapshot scenes captured and compares each pixel against Assets/CircusCrayon.png. Before T21 it
reported the fire ramp's 64 off-palette colours; after it, the survivors should be BLENDS.

It is a REVIEW INSTRUMENT, not a pass/fail gate, and deliberately not wired into all_tests. FX quads
are alpha-blended over the snapshot backdrop, so a translucent flame pixel is legitimately a mix of a
palette entry and the grey behind it — no amount of correct plumbing makes those exact entries. What
the report is for is the LARGE clusters: a solid area of one off-palette colour means something is
still choosing its own colour instead of pointing at the palette. The headless guarantee (every
generated ramp texel is exactly an entry) lives in Tests/Engine/test_palette.gd.

Run:  py solatro/Tools/palette_conformance.py
      py solatro/Tools/palette_conformance.py --top 20 --min-count 50
Reads: %APPDATA%/Godot/app_userdata/Solatro/{fx_snapshots,prop_art_snapshots}/*.png

stdlib only — no PIL, no numpy, same rule the rest of tools/ follows.
"""

import argparse
import os
import struct
import sys
import zlib
from collections import Counter
from pathlib import Path

PALETTE_PNG = Path(__file__).resolve().parent.parent / "Assets" / "CircusCrayon.png"

# The snapshot harness draws its own chrome (SnapshotScene): a neutral backdrop, captions, card
# outlines and the ball oracle's crosses. None of it is game art, so none of it is a violation.
# Sources: SnapshotScene.BACKDROP + its caption font_color, and fx_snapshot's _Ghost geometry
# (reference outline 0.45/0.5/0.6, the dimmer outline, and the green ball oracle crosses 0.4/1.0/0.6).
HARNESS_COLOURS = {
    (23, 23, 31), (77, 77, 77),          # backdrop, at both gammas the captures use
    (191, 199, 217), (140, 144, 154),    # captions
    (134, 138, 147), (114, 117, 123), (82, 82, 83),
    (115, 128, 153),                     # #738099 — reference outline (0.45, 0.5, 0.6)
    (85, 94, 112),                       # #555e70 — the dimmer outline
    (102, 255, 153),                     # #66ff99 — ball oracle crosses (0.4, 1.0, 0.6)
}


def read_png(path):
    """(width, height, bytes_per_pixel, unfiltered_pixel_bytes) for an 8-bit RGB/RGBA PNG."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % path)
    pos, idat = 8, b""
    width = height = colour_type = 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, _depth, colour_type = struct.unpack(">IIBB", payload[:10])
        elif tag == b"IDAT":
            idat += payload
        pos += 12 + length
    bpp = {2: 3, 6: 4}.get(colour_type)
    if bpp is None:
        raise ValueError("%s: unsupported colour type %d" % (path, colour_type))

    raw = zlib.decompress(idat)
    stride = width * bpp
    out = bytearray()
    prev = bytearray(stride)
    pos = 0
    for _y in range(height):
        filter_type = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if filter_type == 1:
                line[x] = (line[x] + a) & 0xFF
            elif filter_type == 2:
                line[x] = (line[x] + b) & 0xFF
            elif filter_type == 3:
                line[x] = (line[x] + (a + b) // 2) & 0xFF
            elif filter_type == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 0xFF
        out += line
        prev = line
    return width, height, bpp, bytes(out)


def palette_entries():
    w, _h, bpp, px = read_png(PALETTE_PNG)
    return {tuple(px[i * bpp:i * bpp + 3]) for i in range(w)}


def nearest_distance(colour, entries):
    """Distance to the closest palette entry, 0-255 RGB. Small = a blend, large = a wrong colour."""
    return min(max(abs(colour[i] - e[i]) for i in range(3)) for e in entries)


def scan(path, entries, min_count):
    w, h, bpp, px = read_png(path)
    offenders = Counter()
    total = 0
    for i in range(w * h):
        off = i * bpp
        if bpp == 4 and px[off + 3] < 255:
            continue                      # translucent: blended by definition
        colour = tuple(px[off:off + 3])
        if colour in entries or colour in HARNESS_COLOURS:
            continue
        offenders[colour] += 1
        total += 1
    return w * h, total, [(c, n) for c, n in offenders.items() if n >= min_count]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", action="append", default=[],
                    help="extra directory of PNGs to scan")
    ap.add_argument("--top", type=int, default=8, help="offending colours to list per file")
    ap.add_argument("--min-count", type=int, default=10,
                    help="ignore colours appearing fewer times than this (isolated blend pixels)")
    args = ap.parse_args()

    entries = palette_entries()
    print("palette: %s (%d entries)\n" % (PALETTE_PNG.name, len(entries)))

    roots = [Path(d) for d in args.dir]
    appdata = os.environ.get("APPDATA")
    if appdata and not roots:
        base = Path(appdata) / "Godot" / "app_userdata" / "Solatro"
        roots = [base / "fx_snapshots", base / "prop_art_snapshots"]

    files = sorted(p for root in roots if root.is_dir() for p in root.glob("*.png"))
    if not files:
        print("no snapshots found — run the snapshot scenes first:")
        print("  Godot --path solatro res://Tests/Visual/fx_snapshot.tscn")
        print("  Godot --path solatro res://Tests/Visual/prop_art_snapshot.tscn")
        return 1

    grand = 0
    for path in files:
        pixels, off, clusters = scan(path, entries, args.min_count)
        grand += off
        pct = 100.0 * off / pixels if pixels else 0.0
        print("%-28s %7d off-palette of %7d (%.2f%%)" % (path.name, off, pixels, pct))
        for colour, count in sorted(clusters, key=lambda kv: -kv[1])[:args.top]:
            print("      #%02x%02x%02x  x%-6d  nearest entry %3d away" %
                  (colour[0], colour[1], colour[2], count, nearest_distance(colour, entries)))
    print("\ntotal off-palette opaque pixels: %d" % grand)
    print("Large single-colour clusters far from any entry are the real finds; small counts a few "
          "steps from an entry are edge blends.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
