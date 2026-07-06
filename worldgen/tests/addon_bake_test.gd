extends Node2D

## Bake/reload test: generate a world, bake it to disk, free it (simulate quitting), then
## load a SECOND WorldMap2D from that bake with generate_on_ready = false -- i.e. resuming a
## player's saved map WITHOUT regenerating. Run with F6 and read the Output. The reloaded
## map should show the same composite + a populated graph (identical node/edge counts).

const BAKE_DIR := "user://worldgen_bake_test"

func _ready() -> void:
	# --- Phase 1: generate + bake (the "playing" session) ---
	var a := WorldMap2D.new()
	a.world_seed = 777                # fixed so the run is reproducible
	a.bake_directory = BAKE_DIR
	add_child(a)
	await a.generation_finished
	var made := a.overlay().nodes().size()
	a.bake_to_files()                 # EXR is skipped at runtime (editor-only) -> expected warning
	print("[BakeTest] generated seed 777 (%d nodes) and baked to %s" % [made, BAKE_DIR])
	a.queue_free()                    # simulate quitting the game
	await get_tree().process_frame

	# --- Phase 2: reload from the bake (the "resume saved game" path) ---
	var b := WorldMap2D.new()
	b.generate_on_ready = false       # do NOT regenerate; load the baked files
	b.bake_directory = BAKE_DIR
	add_child(b)                      # its _ready() calls _load_baked()
	await get_tree().process_frame

	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()
	var size := Vector2(b.settings.map_width, b.settings.map_height) if b.settings else Vector2(512, 512)
	var vp := get_viewport_rect().size
	cam.zoom = Vector2.ONE * minf(vp.x / size.x, vp.y / size.y) * 0.9

	var loaded := b.overlay().nodes().size()
	var ok := loaded == made and made > 0

	# graph.json v2: legend present + biome meta survives the bake round-trip.
	var gj = JSON.parse_string(FileAccess.get_file_as_string(BAKE_DIR.path_join("graph.json")))
	var v2_ok: bool = typeof(gj) == TYPE_DICTIONARY and int(gj.get("version", 0)) == 2 \
		and not (gj.get("biomes", []) as Array).is_empty()
	var meta_ok :bool= loaded > 0 and b.overlay().nodes()[0].meta.has("biome_name")
	print("[BakeTest] graph.json v2 + legend: %s, reloaded node biome meta: %s" % [
		"PASS" if v2_ok else "FAIL", "PASS" if meta_ok else "FAIL"])
	ok = ok and v2_ok and meta_ok
	print("[BakeTest] reloaded baked map: %d graph nodes (expected %d) -> %s" % [
		loaded, made, "PASS" if ok else "MISMATCH"])
