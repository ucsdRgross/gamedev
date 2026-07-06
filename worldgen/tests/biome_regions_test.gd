extends Node

## Phase-2 gate for the Biomes step (run with F6): generates seeds through the
## Biomes step, dumps debug PNGs to res://biome_debug/, and verifies:
##   1) coverage: every land pixel has a biome, every water pixel is -1
##   2) pins: each exported graph node sits on a pixel of its own biome
##   3) perf: the whole step stays under the 1 s budget (512^2)
## Also prints the step's internal timings, sliver/orphan counts, and a
## per-biome pixel histogram. Eyeball the PNGs: organic borders, nodes inside
## (not centered in) their territories, far islands filled.
##   cells_<seed>.png  : one random color per region cell (warped Voronoi)
##   biomes_<seed>.png : legend colors + black node dots

const OUT_DIR := "res://biome_debug/"

@export var seeds: Array[int] = [1, 2, 3]

var _gen: WorldGenerator
var _fails := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_gen = WorldGenerator.new()
	add_child(_gen)
	await get_tree().process_frame
	print("=== BiomeRegions test ===")
	for sd in seeds:
		await _run_seed(sd)
	print("=== BiomeRegions test complete: %s (images in %s) ===" % [
		"PASS" if _fails == 0 else "FAIL (%d checks)" % _fails, OUT_DIR])
	get_tree().quit()


## Print one PASS/FAIL line and count failures for the summary.
func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print("  [%s] %s" % ["PASS" if ok else "FAIL", msg])


## Generate seed `sd` through Biomes, run checks, dump both debug PNGs.
func _run_seed(sd: int) -> void:
	var bs := WorldSettings.new()
	bs.main_seed = sd
	_gen.settings = bs
	await _gen.generate_up_to(WorldGenerator.GenStep.BIOMES)
	var w := bs.map_width
	var h := bs.map_height
	var buf := _gen.biome_buffer
	var field = _gen.map_field
	var st := _gen.biome_stats
	print("-- seed %d: %d cells (%d orphan), flood %d ms, paint %d ms, total %d ms" % [
		sd, st.get("n_cells", 0), st.get("orphan_cells", 0),
		st.get("flood_ms", -1), st.get("paint_ms", -1), st.get("total_ms", -1)])
	print("   pins %d (failed %d), slivers absorbed %d" % [
		st.get("pins", 0), st.get("pin_fail", 0), st.get("slivers_fixed", 0)])
	if field == null or buf.size() < w * h:
		_fails += 1
		print("  [FAIL] no biome buffer / map field after generate_up_to(BIOMES)")
		return

	# 1) Coverage.
	var land_missing := 0
	var water_marked := 0
	for i in range(w * h):
		if field.water[i] == 0:
			if buf[i] < 0:
				land_missing += 1
		elif buf[i] >= 0:
			water_marked += 1
	_check(land_missing == 0 and water_marked == 0,
		"coverage: land w/o biome %d, water w/ biome %d" % [land_missing, water_marked])

	# 2) Pins: exported node biome == map biome under the node.
	var nodes: Array = _gen.graph_export.get("nodes", [])
	var pin_bad := 0
	for nd in nodes:
		var p: Vector2 = nd.pos
		if buf[(int(p.y) * w) + int(p.x)] != nd.biome:
			pin_bad += 1
	_check(pin_bad == 0, "pins honored: %d/%d nodes on their own biome" % [
		nodes.size() - pin_bad, nodes.size()])

	# 3) Perf budget.
	var ms: int = st.get("total_ms", 99999)
	_check(ms < 1000, "biome step under budget (%d ms < 1000 ms)" % ms)

	_print_histogram(buf)
	_dump_biomes_png(sd, w, h, buf, nodes)
	_dump_cells_png(sd, w, h, field, bs)


## Per-biome land-pixel histogram (largest first) using the legend names.
func _print_histogram(buf: PackedInt32Array) -> void:
	var counts := {}
	for v in buf:
		if v >= 0:
			counts[v] = counts.get(v, 0) + 1
	var rows: Array = []
	for b in counts:
		rows.append([counts[b], b])
	rows.sort()
	rows.reverse()
	var parts: Array = []
	for r in rows:
		parts.append("%s %d" % [_legend_name(r[1]), r[0]])
	print("   biome px: " + ", ".join(parts))


func _legend_name(id: int) -> String:
	for e in _gen.biome_legend:
		if e.id == id:
			return e.name
	return str(id)


## Legend-colored biome map + black 3x3 node dots (eyeball: nodes inside blobs).
func _dump_biomes_png(sd: int, w: int, h: int, buf: PackedInt32Array, nodes: Array) -> void:
	var pal := {}
	for e in _gen.biome_legend:
		pal[e.id] = Color(e.color)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var v := buf[(y * w) + x]
			img.set_pixel(x, y, pal.get(v, Color("#122036")) if v >= 0 else Color("#122036"))
	for nd in nodes:
		var p: Vector2 = nd.pos
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var px := int(p.x) + ox
				var py := int(p.y) + oy
				if px >= 0 and py >= 0 and px < w and py < h:
					img.set_pixel(px, py, Color.BLACK)
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "biomes_%d.png" % sd))


## Random color per region cell (re-runs the deterministic flood): eyeball the
## organic warped-Voronoi partition itself.
func _dump_cells_png(sd: int, w: int, h: int, field, bs: WorldSettings) -> void:
	var cells := BiomeRegions.build_cells(field,
		_gen.noise_img("biome_warp").get_data(),
		_gen.noise_img("humidity").get_data(), bs.biome_opts())
	var owner: PackedInt32Array = cells.cell_of
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var o := owner[(y * w) + x]
			if o < 0:
				img.set_pixel(x, y, Color("#122036"))
			else:
				var hv := hash(o * 2654435761)
				img.set_pixel(x, y, Color(
					0.25 + 0.75 * float(hv & 255) / 255.0,
					0.25 + 0.75 * float((hv >> 8) & 255) / 255.0,
					0.25 + 0.75 * float((hv >> 16) & 255) / 255.0))
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "cells_%d.png" % sd))
