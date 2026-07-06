# Worldgen addon

Self-contained heightmap world generation for Godot 4.7. Drop `addons/worldgen/`
into any project, enable the **Worldgen** plugin (Project → Project Settings →
Plugins), then add a **WorldMap2D** node to a scene. It generates a static
colorized 2D map plus an interactive DAG overlay (graph nodes + curved edges)
centered on the node's origin, driven by tunable parameter ranges.

## Layout

```
addons/worldgen/
├── plugin.cfg / plugin.gd / icon.svg   editor plugin (registers WorldMap2D)
├── world_map_2d.gd                     the drag-and-drop @tool Node2D deliverable
├── graph_overlay.gd / graph_map_node.gd  interactive DAG overlay + per-node API
├── height_band.gd / height_colorizer.gd  land/water palette (Resources)
├── biome.gd / biome_set.gd             biome pool + casting/prior/ramp/deco config
├── biome_deco.gd                       baked decoration scatter (paint-time)
├── map_painter.gd                      composite / land / water / height images
├── world_randomizer.gd                 param tables + sampler + bundle randomize
├── ranges_bundle.json                  merged density model (dev-generated)
├── core/
│   ├── world_generator.gd              pipeline orchestrator (GPU + CPU)
│   ├── world_settings.gd               all tunables (@tool)
│   ├── world_gen_step.gd               GenerationStep base + shared CPU algorithms
│   ├── noise_baker.gd                  CPU noise bake
│   ├── steps/    landmass, tectonics, peaks_valleys, erosion, rivers, graph, biomes
│   ├── graph/    graph_spec, graph_placement, graph_detail
│   └── biomes/   biome_assign (node casting), biome_regions (map regions)
└── shaders/      landmass, tectonic_blueprint, tectonic_deformation,
                  peaks_and_valleys, erosion
```

## Pipeline

Landmass → Tectonics → Peaks&Valleys → Erosion → Rivers → Graph → Biomes. Each step
after Landmass can be toggled off in the WorldSettings **Pipeline** group; a disabled
step passes its input through to the next enabled step, and the final image reads
whatever step ran last. Biomes off = the classic height-band coloring; Graph off with
Biomes on degrades to a pure climate map (biomes chosen by height/moisture only).

## Usage

Add a **WorldMap2D** node. In the inspector it exposes `settings`, `colorizer`,
`world_seed`, `generate_on_ready`, `bake_directory`, and overlay/loading options,
plus tool buttons (Generate, Randomize + Generate, Bake, Export PNGs, Export EXR).
The map is a centered `Sprite2D`; the DAG is a `WorldGraphOverlay` (one
`WorldGraphNode` per node, one `Line2D` per edge), both centered on the node origin.

### Seed (reproducibility)

`world_seed` is the world's reproducibility handle:

- `world_seed = <non-zero>` → the same world is reproduced every time, as long as the
  shipped `ranges_bundle.json` and the parameter tables are unchanged (re-tuning shifts
  the random draw order — expected).
- `world_seed = 0` → "no seed": **Generate** keeps the current `settings` as-is (it
  never rerolls); **Randomize + Generate** rolls fresh params from the bundle; and
  `generate_on_ready` picks a fresh random terrain seed each launch while keeping the
  configured parameters.

So the two buttons are distinct: **Generate** re-runs what you see (respecting the seed
you set), and **Randomize + Generate** is the one that rolls a new world.

Pass a seed at runtime from a separate project by setting the export before generating:

```gdscript
@onready var map: WorldMap2D = $WorldMap2D

func new_world(seed: int) -> void:
	map.world_seed = seed          # non-zero = reproducible; 0 = random
	await map.randomize_and_generate()   # rolls params from the bundle, then generates
	# or map.generate() to keep the current params and just (re)apply the seed
```

Walk the graph for token movement once generation finishes:

```gdscript
var node := map.overlay().start_node()
for next in node.next_nodes():
	var path := node.edge_to(next)   # PackedVector2Array in map-local space
	var ferry := node.is_ferry_to(next)
```

### Loading screen

Generation is `await`-driven and emits `generation_started`,
`generation_progress(stage, fraction)`, and `generation_finished`. A minimal
built-in placeholder overlay is shown at runtime (`show_loading_screen`). To use
your own, connect to those signals and set `show_loading_screen = false`.

`threaded_paint` (default on) runs the pure-CPU work off the main thread so the
overlay keeps animating: the noise bake, the CPU pipeline steps (Rivers, Graph), and
the final image painting all run on `WorkerThreadPool` tasks while the main thread
polls frames. The GPU steps already yield per frame. Turn `threaded_paint` off to run
everything synchronously. `generation_progress` reports the running step, so a custom
overlay can show "Carving rivers & lakes" etc. as they happen.

### Customizing node + edge visuals

The overlay draws vector defaults (discs for nodes, colored `Line2D`s for edges).
Restyle without code via the inspector **Overlay** group: colors/widths, plus
optional `node_texture`/`start_texture`/`end_texture` (replace the discs, tinted by
the colors) and `edge_texture`/`ferry_texture` (tiled along the line) /
`edge_gradient` (colors the line along its length).

For full control, connect `graph_populated` and restyle the real nodes:

