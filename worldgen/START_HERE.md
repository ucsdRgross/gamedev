# START HERE — worldgen agent guide & reference

**Read this first if you are new to this directory.** Consolidated 2026-07-19 from the
GDExtension port handoffs (Phases 1–4 + NoiseBake), the determinism port, and the
efficiency audit — the full historical docs live in git history (map at the bottom).
**Keep it current:** when work lands, fold its regression-critical residue in here,
update the addon README if user-facing, and delete the temporary plan doc (git keeps the
text). Never keep dated "what happened" logs in living docs.

## What this project is

Canonical home of the **worldgen addon** (`addons/worldgen/` — self-contained heightmap
world generation + DAG overlay for Godot 4.7; full user docs in
[addons/worldgen/README.md](addons/worldgen/README.md)) plus its dev/tuning host
(map_viewer, tests/, tuning/, presets/) and the **worldgen_native** C++ GDExtension
([worldgen_native/BUILD.md](worldgen_native/BUILD.md)).

Pipeline: Landmass → Tectonics → Peaks&Valleys → Erosion → Rivers → Graph → Biomes.
The four heightmap steps run as native CPU code by default
(`WorldSettings.deterministic_terrain = true`); their old GPU shader paths remain as the
fallback when the dll is missing.

## Hard rules (every past handoff restated these)

1. **Vendoring:** Solatro vendors this addon at `solatro/addons/worldgen/` — NEVER edit
   the vendored copy. Land here, validate here, then re-copy changed files + `bin/` into
   Solatro (never its README — it carries a vendored banner), run
   `--headless --import` there (twice if uid errors), then Solatro's full test suite.
   ⚠️ Close any open Godot editor first — it LOCKS the vendored dll and the copy fails.
2. **No `git add` / commit / staging** — the owner commits via GitHub Desktop.
3. Warnings are errors: type every array and every for-loop variable.
4. **Run worldgen test scenes WINDOWED, never `--headless`** — Godot 4.7 headless never
   fires `frame_post_draw`, so any scene that generates a world stalls forever on the
   first GPU flush. `--headless --import` is fine. (Canonical writeup:
   `solatro/HEADLESS_TESTING.md`.)
5. **Two correctness contracts exist — apply the right one:**
   - **Performance ports** (everything except terrain): output must be **bit-identical**
     to the GDScript twin. Do arithmetic in double, narrow to float only where the
     GDScript stored float32; keep exact loop order and tie-breaks (heap `<=` push /
     `<` pop, dy/dx neighbour order); `int(x)` truncates toward zero. Gate:
     `tests/native_ab_test.tscn` (57 checks × 3 seeds).
   - **Deterministic terrain** (the 4 heightmap steps): NOT bit-identical to the GPU
     (impossible across vendors — that was the problem). Contract: (1) byte-identical
     run-to-run and across renderers, (2) measured-close to the old GPU look,
     (3) graph-stable (the land/water mask FLIP COUNT is the number that matters, not
     height deltas). Gate: `tests/deterministic_terrain_test.tscn`.
6. **Every native call site keeps its GDScript fallback** behind
   `if GenerationStep._native:` — the addon must work with the dlls deleted (rename
   them to `.off` to test; `generate_up_to_test` then takes ~150 s — slow, NOT hung).
