"""Pixel-diff two runs of fx_snapshot.tscn / prop_art_snapshot.tscn.

    py solatro/Tools/snapshot_diff.py save          # stash the CURRENT PNGs as the baseline
    py solatro/Tools/snapshot_diff.py diff          # re-run the scene first, then compare

WHY THIS EXISTS. FX_HANDOFF's standing rule is "judge fire by EYE, never by counting columns" — two
rejected builds were reported as successes by an instrument that counted. That rule is right for a
change that is SUPPOSED to alter the picture. It is the wrong instrument for the other kind: an
optimisation that must alter NOTHING, where the only honest claim is "byte-identical", and where an
eye is far too generous.

Used 2026-07-29 to land the fire shader's empty-quad rejection and the off-screen uniform skip: both
came back identical across all 18 panels, which is what made "this cannot have changed a pixel"
a measurement rather than an argument. Run `save` on the build you trust, make the change, re-run the
snapshot scene, run `diff`.

⚠ It proves two RUNS agree, not that either is correct. A change that is meant to look different
still has to be looked at.

⚠ EVERY HARNESS THAT WRITES PANELS IS COVERED, and for a while only one was. This read
`fx_snapshots` alone while the docstring above claimed the prop harness too — so an optimisation
landed on the props, or on the seam, came back "18 of 18 identical" having compared nothing about
them. `fx_behind` matters most of the three here: it is the only harness that shows where flame meets
art, which is exactly what a mask change moves. A missing directory is reported, never skipped
silently — that is the same lesson as `_bbox` below.
"""
import os
import shutil
import sys

from PIL import Image, ImageChops

ROOT = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Solatro")
# Every scene that writes reviewable panels. Keep in step with the OUT_DIR constants in
# Tests/Visual/{fx_snapshot,prop_art_snapshot,fx_behind}.gd.
SETS = ("fx_snapshots", "prop_art_snapshots", "fx_behind")

# PANELS THAT DIFFER RUN TO RUN ON UNCHANGED CODE. Reported, never counted — a diff that buries one
# real regression under four known ones is a diff nobody reads, and silently DROPPING them is the
# `_bbox` mistake again in the other direction.
#
# Measured 2026-07-30, two consecutive runs of an unchanged build with the per-host seed pinned:
#   02_fire_rotation      12392 px    ROTATED host
#   05f_ball_rotation      1035 px    ROTATED host
#   behind_prop_turned    15506 px    ROTATED host
#   09_embers              1159 px    embers are randomised BY DESIGN (FxAttachment._emit_embers)
# Every panel with an upright host was byte-identical, in all three sets. The rotated-host
# phenomenon is the one `fx_snapshot.gd`'s header has warned about since 2026-07-27 and its cause is
# still unknown — its stated one (screen-space `fx_bayer(FRAGCOORD.xy)`) stopped applying when the
# dither moved onto the FX pixel grid, and the flakiness did not go with it.
#
# ⚠ ADDING A NAME HERE IS GIVING UP ON DIFFING THAT PANEL. Do it only with two runs of an UNCHANGED
# build to point at, as above.
NOISY = ("02_fire_rotation.png", "05f_ball_rotation.png", "behind_prop_turned.png",
         "09_embers.png")


def _dirs():
    """(shots, baseline) per set, with the missing ones named rather than dropped."""
    for name in SETS:
        shots = os.path.join(ROOT, name)
        if not os.path.isdir(shots):
            print("  NO PANELS  %s (run its scene first)" % name)
            continue
        yield name, shots, os.path.join(shots, "_baseline")


def save() -> int:
    total = 0
    for name, shots, base in _dirs():
        os.makedirs(base, exist_ok=True)
        n = 0
        for entry in sorted(os.listdir(shots)):
            if not entry.endswith(".png"):
                continue
            shutil.copy2(os.path.join(shots, entry), os.path.join(base, entry))
            n += 1
        print("baseline: %d panels saved from %s" % (n, name))
        total += n
    print("%d panels in total" % total)
    return 0


def _bbox(d):
    """The bounding box of everything that changed, across EVERY channel.

    ⚠ NOT `d.getbbox()`, AND THAT ONE-LINE DIFFERENCE MADE THIS TOOL LIE. On an RGBA image Pillow
    trims by the ALPHA channel alone (measured on Pillow 9.5: two opaque images differing only in RED
    return `getbbox() is None`), and every panel these harnesses write is opaque edge to edge — so
    `diff` reported "identical" for ANY change that did not move alpha, which is every colour change
    there is. Found 2026-07-29 by blanking the card mask deliberately: the fire vanished from four
    panels and the tool still said 20 of 20 identical.

    ⚠ SO EVERY EARLIER "18/18 PANELS BYTE-IDENTICAL" CLAIM IN FX_HANDOFF IS VACUOUS — §0d's `min_half`
    and §6a's two changes were all landed on this instrument. Splitting the bands first and taking each
    one's own bbox is honest: a single-band image has no alpha to trim by.
    """
    box = None
    for band in d.split():
        b = band.getbbox()
        if b is None:
            continue
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]),
                                     max(box[2], b[2]), max(box[3], b[3]))
    return box


def diff() -> int:
    bad = total = seen = noisy = 0
    for name, shots, base in _dirs():
        if not os.path.isdir(base):
            print("  NO BASELINE %s — run `save` on a build you trust first" % name)
            bad += 1
            continue
        seen += 1
        print("  --- %s ---" % name)
        for entry in sorted(os.listdir(base)):
            if not entry.endswith(".png"):
                continue
            total += 1
            new = os.path.join(shots, entry)
            if not os.path.exists(new):
                print("  MISSING    %s" % entry)
                bad += 1
                continue
            a = Image.open(os.path.join(base, entry)).convert("RGBA")
            b = Image.open(new).convert("RGBA")
            if a.size != b.size:
                print("  SIZE DIFF  %s  %s vs %s" % (entry, a.size, b.size))
                bad += 1
                continue
            d = ImageChops.difference(a, b)
            box = _bbox(d)
            if box is None:
                print("  identical  %s" % entry)
                continue
            data = list(d.getdata())
            px = sum(1 for p in data if p != (0, 0, 0, 0))
            worst = max(max(p) for p in data)
            if entry in NOISY:
                print("  noisy      %s  %d px (known: differs on unchanged code)" % (entry, px))
                noisy += 1
                continue
            print("  DIFFER     %s  %d px, max channel delta %d, bbox %s"
                  % (entry, px, worst, box))
            bad += 1
    if seen == 0:
        print("\nnothing compared — no baseline anywhere")
        return 2
    print("\n%d of %d comparable panels differ (%d known-noisy skipped, %d of %d sets compared)"
          % (bad, total - noisy, noisy, seen, len(SETS)))
    return 1 if bad else 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "diff"
    sys.exit(save() if mode == "save" else diff())
