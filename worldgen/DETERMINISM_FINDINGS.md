# Worldgen cross-machine determinism — findings (2026-07-18)

Investigation triggered by "why do graphs and biomes look different now?" during the
Phase 4 native port review. Short answer: **not the port — the GPU.** Longer answer
below, with the evidence, because the consequence is a shipping issue for Solatro.

## TL;DR

- Every C++ port (Phases 1-4) is **behavior-neutral** — proven, see §1.
- The four heightmap steps (Landmass, Tectonics, Peaks, Erosion) are **GPU shader
  passes**, read back at full float32 (`FORMAT_RF`). Their output is
  hardware/driver dependent.
- Consequence: **the same `world_seed` produces a different map on different
  machines** — and not only cosmetically. Measured against the dev box's committed
  images, **graph edge routes and node markers move** (§3).
- Solatro generates the map **at runtime on the player's machine**
  (`Scripts/Map/world_map_controller.gd:64`) and bakes locally, so this reaches
  players: seeds are not shareable, and a bug report's seed will not reproduce.
- The committed `placement_debug/` + `biome_debug/` PNGs are therefore **NOT a valid
  cross-machine regression baseline.** They are only meaningful same-machine.

## 1. The ports are behavior-neutral (proven, not assumed)

Ran the same tests on THIS box across three code states via a throwaway
`git worktree`, comparing the 78 `placement_debug` + 6 `biome_debug` images:

| Comparison (same machine) | Result |
|---|---|
| HEAD code vs Phase-4 code | **78/78 + 6/6 identical** |
| Pre-port code (`3750300`, before ANY C++ work) vs Phase-4 code | **78/78 identical** |
| HEAD code vs HEAD's own COMMITTED images | **84 differ** |
| `3750300` code vs `3750300`'s own COMMITTED images | **78 differ** |

The last row is the decisive one: **the commit that generated those images cannot
reproduce them on this machine.** That excludes code as the cause, including Phases
1-3 and NoiseBake. Rows 1-2 independently confirm the whole port chain changes
nothing.

## 2. Root cause

`world_generator.gd` `_pipeline()` — the first four steps are `"gpu": true`, rendered
through SubViewports and read back via `vp.get_texture().get_image()` into
`height_buffer` as **`FORMAT_RF` (32-bit float)**. There is no 8-bit quantisation
anywhere in that path to mask small differences.

The shaders use ops whose precision is **implementation-defined** in the GLSL spec —
vendors and drivers legitimately differ:

| shader | precision-sensitive ops |
|---|---|
| `erosion.gdshader` (276 ln) | `atan` x3, `sin` x2, `cos` x2, `pow` x2, `fract` x2, `exp`, `smoothstep` |
| `peaks_and_valleys.gdshader` | `texture` x7, `smoothstep` x3, `pow` |
| `tectonic_deformation.gdshader` | `texture` x3, `smoothstep`, `normalize` |
| `landmass.gdshader` | `texture` x3, `pow` |
| `tectonic_blueprint.gdshader` | `texture` x2 |

Everything downstream (Rivers, Graph, Biomes) is deterministic CPU code — proven
bit-identical native-vs-GDScript by `tests/native_ab_test.tscn`. So the GPU steps are
the **single** root cause.

Note NoiseBake is NOT implicated: it runs on the CPU (FastNoiseLite `get_image` +
native `bake_multifractal`) and emits `FORMAT_L8`.

## 3. How bad is it, measured

**Same machine, different renderer** (`gl_compatibility` vs `forward_plus`/`d3d12`,
same Intel UHD), via `addon_bake_test`:

| artifact | changed? |
|---|---|
| `composite.png` | **differs** |
| `land.png` | **differs** |
| `water.png` | same |
| `graph.json` | **same** |

So an API swap on one GPU perturbed heights enough to move land band colors, but not
enough to cross the ocean threshold or change the graph. Encouraging but **not a
guarantee** — it is one mild sample.

**Genuinely different machine** (dev box GTX 1070 committed image vs this box's
regeneration, `big_s1_4_curved.png`, 512x512):

```
differing=17833 (6.80%)   large-jump differing=9254 (3.53%)
top transitions:
   e5e5f2 -> 1e2d59   1810     <- white ROUTE LINE became ocean
   1e2d59 -> e5e5f2   1797     <- ocean became route line
   657d4f -> 647d4f     99     <- (harmless 1-unit terrain shading drift)
   e54c4c -> e5e5f2     76     <- red NODE MARKER moved
```

The ~1800/1797 white<->navy swap is **graph edges routed differently**, and the red
marker swaps are **node positions moving**. This is a structural difference, not a
shading difference. **The graph is not machine-stable today.**

## 4. Options to fix (no work started — needs an owner decision)