```gdscript
map.overlay().graph_populated.connect(func():
	for n in map.overlay().nodes():
		n.add_child(my_node_scene.instantiate())   # attach any art/animation
	var line := map.overlay().start_node().edge_line(map.overlay().start_node().next_nodes()[0])
	line.width = 8.0
)
```

### Biomes

The Biomes step colors ALL land into organic biome regions and gives every graph
node a biome the player will encounter:

- **Config** lives on a `WorldBiomeSet` Resource (WorldSettings → *Step 7 - Biomes*
  → `biome_set`; left empty, a shipped 16-biome default is used). It holds one pool
  of `WorldBiome`s plus `required_count` = N: **every start→end path is guaranteed
  to cross N distinct "required" biomes** — which ones depends on the route the
  player picks, and the cast is drawn fresh per seed (`force_include` pins a biome
  into every cast; `ambient_only` biomes only ever fill scenery; `required_eligible`
  gates the draw).
- **Land that no node touches** (far islands, interior) fills with climate-plausible
  biomes from the same pool (`height_range`/`moisture_range`/`weight` priors), so
  nodes never read as the origins of the coloring.
- **Look**: each biome carries its own `WorldHeightBand` ramp, so the heightmap
  stays visible inside every region; `snow_line` on the set is a global high-alt
  override. Borders wander organically (warp noise) — tune *Step 7* knobs
  (`biome_territory_cells`, `biome_warp_amp`, `biome_height_cost`, ...).
- **Decorations**: each biome holds an ARRAY of `WorldDecoLayer`s baked into the
  land image, so a forest can stack trees + undergrowth + mushrooms. Per layer:
  `textures` (drop in your own pixel art — stamped scaled + tinted; empty falls
  back to a procedural `mark`: TREE/ROCK/TUFT/SHARD/MUSHROOM), `density` (stamps
  per 1000 land px of the biome — 10-20 reads as dense forest; scaled by the
  global `biome_deco_density_mul`), `scale_range`, `color`, and `stackable`
  (ground cover overlaps freely; non-stackable stamps keep a small clearance from
  each other). Decorations avoid water, rivers, and graph nodes.
- **Gameplay data**: every exported node carries `biome` (index into the set) and
  the export/`graph.json` carry a `biomes` legend `[{id, name, color, required}]`;
  `WorldGraphNode.biome` + `meta["biome_name"/"biome_color"]` mirror it on the
  overlay, and `tint_nodes_by_biome` (Overlay group) optionally tints markers.
- **Iteration**: the **Repaint biomes** tool button re-runs only the painting, so
  palette/deco/tint edits show in under a second. Region shapes, the cast, and ids
  come from generation — reordering `biome_set.biomes` between Generate and Repaint
  mismatches colors (ids are indices); just Generate again.

### Baking

**Bake to files** writes `composite.png`, `land.png`, `water.png`, `height.exr`,
and `graph.json` to `bake_directory` (default: `res://addons/worldgen/exports`). With
`generate_on_ready = false` the node loads `composite.png` + `graph.json` from that
directory at runtime instead of regenerating — keeping the `.tscn` tiny, since the
generated images are never serialized into the scene.

`res://` is read-only in exported builds, so for **runtime** baking/saving set
`bake_directory` to a `user://` path (the editor tool buttons write `res://` fine).

## Notes / caveats

- **`class_name` is project-global.** `WorldGenerator`, `WorldSettings`,
  `GenerationStep`, `GraphSpec`, `GraphPlacement`, `GraphDetail`, `NoiseBaker`,
  `WorldRandomizer`, `WorldHeightBand`, `WorldHeightColorizer`, `WorldMapPainter`,
  `WorldMap2D`, `WorldGraphOverlay`, `WorldGraphNode`, `WorldBiome`,
  `WorldBiomeSet`, `WorldDecoLayer`, `WorldBiomeDeco`, `StepBiomes`,
  `BiomeAssign`, and `BiomeRegions` are declared with `class_name`, so a host project that already
  defines any of those names will collide. Rename here (and update the internal references) or preload the scripts
  by path instead of relying on the global name.
- **EXR export needs `WorkerThreadPool`-safe painting off.** Painting is
  thread-safe (Image/PackedArray only), but if you extend the painter to touch the
  scene tree or RenderingServer, disable `threaded_paint` — those APIs are
  main-thread-only.
- **Renderer.** The pipeline is verified only on **GL Compatibility**. It should
  work on Forward+ (canvas_item shaders + `use_hdr_2d` half-float readback), but
  that is untested. The double `frame_post_draw` await in `WorldGenerator.flush()`
  and the `FORMAT_RGBAH` targets are required for GL-compat readback — keep them.
- **EXR heightmap export is editor-only.** TinyEXR ships with the editor but not
  with export templates, so heightmap-EXR export is a tool-button action; at
  runtime it falls back with a warning.

## Development

This repository is also the dev/tuning host. Everything outside `addons/worldgen/`
is dev tooling: `map_viewer.*` (3D tuning viewer), `scripts/world_viewer*.gd`
(debug-sheet colorizer), `scripts/preset_io.gd` (good/bad preset recording),
`tests/`, and `presets/`. None of it is required by the addon at runtime.
