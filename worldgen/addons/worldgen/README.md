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
├── map_painter.gd                      composite / land / water / height images
├── world_randomizer.gd                 param tables + sampler + bundle randomize
├── ranges_bundle.json                  merged density model (dev-generated)
├── core/
│   ├── world_generator.gd              pipeline orchestrator (GPU + CPU)
│   ├── world_settings.gd               all tunables (@tool)
│   ├── world_gen_step.gd               GenerationStep base + shared CPU algorithms
│   ├── noise_baker.gd                  CPU noise bake
│   ├── steps/    landmass, tectonics, peaks_valleys, erosion, rivers, graph
│   └── graph/    graph_spec, graph_placement, graph_detail
└── shaders/      landmass, tectonic_blueprint, tectonic_deformation,
                  peaks_and_valleys, erosion
```

## Pipeline

Landmass → Tectonics → Peaks&Valleys → Erosion → Rivers → Graph. Each step after
Landmass can be toggled off in the WorldSettings **Pipeline** group; a disabled
step passes its input through to the next enabled step, and the final image reads
whatever step ran last.

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
overlay keeps animating: the CPU pipeline steps (Rivers, Graph) run on a
`WorkerThreadPool` task, and so does the final image painting. The GPU steps already
yield per frame. Turn `threaded_paint` off to run everything synchronously.

One caveat: the initial noise bake still runs on the main thread (it builds GPU
textures, which must be main-thread), so there is a brief hitch at the very start of
generation before the first step reports in.

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

### Baking

**Bake to files** writes `composite.png`, `land.png`, `water.png`, `height.exr`,
and `graph.json` to `bake_directory` (or beside the saved scene; `user://` if the
scene is unsaved). With `generate_on_ready = false` the node loads `composite.png`
+ `graph.json` at runtime instead of regenerating — keeping the `.tscn` tiny, since
the generated images are never serialized into the scene.

## Notes / caveats

- **`class_name` is project-global.** `WorldGenerator`, `WorldSettings`,
  `GenerationStep`, `GraphSpec`, `GraphPlacement`, `GraphDetail`, `NoiseBaker`,
  `WorldRandomizer`, `WorldHeightBand`, `WorldHeightColorizer`, `WorldMapPainter`,
  `WorldMap2D`, `WorldGraphOverlay`, and `WorldGraphNode` are declared with
  `class_name`, so a host project that already defines any of those names will
  collide. Rename here (and update the internal references) or preload the scripts
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