**A. Port the 4 GPU steps to CPU/C++ (recommended).** Gives identical heightmaps,
graphs AND visuals. Feasibility is good: the map is only **512x512**, and every one of
the four is a **single-pass per-pixel shader** — `erosion.gd` does two flushes but
each is one full-screen pass with an octave loop inside, no ping-pong iteration. The
existing `worldgen_native` extension and the A/B bit-identity harness already provide
the pattern. Likely **no net slowdown**: the GPU path costs 363 ms today and includes
5 SubViewport flushes, each awaiting `frame_post_draw` twice (~166 ms of pure frame
latency at 60 fps). CAVEAT: this buys determinism across machines *of the same OS and
architecture*, because the shipped dll embeds one implementation. Bit-identity across
Windows/Mac/ARM additionally requires avoiding libm transcendentals (`sin`/`cos`/`pow`
can differ between platform libms) in favour of self-contained implementations.

### Option A: COMPLETE 2026-07-18 — all 4 steps ported, default now ON

Owner chose A, with the acceptance bar "graph data identical across machines;
visuals may differ slightly". That relaxation matters: the CPU twins do **not** try
to reproduce the GPU bit-for-bit (impossible across vendors — it is the problem
itself). The contract is *self-consistency on every machine*.

- `WorldSettings.deterministic_terrain` (default **true** since all four steps
  landed) switches the heightmap steps to native CPU twins.
- **`terrain_landmass` done.** Skips the SubViewport entirely — no material, no
  `flush`, no frame waits. The noise/warp maps are CPU-baked L8 at exactly w x h and
  the shader samples at pixel centres, so bilinear sampling degenerates to a texel
  fetch: nothing filter-dependent to reproduce.
- New gate `tests/deterministic_terrain_test.tscn` (run WINDOWED — the GPU
  comparison arm needs `frame_post_draw`). Measured, seeds 12356 / 777:

```
[PASS] CPU terrain is byte-identical across runs (262144 px)
   seed 12356  CPU vs GPU: max|d|=0.00049 mean|d|=0.000113  land/water flips=75 (0.029%)
   seed 777    CPU vs GPU: max|d|=0.00049 mean|d|=0.000108  land/water flips=77 (0.029%)
```

  The max delta of ~0.00049 is ~2^-11 — i.e. the difference is dominated by the GPU
  render target storing **half floats**, not by shader math. Practically: switching
  this step to CPU is visually imperceptible and moves 0.03% of coastline pixels.
