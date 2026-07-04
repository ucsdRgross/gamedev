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
├── height_band.gd / height_colorizer.gd  land/water palette (Resources)
├── map_painter.gd                      composite / land / water / height images
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

## Notes / caveats

- **`class_name` is project-global.** `WorldGenerator`, `WorldSettings`,
  `GenerationStep`, `GraphSpec`, `GraphPlacement`, `GraphDetail`, `NoiseBaker`,
  `WorldHeightBand`, `WorldHeightColorizer`, `WorldMapPainter`, and `WorldMap2D`
  are declared with `class_name`, so a host project that already defines any of
  those names will collide. Rename here (and update the internal references) or
  preload the scripts by path instead of relying on the global name.
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
