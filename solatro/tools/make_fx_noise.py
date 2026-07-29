#!/usr/bin/env python3
"""Bake the seamless tiling FBM the fire shader scrolls (FX_HANDOFF §0e.1).

    py solatro/tools/make_fx_noise.py

Writes `Assets/Fx/noise_fire.png` — a 128x128 greyscale, three octaves of value noise,
SEAMLESS on both axes. `fire.gdshader` samples it with `filter_nearest, repeat_enable`.

WHY A BAKED TEXTURE RATHER THAN `NoiseTexture2D`. NoiseTexture2D generates on a worker
thread at LOAD, so the first frames of a headless snapshot run can read an empty image —
a rendering test with a race in it is not a test. A committed PNG is deterministic, and
re-rolling it is this one command.

WHY OCTAVES ARE BAKED IN RATHER THAN SUMMED PER FRAGMENT. `fx_fbm` pays for its three
octaves per fragment every frame; this pays once, here. And there is a hard ceiling on
useful detail: `p` is quantized to `u_pixel` before anything samples it, so octaves finer
than one FX pixel cannot be seen. The finest octave below lands at 4 px of a 128 px tile,
which at the shipped `noise_scale` is about one FX pixel — going finer is pure waste.

⚠ THE TEXTURE PATH IS NOT AUTOMATICALLY THE CHEAPER ONE. It trades seven hash+lerp ALU
taps for one memory fetch, on an Intel UHD with shared memory bandwidth. `FxFireStyle
.noise_procedural` switches between them and `Tests/Visual/fx_cost.tscn` prices both;
the shipped default is whichever won there.

⚠ CHECK THE TILING PERIOD BY EYE at the shipped `noise_scale`. A nearest-filtered
scrolling texture repeats visibly if its period lands near the flame height, and no
number catches that.
"""

import pathlib

import numpy as np
from PIL import Image

SIZE = 128
# Lattice cells per tile, coarsest first. Each must DIVIDE `SIZE`, or the octave does not
# tile with the image and the seam comes back.
OCTAVES = ((8, 0.6), (16, 0.3), (32, 0.1))
SEED = 20260729


def _hash_lattice(cells: int, rng: np.random.Generator) -> np.ndarray:
    """One octave's random values, with the lattice WRAPPED so the tile is seamless."""
    v = rng.random((cells, cells), dtype=np.float64)
    # The interpolation below reads i+1, so the tile only closes if the row and column past
    # the end are the first ones again.
    return np.pad(v, ((0, 1), (0, 1)), mode="wrap")


def _octave(cells: int, rng: np.random.Generator) -> np.ndarray:
    lattice = _hash_lattice(cells, rng)
    t = np.arange(SIZE, dtype=np.float64) * (cells / SIZE)
    i = np.floor(t).astype(np.int64)
    f = t - i
    # Smoothstep, exactly as fx_value_noise does it, so the two noise paths have the same
    # character and the A/B is measuring COST rather than look.
    w = f * f * (3.0 - 2.0 * f)
    iy, ix = i[:, None], i[None, :]
    wy, wx = w[:, None], w[None, :]
    a = lattice[iy, ix]
    b = lattice[iy, ix + 1]
    c = lattice[iy + 1, ix]
    d = lattice[iy + 1, ix + 1]
    return (a + (b - a) * wx) + ((c + (d - c) * wx) - (a + (b - a) * wx)) * wy


def main() -> None:
    rng = np.random.default_rng(SEED)
    img = np.zeros((SIZE, SIZE), dtype=np.float64)
    for cells, weight in OCTAVES:
        img += _octave(cells, rng) * weight
    # Normalize to the full byte range: the shader treats the sample as a 0..1 noise and a
    # texture that only ever reached 0.2..0.8 would quietly halve `aperture`'s effect.
    img = (img - img.min()) / max(img.max() - img.min(), 1e-9)
    out = pathlib.Path(__file__).resolve().parent.parent / "Assets" / "Fx" / "noise_fire.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((img * 255.0 + 0.5).astype(np.uint8)).save(out)
    # Seam check, so a broken edit cannot ship a texture with a visible line down it.
    seam_x = float(np.abs(img[:, 0] - img[:, -1]).max())
    seam_y = float(np.abs(img[0, :] - img[-1, :]).max())
    print(f"wrote {out} ({SIZE}x{SIZE})")
    print(f"seam continuity: max step across the wrap x={seam_x:.4f} y={seam_y:.4f}")


if __name__ == "__main__":
    main()