- **`terrain_tectonics` done.** ONE CPU pass covers BOTH shaders: the blueprint and
  the deform pass recompute the same warped-Voronoi nearest plates, so the plate ids
  (blueprint's blue channel) and the deformed height fall out of the same loop. It
  returns `[height, plate_ids]`. The trap: the deform shader samples
  `gen.viewport_texture("landmass")`, i.e. the GPU viewport — never rendered on this
  path — so the twin reads `gen.height_buffer`. That sample is the one place bilinear
  filtering is real (the drift offset lands between texels), so the twin does a
  clamp-to-edge bilinear fetch rather than a texel read.
- **`terrain_peaks` done.** Straight per-pixel port; every texture is sampled at a
  pixel centre so it is a direct texel fetch. Reads `height_buffer` at float32 rather
  than the GPU path's RGBAH half-float `height_texture()` — deliberately *more*
  precise.
- **`terrain_erosion` done.** The bulk. Directional-gabor octave loop in `double`,
  stored `float`. One CPU pass produces both shader outputs (the GPU needs two flushes
  only because `output_mode` is a uniform): the eroded height and the L8 erosion field
  for the debug viewer. Note the shader aliases `directional_gabor2`'s `sloping` out
  param onto `steepness`, so later octaves read the overwritten value — that is
  deliberate and the port preserves it.

Full-chain measurement (`generate_up_to(EROSION)`, seeds 12356 / 777), i.e. after all
four steps compound:

```
[PASS] CPU terrain is byte-identical across runs (262144 px)
   seed 12356  CPU vs GPU: max|d|=0.02836 mean|d|=0.000447  land/water flips=71 (0.027%)
   seed 777    CPU vs GPU: max|d|=0.02655 mean|d|=0.000381  land/water flips=71 (0.027%)
```

The flip count is the number that matters (it is what the graph is built from), and it
did **not** compound — 71 px full-chain vs 75-77 px after Landmass alone, because the
later steps' edge clamps and gates re-quantise the same coastline. Max height delta
grows to ~0.028 (erosion amplitude is 0.08, so this is a fraction of one octave of
gabor noise), mean stays at ~4e-4.

**Acceptance test passed.** `addon_bake_test` baked under two renderers —
default (OpenGL Compatibility) vs `--rendering-method forward_plus --rendering-driver
d3d12` — produced byte-identical `graph.json`, **and** byte-identical `land.png`,
`water.png` and `composite.png`. On the GPU path the PNGs differed between renderers
while `graph.json` happened to survive; now nothing differs at all.

**Scope of the guarantee (be honest about what was proven).** The two-renderer bake
ran on ONE machine, swapping only the rendering backend — it proves *renderer*
independence directly; *machine* independence follows from the argument that the CPU
path no longer touches the GPU at all, not from a second-machine measurement. And the
cross-machine claim itself rests on **"every player runs the same compiled dll"**, not
on C++ math being portable: `std::pow`/`atan2`/`exp`/`sin` are not IEEE-mandated to be
correctly rounded and can differ between libm implementations/compilers, and
`FastNoiseLite` baking rides on the same same-binary argument via the engine build.
One dll per platform = one implementation per platform; a recompile with a different
toolchain (or a Mac/ARM port) is a **map-breaking event for shared seeds** and should
be treated as such. To keep the compiler leg of that pinned, `worldgen_native/SConstruct`
now sets `/fp:precise` (MSVC) / `-ffp-contract=off` (GCC/Clang) explicitly instead of
relying on toolchain defaults — `/O2` does not imply `/fp:fast` today, but nothing
guaranteed that tomorrow.

**Cost.** Erosion is the only step where CPU is materially more work than the GPU:
single-threaded it landed at **1692 ms** (81% of generation). It is row-parallelised —
every output pixel is a pure function of the read-only input buffer with no cross-pixel
accumulation, so the result is independent of thread count and scheduling and
determinism is preserved by construction (verified: threaded output is byte-identical
to the single-threaded run, same max|d| / flip numbers). That takes Erosion to
**292 ms** and enabled-steps to **2076 -> 527 ms** (seed 12356, `addon_node_test`), i.e.
the CPU path is now *at or below* what the GPU path cost — the GPU path spent ~166 ms
just awaiting `frame_post_draw`, and its two erosion flushes are gone (one CPU pass
emits both outputs). Per-step: Landmass 11, Tectonics 17, PeaksAndValleys 6,
Erosion 292 ms.

- Regression: worldgen test scenes green with the toggle in BOTH positions, including
  the 57-check `native_ab_test` (untouched functions, still bit-identical) and the
  no-dll fallback (dlls renamed `.off` -> GPU path resumes, `generate_up_to` PASS).
  `graph_spec_test`'s structured cases all print OK in both positions; its 1500-spec
  fuzz (35 min on this box) was not re-run to completion for this change because that
  test never constructs a `WorldGenerator` — it exercises `graph_spec.gd`'s abstract
  DAG only and cannot see the heightmap.
- Vendored into Solatro (5 `.gd` files + both dlls): **ALL 24 SUITES, 1291 CHECKS
  PASSED, exit 0.**

**B. Quantise the heightmap before any CPU consumer.** Cheap stopgap, but only reduces
the odds — any value near a quantisation boundary still flips, and the ocean threshold
turns a 1-ULP difference into a land/water flip that changes landmass labels. **Not a
guarantee**; do not rely on it alone.

**C. Ship pre-baked maps.** Trivially identical everywhere; kills runtime procedural
variety per seed unless a fixed pool is acceptable.

**D. Keep GPU visuals, drive the graph from a separate CPU-computed field.** Satisfies
"graph data identical" only. Risky: the visual coastline would no longer exactly match
the field the nodes were placed against, so nodes can appear in water.

## 5. Unrelated findings from the same review

- **Test validity:** of the 8 worldgen test scenes, only `native_ab_test` propagates a
  failure exit code (`quit(_fails)`). The other seven call bare `get_tree().quit()` and
  **always exit 0** — `graph_spec_test` even counts `_failed` internally and then
  discards it. `addon_node_test` has no assertions at all;
  `graph_placement_test`'s `on_land%` / `ON_RIVER` / `water_viol` are printed, not
  asserted. They exercise live code (nothing is stale in that sense) but as regression
  detectors they are eyeball gates. Worth fixing if CI is ever wanted.
- **Routing has no quality-for-speed tradeoff active.** Instrumenting the three
  straight-line fallbacks and the iteration cap over a full generation:
  `total=81 degenerate_box=0 astar_failed=0 iter_cap=0` — every route solves cleanly.
  The `2 path pts` edges are LOS-simplified straight runs (by design), not fallbacks.
- **Routing quality headroom the port bought.** `route_downscale` defaults to 4 (A* on
  a grid 4x coarser than pixels) because it used to be expensive. Cost scales with cell
  count: `ds=2` is ~4x (323 ms -> was 1.3 s, now ~90 ms) and `ds=1` ~16x (now ~350 ms,
  still cheaper than the OLD GDScript path at ds=4). Also cheap now:
  `route_corridor_ratio` / `route_margin` (wider detour room). All of these CHANGE
  OUTPUT by design and would retire the bit-identity baseline — owner decision, and
  whether finer actually looks better needs a visual A/B.
