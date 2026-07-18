# Upstream efficiency work items (from the Solatro audit, 2026-07-16)

**STATUS: ALL 4 ITEMS IMPLEMENTED 2026-07-17** and re-copied into Solatro the same day.
Implementation notes per item are inline below. Validation: all worldgen test scenes ran
clean (windowed — see "Headless caveat" at the bottom).

Source: `C:\richard\gamedev\solatro\EFFICIENCY_AUDIT_TRACKER.md` ("Worldgen addon
findings") and AUDIT_PROPOSALS_HANDOFF.md P14 (owner-approved 2026-07-16). Solatro
vendors this addon at `addons/worldgen/` — fixes must land HERE first, then be
re-copied into Solatro. All items are behavior-identical; the wins are generation
time and memory on big maps.

## Items

1. **Image readbacks via raw `data` buffer math** — DONE 2026-07-17, with a measured
   correction to the premise: per-element writes into a PackedByteArray from GDScript are
   ~3x SLOWER than `set_pixel` (one C++ call beats 4 indexed stores + clamps), so the wins
   were taken as whole-image C++ passes instead of byte math:
   - `read_height_from_image`: `convert(FORMAT_RF)` + `get_data().to_float32_array()`
     (bit-identical to `get_pixel().r`, verified) — the loop disappears entirely.
   - `read_plate_ids_from_image`: `convert(FORMAT_RGBAF)` + indexed float reads (int
     conversion still needs the loop, but indexing beats `get_pixel`).
   - `height_texture` / `map_painter.height_image_rf`: `Image.create_from_data(FORMAT_RF)`
     adopting the buffer (+ `convert(RGBAH)` for the texture — byte-identical, verified).
   - `map_painter.merge_layers`: `land.duplicate()` + `blit_rect_mask(water, water, ...)`
     — one C++ pass, bit-identical to the old per-pixel merge (verified incl. fractional
     deco alpha in the land layer).
   - `map_painter._paint` KEEPS its per-pixel `set_pixel`: the per-pixel classifier logic
     can't be bulk-converted, and byte-store output was measured slower (see above). Do
     not "optimize" it back to raw bytes. (RGBA8 `set_pixel` TRUNCATES, `int(clamp(v*255))`
     — relevant if anyone ever does rewrite it.)

2. **River/lake node storage** — DONE 2026-07-17. `river_nodes`/`lake_nodes` are now
   `PackedInt32Array` of flat cell indices (y*w+x; decode x = i % w, y = i / w).
   Consumers updated: `graph_placement.gd` `_build_masks` indexes the masks directly;
   `graph_placement_test.gd` only used `.size()`. Snapshot save/restore duplicate()
   carries over unchanged.

3. **Typed local dictionaries** — DONE 2026-07-17 where K/V are stable: ~30 locals across
   `graph_spec.gd`, `world_randomizer.gd`, `biome_assign.gd`, `biome_regions.gd`,
   `steps/biomes.gd`, `graph_placement.gd` (incl. MapField `sizes`/`label_seed`/`_shash`
   members). Left untyped: heterogeneous result/spec dicts (e.g. `assign`, snapshot
   bridges) whose values mix types by design.

4. **Loading-spinner `set_process` gating** — DONE 2026-07-17. `world_map_2d.gd` starts
   with `set_process(false)`; `_show_loading` enables, `_hide_loading` and
   `release_generator` disable. The `_process` visibility guard stays as a belt.

## Headless caveat (found while validating, 2026-07-17; canonical copy: solatro/HEADLESS_TESTING.md)

`--headless` never fires `RenderingServer.frame_post_draw` in Godot 4.7, so any test
scene that awaits a GPU `flush()` (generate_up_to, placement, biome, addon tests) stalls
forever headless. Run the test scenes WINDOWED (`Godot --path . res://tests/<t>.tscn`);
graph_spec_test is the only pure-data scene but its 1500-spec fuzz takes ~17 min
(~0.7 s/spec) — pre-existing, not a hang. addon_bake/addon_node scenes have no quit()
by design (kill after the PASS lines). This is likely the same root cause as Solatro's
"headless run hangs after the final banner" note.

## Context worth keeping (from the audit)

- Cross-folder coupling check PASSED: the addon references nothing in Solatro.
- Already excellent (don't churn): GPU shader steps, WorkerThreadPool CPU steps +
  parallel noise baking, COW PackedArray buffers/masks, texelFetch data textures,
  downscaled hydrology/distance grids, thread-safe pure-data graph placement.
- Long-term GDExtension/C# candidates if generation time ever matters:
  `rivers.gd` hydrology loops (DONE 2026-07-17 — `worldgen_native/` GDExtension,
  bit-identical, 5287 -> 1829 ms; see GDEXTENSION_PORT_HANDOFF.md STATUS),
  `graph_placement.gd` MapField, `biome_regions.gd` flood/voting,
  painter/generator readback loops.

After landing any item: re-copy the addon into `solatro/addons/worldgen/` and tick
P14 in Solatro's AUDIT_PROPOSALS_HANDOFF.md / EFFICIENCY_AUDIT_TRACKER.md.