7. Docs referencing `C:\richard\gamedev\...` mean the owner's other machine; real paths
   here are `C:\Users\khanr\Documents\GitHub\gamedev\`.

## worldgen_native — what is ported (all validated, vendored into Solatro)

One class `WorldgenNative`; GDScript reaches it via the cached `GenerationStep._native`.

- **Rivers:** `fill_depressions`, `flow_accumulate_mfd`, `box_blur`, `dilate_lake`,
  `river_downsample`, `river_seed_field`, `river_depth_stamp`, `river_lake_surfaces`,
  `river_apply_water`.
- **Graph/MapField:** `label_landmasses`, `map_distance_transform`,
  `poisson_land_samples`, `jittered_land_samples`, `measure_land`. (`_build_masks` and
  the placement solver stay GDScript — solver is ~2 ms, don't port it.)
- **Biomes:** `biome_build_cells` (adjacency dicts built with exact GDScript insertion
  order — downstream iterates them). `paint_cells` stays GDScript (RNG/dict-heavy, 3 ms).
- **Routing:** `route_edge` = the whole of `GraphDetail._route` (A*, `_cell_cost`,
  binary heap, LOS-simplify, Chaikin). Per-edge loop, route ORDER, occupancy stamping
  stay GDScript.
- **Painting:** `paint_map` = `WorldMapPainter._paint` per-pixel classifier writing RGBA8
  bytes directly. Band `upper` values cross as **float64** (GDScript floats are doubles —
  narrowing moves band edges); reproduces `set_pixel`'s truncation
  `uint8_t(CLAMP(c*255.0,0,255))` by hand. Deco scatter (9 ms) and `merge_layers` (3 ms,
  already one blit) untouched.
- **NoiseBake:** `bake_multifractal` (calls the ENGINE's own FastNoiseLite per octave —
  identical values by construction; same trick as Poisson using the engine's own
  RandomNumberGenerator: pass engine objects across, don't reimplement them).
- **Deterministic terrain:** `terrain_landmass`, `terrain_tectonics` (ONE pass covers
  both tectonic shaders, emits height + plate_ids; reads `gen.height_buffer`, not the
  never-rendered landmass viewport), `terrain_peaks`, `terrain_erosion` (one pass emits
  both shader outputs; row-parallelised — each pixel is a pure function of the read-only
  input, so thread count can't change the result).

Timings (dev box, seed 12356): enabled steps **5287 → ~593 ms** (GPU-era terrain) /
**~527 ms** deterministic; setup NoiseBake ~2200 → ~380 ms (floored by engine noise
calls). Remaining hot spots are the GPU-fallback path and engine noise — no native
candidates remain from the original list.

**Measured lesson worth keeping:** per-byte PackedByteArray writes from *GDScript* are
~3x SLOWER than `set_pixel` (one C++ call beats 4 indexed stores) — the raw-byte win only
exists *inside C++*. Don't "optimize" set_pixel loops in GDScript.

## Determinism — the guarantee and its edges

- Same seed = same map on every machine **because every player runs the same compiled
  dll** — not because C++ math is portable. `std::pow/atan2/exp/sin` differ between libm
  implementations. Consequences:
  - A recompile with a different toolchain, or a Mac/ARM port, is a **map-breaking event
    for shared seeds** — treat it as such.
  - `worldgen_native/SConstruct` pins `/fp:precise` (MSVC) / `-ffp-contract=off`
    (GCC/Clang) explicitly — keep it; `/fp:fast` would silently break determinism.
- Acceptance evidence: two-renderer bakes (GL Compatibility vs forward_plus/d3d12) are
  byte-identical on `graph.json` AND `land/water/composite.png`. Full-chain CPU-vs-old-GPU
  divergence: max|d|≈0.028, land/water flips 71 px (0.027%), non-compounding.
- ⚠️ **The committed `placement_debug/` + `biome_debug/` PNGs predate the port and came
  from the dev box** — they are a SAME-MACHINE regression check only; a diff against them
  on another machine is NOT a regression. Images regenerated after the port ARE
  cross-machine comparable.
- `world_seed` reproducibility also depends on the shipped `ranges_bundle.json` and
  parameter tables — re-tuning shifts the random draw order (expected).

## Test scenes (`tests/`) — run WINDOWED

| Scene | Notes |
|---|---|
| `native_ab_test` | Bit-identity gate, 57 checks × 3 seeds. The ONLY scene that propagates a failure exit code. |
| `deterministic_terrain_test` | Terrain repeatability + CPU-vs-GPU divergence numbers. |
| `generate_up_to_test` | Full pipeline; ~150 s without dlls (fallback gate). Rewrites `snapshot_*.png`. |
| `graph_placement_test` | 78 debug images; on_land%/water_viol are PRINTED, not asserted. |
| `biome_regions_test` / `biome_assign_test` | Biome gates. |
| `graph_spec_test` | Pure-data (no WorldGenerator, could run headless); sampled 300-spec fuzz is the normal gate; full 1500 ≈ 17–35 min. Counts failures then DISCARDS them (exit 0 always). |
| `addon_bake_test` / `addon_node_test` | No `quit()` by design (also demos) — kill after the PASS lines. addon_node prints per-step timings. Bake output: `%APPDATA%\Godot\app_userdata\worldgen\worldgen_bake_test\`. "EXR export is editor-only" warning is expected. |

⚠️ Seven of the eight scenes always exit 0 — READ their output; don't trust exit codes.
If a scene reports "WorldgenNative class not registered": the project is missing
`.godot/extension_list.cfg` — run `--headless --import` once (also the fix for stale
class-cache "Could not find type X" cascades).

## Open items / backlog

- **Test validity:** make the seven eyeball-gate scenes propagate failure exit codes
  (needed before any CI).
- **Routing quality headroom** (owner-gated — changes output, retires the bit-identity
  baseline): `route_downscale` 4 → 2 is ~90 ms (was 1.3 s pre-port), `ds=1` ~350 ms;
  `route_corridor_ratio`/`route_margin` also cheap now. Needs a visual A/B.
- **Unverified review items from the determinism port** (low priority, none observed
  failing): the bilinear clamp-to-edge sampler assumption in `terrain_tectonics`' drift
  sample (the one between-texel sample; wrong default → wrong edge pixels); thread-count
  independence only proven serial-vs-8-threads on one box; nobody has visually inspected
  a deterministic-terrain map; `deterministic_terrain_test` can pass vacuously if
  `_native` is null (no assertion the CPU path ran); no per-function characterization
  tests (output hashes for fixed inputs); erosion port never line-audited against the
  shader (`sloping`-aliases-`steepness` preserved deliberately); `erosion_field` debug
  image is now L8 (was float) — viewer slot unconfirmed.
- `worldgen/snapshot_*.png` in the repo were last written during a no-dll FALLBACK run
  (GPU path) — regenerate with the toggle on before treating them as current.
- `worldgen_native/.sconsign.dblite` probably shouldn't be tracked.

## Doc hygiene & retired docs

Same policy as `solatro/START_HERE.md`: plan/handoff docs are temporary — once landed,
fold the residue here and delete them; git history keeps the full text. Retired
2026-07-19: `GDEXTENSION_PORT_HANDOFF.md`, `GDEXTENSION_PHASE2_HANDOFF.md`,
`GDEXTENSION_PHASE4_HANDOFF.md`, `DETERMINISM_PORT_HANDOFF.md`,
`DETERMINISM_PORT_REVIEW_REQUEST.md`, `DETERMINISM_FINDINGS.md`,
`EFFICIENCY_AUDIT_TRACKER.md`, `UPSTREAM_EFFICIENCY_TODO.md`, `CPP_SETUP_FOR_OWNER.md`
(toolchain is installed: VS Build Tools 2022 + `pip install scons`), `PIPELINE.md` and
`criteria.txt` (stale pre-implementation specs — the addon README documents the real
pipeline; graph constraints live in `GraphRules`/`graph_spec.gd`).

Other references: `tuning/HOW_TO_READ.txt` + `tuning/best_ranges.*` (graph parameter
search artifacts — start at best_ranges.txt); memory notes `graph-spec-step-a` /
`graph-placement-step-b` cover the graph algorithm design.

## Build quick facts (details: worldgen_native/BUILD.md)

- `scons` is often NOT on PATH — use `python -m SCons platform=windows
  target=template_debug` (and `template_release`) from `worldgen_native/`.
- `godot-cpp/` is gitignored and may be absent: shallow-clone master, then copy
  `api/extension_api.json` + `api/gdextension_interface.h` over `godot-cpp/gdextension/`
  (no 4.7 branch exists upstream). First build ~30 min, then incremental.
- If SCons says "up to date" for a file you edited mid-build: delete `src/*.obj`.
- Output lands directly in `addons/worldgen/bin/` (so the vendor copy carries it).
