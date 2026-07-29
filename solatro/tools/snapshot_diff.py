"""Pixel-diff two runs of fx_snapshot.tscn / prop_art_snapshot.tscn.

    py solatro/tools/snapshot_diff.py save          # stash the CURRENT PNGs as the baseline
    py solatro/tools/snapshot_diff.py diff          # re-run the scene first, then compare

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
"""
import os
import shutil
import sys

from PIL import Image, ImageChops

SHOTS = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Solatro\fx_snapshots")
BASE = os.path.join(SHOTS, "_baseline")


def save() -> int:
    os.makedirs(BASE, exist_ok=True)
    n = 0
    for name in sorted(os.listdir(SHOTS)):
        if not name.endswith(".png"):
            continue
        shutil.copy2(os.path.join(SHOTS, name), os.path.join(BASE, name))
        n += 1
    print("baseline: %d panels saved to %s" % (n, BASE))
    return 0


def diff() -> int:
    if not os.path.isdir(BASE):
        print("no baseline — run `save` on a build you trust first")
        return 2
    bad = total = 0
    for name in sorted(os.listdir(BASE)):
        if not name.endswith(".png"):
            continue
        total += 1
        new = os.path.join(SHOTS, name)
        if not os.path.exists(new):
            print("  MISSING    %s" % name)
            bad += 1
            continue
        a = Image.open(os.path.join(BASE, name)).convert("RGBA")
        b = Image.open(new).convert("RGBA")
        if a.size != b.size:
            print("  SIZE DIFF  %s  %s vs %s" % (name, a.size, b.size))
            bad += 1
            continue
        d = ImageChops.difference(a, b)
        if d.getbbox() is None:
            print("  identical  %s" % name)
            continue
        px = sum(1 for p in d.getdata() if p != (0, 0, 0, 0))
        worst = max(max(p) for p in d.getdata())
        print("  DIFFER     %s  %d px, max channel delta %d, bbox %s"
              % (name, px, worst, d.getbbox()))
        bad += 1
    print("\n%d of %d panels differ" % (bad, total))
    return 1 if bad else 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "diff"
    sys.exit(save() if mode == "save" else diff())
