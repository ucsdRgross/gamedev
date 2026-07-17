class_name StepBiomes
extends GenerationStep

## Biomes step -- runs right after Graph:
##   A) BiomeAssign.assign      : biome per graph node (guarantee-rung scheme)
##   B) BiomeRegions.build_cells: warped flood -> organic land cells
##   C) BiomeRegions.paint_cells: node pins grow territories, climate-prior
##      filler covers untouched land + islands, slivers absorbed
##   then rasterize -> gen.biome_buffer, legend -> gen.biome_legend, and the
##   gameplay graph re-exports through the export_graph biome_fn hook so every
##   node carries its biome id.
## Graph toggled OFF degrades gracefully to a pure climate map (no pins).
## Pure CPU, no await -- safe on a WorkerThreadPool task (thread_cpu_steps).
## Do not edit settings/biome resources while a generation is running.

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var t0 := Time.get_ticks_msec()
	var bset: WorldBiomeSet = settings.active_biome_set()
	var field = gen.map_field
	if field == null:  # Graph off: build our own field (samples = region kernels)
		field = GraphPlacement.MapField.from_generator(gen, settings.field_opts())
		gen.map_field = field
	var warp: PackedByteArray = gen.noise_img("biome_warp").get_data()
	var humid: PackedByteArray = gen.noise_img("humidity").get_data()
	var seed_v: int = settings.main_seed + settings.biome_seed_offset
	var opts := settings.biome_opts()

	var cells := BiomeRegions.build_cells(field, warp, humid, opts)

	# Node assignment + pins (skipped in degraded graph-off mode).
	var assign := {}
	var pins: Array = []
	var ctx = gen.graph_ctx
	if ctx != null:
		assign = BiomeAssign.assign(ctx, bset, seed_v)
		var nb: PackedInt32Array = assign.node_biome
		var cell_of: PackedInt32Array = cells.cell_of
		for i in range(ctx.n):
			if ctx.active[i] == 0 or nb[i] < 0:
				continue
			var p: Vector2 = ctx.pos[i]
			var idx :int= (int(p.y) * field.w) + int(p.x)
			var cell: int = cell_of[idx] if idx >= 0 and idx < cell_of.size() else -1
			pins.append({"cell": cell, "biome": nb[i]})

	var paint := BiomeRegions.paint_cells(cells, bset, pins, opts, seed_v)
	gen.biome_buffer = BiomeRegions.rasterize(cells, paint.cell_biome, field)
	gen.biome_cell_of = cells.cell_of  # dev viewers visualize the raw partition
	gen.biome_legend = BiomeRegions.legend(bset, assign)
	gen.biome_stats = {
		"flood_ms": cells.ms, "paint_ms": paint.ms,
		"total_ms": Time.get_ticks_msec() - t0,
		"n_cells": cells.n_cells, "orphan_cells": cells.orphan_cells,
		"pins": pins.size(), "pin_fail": paint.pin_fail,
		"slivers_fixed": paint.slivers_fixed,
	}

	if ctx != null:
		# Re-export through the export_graph biome hook. Exact pos->biome LUT
		# (export_graph calls biome_fn with ctx.pos[i] verbatim) keeps node data
		# truthful even under pin fallbacks; the buffer lookup covers any miss.
		var lut: Dictionary[Vector2, int] = {}
		var nb2: PackedInt32Array = assign.node_biome
		for i in range(ctx.n):
			if ctx.active[i] == 1:
				lut[ctx.pos[i]] = nb2[i]
		var buf := gen.biome_buffer
		var fw: int = field.w
		var biome_fn := func(p: Vector2) -> int:
			var v = lut.get(p)
			if v != null:
				return v
			var bi := (int(p.y) * fw) + int(p.x)
			return buf[bi] if bi >= 0 and bi < buf.size() else -1
		gen.graph_export = GraphPlacement.export_graph(ctx, field, gen.graph_curves,
			{"biome_fn": biome_fn})
		# Bake the legend into the export so the overlay (meta/tint) and graph.json
		# can resolve biome ids to names/colors without the WorldBiomeSet.
		gen.graph_export["biomes"] = gen.biome_legend
	gen._save_snapshot_bridge("Biomes")
