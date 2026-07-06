extends Node

## Verifies WorldGenerator.generate_up_to() runs a strict prefix of the pipeline
## AND that the per-step toggles pass through correctly. Run this scene (F6).
## Prints PASS/FAIL lines, then quits.
##   1. Stop at EROSION -> "Erosion" present; "Rivers_Only"/"Graph" absent; the
##      deleted "Climate" snapshot never appears.
##   2. Disable Erosion, run up to RIVERS -> "Erosion" skipped, "Rivers_Only"
##      still produced (pass-through), final_snapshot() == "Rivers_Only".
##   3. Stop at GRAPH -> no "Biomes" snapshot (strict prefix holds for the new step).
##   4. Disable Biomes, run all -> final stays "Graph", biome buffer empty.
##   5. Disable Graph, keep Biomes -> "Biomes" present (degraded climate-map mode),
##      full land coverage, no graph export.

func _ready() -> void:
	print("=== generate_up_to test ===")
	var gen := WorldGenerator.new()
	gen.settings = WorldSettings.new()
	add_child(gen)
	await get_tree().process_frame

	# --- 1: strict prefix ----------------------------------------------------
	await gen.generate_up_to(WorldGenerator.GenStep.EROSION)
	var has_erosion: bool = gen.snapshots.has("Erosion")
	var has_rivers: bool = gen.snapshots.has("Rivers_Only")
	var has_climate: bool = gen.snapshots.has("Climate")
	print("  [prefix] has 'Erosion'    : ", has_erosion, "  (expected true)")
	print("  [prefix] has 'Rivers_Only': ", has_rivers, "  (expected false)")
	print("  [prefix] has 'Climate'    : ", has_climate, "  (expected false; step deleted)")
	print("  [prefix] final_snapshot   : ", gen.final_snapshot(), "  (expected Erosion)")
	var ok1 := has_erosion and not has_rivers and not has_climate \
		and gen.final_snapshot() == "Erosion"

	# --- 2: toggle pass-through ---------------------------------------------
	gen.settings.enable_erosion = false
	await gen.generate_up_to(WorldGenerator.GenStep.RIVERS)
	var skipped_erosion: bool = not gen.snapshots.has("Erosion")
	var rivers_ok: bool = gen.snapshots.has("Rivers_Only")
	print("  [toggle] Erosion skipped  : ", skipped_erosion, "  (expected true)")
	print("  [toggle] has 'Rivers_Only': ", rivers_ok, "  (expected true)")
	print("  [toggle] final_snapshot   : ", gen.final_snapshot(), "  (expected Rivers_Only)")
	var ok2 := skipped_erosion and rivers_ok and gen.final_snapshot() == "Rivers_Only"

	# --- 3: Biomes is a strict-prefix citizen too -----------------------------
	gen.settings.enable_erosion = true
	await gen.generate_up_to(WorldGenerator.GenStep.GRAPH)
	var no_biomes: bool = not gen.snapshots.has("Biomes")
	print("  [prefix] stop@GRAPH, no 'Biomes': ", no_biomes, "  (expected true)")
	var ok3 := no_biomes and gen.final_snapshot() == "Graph"

	# --- 4: Biomes toggled off -> legacy final ---------------------------------
	gen.settings.enable_biomes = false
	await gen.generate_up_to(WorldGenerator.GenStep.BIOMES)
	var b_off: bool = not gen.snapshots.has("Biomes") and gen.final_snapshot() == "Graph" \
		and gen.biome_buffer.is_empty()
	print("  [toggle] Biomes off -> final Graph, empty buffer: ", b_off, "  (expected true)")
	var ok4 := b_off

	# --- 5: Graph off + Biomes on -> degraded climate map ----------------------
	gen.settings.enable_biomes = true
	gen.settings.enable_graph = false
	await gen.generate_up_to(WorldGenerator.GenStep.BIOMES)
	var b_deg: bool = gen.snapshots.has("Biomes") and gen.final_snapshot() == "Biomes" \
		and gen.graph_export.is_empty() and not gen.biome_buffer.is_empty()
	var cover_ok := true
	if b_deg:
		var f = gen.map_field
		for i in range(gen.settings.map_width * gen.settings.map_height):
			if (f.water[i] == 0) != (gen.biome_buffer[i] >= 0):
				cover_ok = false
				break
	print("  [toggle] Graph off, Biomes on -> degraded map: ", b_deg,
		" coverage: ", cover_ok, "  (expected true true)")
	var ok5 := b_deg and cover_ok

	print("  snapshot keys (run 5)     : ", gen.snapshots.keys())
	print("  RESULT: ", "PASS" if (ok1 and ok2 and ok3 and ok4 and ok5) else "FAIL")
	print("=== generate_up_to test complete ===")
	get_tree().quit()
