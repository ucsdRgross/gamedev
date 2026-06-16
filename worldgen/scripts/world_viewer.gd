class_name WorldViewer
extends Node2D

## Colorizes the generator's array-backed snapshots on the CPU and renders
## them. Every visual (topography, biomes, rivers, fault lines, plate vectors,
## graph) is burned into an Image, so the on-screen grid and the exported PNG
## are pixel-identical (the PNG simply omits the text legends drawn on top).

var generator: WorldGenerator
var label: Label

# Each display slot -> [source snapshot key, paint mode].
const SLOT_DEF := {
	"Landmass": ["Landmass", "topo"],
	"Tectonics_Debug": ["Tectonics_Debug", "topo"],
	"PeaksAndValleys": ["PeaksAndValleys", "topo"],
	"ErosionDebug": ["Erosion", "erosion_debug"],
	"Erosion": ["Erosion", "topo"],
	"Climate": ["Climate", "biome"],
	"Rivers_Only": ["Rivers_Only", "rivers"],
	"BiomesRivers": ["Climate", "biome_river"],
	"Graph": ["Graph", "graph"],
}
# The 9 grid slots, row-major.
const GRID_STEPS :Array[String]= ["Landmass", "Tectonics_Debug", "PeaksAndValleys",
	"ErosionDebug", "Erosion", "Climate", "Rivers_Only", "BiomesRivers", "Graph"]

var step_names: Array[String] = []
var _cells: Array = []          # flat [kind, src, label] list for arrow cycling
var current_step_index: int = -1
var cached_texture: ImageTexture
var _grid_texture: ImageTexture

# --- palettes ----------------------------------------------------------------
const SUBSTRATE := Color("#0f172a")
const RIVER := Color("#38bdf8")
const RIVER_OVERLAY := Color("#2563eb")
const RIVER_HI := Color("#e0f2fe")  # high-elevation end of the river height ramp
const RIVER_LO := Color("#0c4a6e")  # low-elevation (near sea) end of the ramp
const LAKE := Color("#1d4ed8")      # depression-fill lake tint
const FAULT := Color("#a855f7")
# Monotone (single-hue, not black/white) ramp for noise maps and raw heightmaps.
const MONO_LO := Color("#10212e")
const MONO_HI := Color("#a9d6ec")
const CELL := 256                   # px size of each cell in the debug composite

func mono_color(v: float) -> Color:
	return MONO_LO.lerp(MONO_HI, clampf(v, 0.0, 1.0))

static func topo_color(val: float, oth: float, mth: float) -> Color:
	if val < oth: return Color("#1a365d")
	elif val < oth + 0.04: return Color("#2b6cb0")
	elif val < 0.46: return Color("#2f855a")
	elif val < mth: return Color("#ecc94b")
	elif val < 0.82: return Color("#718096")
	else: return Color("#ffffff")

const BIOME_COLORS := [
	Color("#1a365d"), Color("#e2e8f0"), Color("#991b1b"), Color("#4b5563"),
	Color("#38bdf8"), Color("#7c2d12"), Color("#9ca3af"), Color("#f9fafb"),
	Color("#65a30d"), Color("#047857"), Color("#b45309"), Color("#15803d"),
	Color("#065f46"),
]

func _ready() -> void:
	label = get_node_or_null("CanvasLayer/Label")
	var tr := get_node_or_null("CanvasLayer/TextureRect")
	if tr: tr.visible = false

	generator = $WorldGenerator
	generator.generation_step_finished.connect(_on_generation_step_finished)
	generator.generate_world_map()

func _on_generation_step_finished(step_name: String) -> void:
	if step_name != "All_Steps_Grid":
		return
	# Arrow keys cycle through every individual cell, then the full composite.
	_cells = _flat_cells()
	step_names.clear()
	for cell in _cells:
		step_names.append(cell[2])
	step_names.append("All_Steps_Grid")
	_build_composite_and_export()
	current_step_index = step_names.size() - 1  # default to the full composite
	_display_snapshot()

func _unhandled_input(event: InputEvent) -> void:
	if step_names.is_empty(): return
	if event.is_action_pressed("ui_right"):
		current_step_index = (current_step_index + 1) % step_names.size()
		_display_snapshot()
	elif event.is_action_pressed("ui_left"):
		current_step_index = (current_step_index - 1 + step_names.size()) % step_names.size()
		_display_snapshot()

func _display_snapshot() -> void:
	var step := step_names[current_step_index]
	if label:
		label.text = "Step: " + step + " (Arrow Keys to Cycle)"

	if step == "All_Steps_Grid":
		cached_texture = _grid_texture
	else:
		var w := generator.settings.map_width
		var h := generator.settings.map_height
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var cell: Array = _cells[current_step_index]
		_paint_cell(img, cell[0], cell[1], Vector2i.ZERO, w)
		cached_texture = ImageTexture.create_from_image(img)
	queue_redraw()

## Debug sheet: one row per generation step/grouping (variable cells per row).
## Each cell is [kind, source]. Monotone (non-B&W) for noise maps and raw
## heightmaps; full color only where color is meaningful (topo, biomes, rivers,
## fault lines/arrows, graph).
## Rows of cells; each cell is [kind, source, label].
func _debug_rows() -> Array:
	return [
		# Landmass: base noise, then colored heights.
		[["noise", "landmass", "Landmass Noise"], ["topo", "Landmass", "Landmass"]],
		# Tectonics: warp noise, then deformed terrain with fault lines + arrows.
		[["noise", "warp_x", "Tectonic Noise"], ["tectonics", "Tectonics_Debug", "Tectonics"]],
		# Peaks & valleys: ridge noise, then colored heights.
		[["noise", "peaks_ridge", "Peaks Noise"], ["topo", "PeaksAndValleys", "Peaks & Valleys"]],
		# Erosion: incoming height, channel noise, erosion humidity, eroded terrain.
		[["mono", "PeaksAndValleys", "Height (pre-erosion)"], ["noise", "erosion_channel", "Erosion Noise"], ["noise", "erosion_humidity", "Erosion Humidity"], ["topo", "Erosion", "Erosion"]],
		# Climate: incoming height, temperature, humidity, biome map.
		[["mono", "Rivers_Only", "Height (pre-climate)"], ["noise", "temperature", "Temperature"], ["noise", "humidity", "Humidity"], ["biome", "Climate", "Biomes"]],
		# Rivers: incoming height, (shared climate) humidity, river network, rivers on biomes.
		[["mono", "Erosion", "Height (pre-rivers)"], ["noise", "humidity", "Humidity (climate)"], ["rivers", "Rivers_Only", "Rivers"], ["biome_river", "Climate", "Rivers on Biomes"]],
		# Nodes / graph: dense travel nodes, sparse city nodes, the graph alone
		# (lines + nodes on a flat background), then the routed graph over biomes.
		[["travel", "Graph", "Travel Nodes"], ["cities", "Graph", "City Nodes"], ["graph_only", "Graph", "Graph (lines only)"], ["graph", "Graph", "Graph on Biomes"]],
	]

## Flat, ordered list of every cell so arrow keys can step through them all.
func _flat_cells() -> Array:
	var out: Array = []
	for row in _debug_rows():
		for cell in row:
			out.append(cell)
	return out

func _build_composite_and_export() -> void:
	var rows := _debug_rows()
	var gap := 4
	var max_cols := 1
	for r in rows:
		max_cols = maxi(max_cols, r.size())
	var comp_w: int = (max_cols * CELL) + ((max_cols - 1) * gap)
	var comp_h: int = (rows.size() * CELL) + ((rows.size() - 1) * gap)
	var comp := Image.create(comp_w, comp_h, false, Image.FORMAT_RGBA8)
	comp.fill(Color.BLACK)

	for ri in range(rows.size()):
		var row: Array = rows[ri]
		for ci in range(row.size()):
			var off := Vector2i(ci * (CELL + gap), ri * (CELL + gap))
			_paint_cell(comp, row[ci][0], row[ci][1], off, CELL)

	_grid_texture = ImageTexture.create_from_image(comp)
	comp.save_png("res://procedural_generation_snapshot.png")
	print("[WorldViewer] Debug sheet exported to res://procedural_generation_snapshot.png")
	_export_full_res()

## Save full-resolution (map-sized) PNGs for every colored cell -- i.e. anything
## that isn't a pure noise map or a pure (monotone) heightmap, since those read
## fine downscaled. Lets the composite stay a compact overview while detailed
## views (biomes, rivers, graph, tectonics, ...) are crisp.
func _export_full_res() -> void:
	var w := generator.settings.map_width
	var seen := {}
	for cell in _flat_cells():
		var kind: String = cell[0]
		if kind == "noise" or kind == "mono":
			continue
		var name: String = cell[2]
		if seen.has(name):
			continue
		seen[name] = true
		var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
		_paint_cell(img, kind, cell[1], Vector2i.ZERO, w)
		var fname := "res://snapshot_%s.png" % name.to_lower().replace(" ", "_").replace("(", "").replace(")", "")
		img.save_png(fname)
	print("[WorldViewer] Full-res cell PNGs exported (snapshot_*.png)")

## Paint one cell_px x cell_px cell at `off` (cell_px = full map width for the
## single-cell arrow view, or CELL for the composite).
func _paint_cell(img: Image, kind: String, src: String, off: Vector2i, cell_px: int) -> void:
	var w := generator.settings.map_width
	var h := generator.settings.map_height
	var oth := generator.settings.ocean_threshold
	var mth := generator.settings.mountain_threshold
	var scale := float(cell_px) / float(w)

	# Pure-graph cell: flat backdrop, then only the graph lines/nodes on top.
	if kind == "graph_only":
		for ty in range(cell_px):
			for tx in range(cell_px):
				img.set_pixel(off.x + tx, off.y + ty, SUBSTRATE)
		_burn_graph(img, off, scale, false)
		return

	# Noise cells read straight from a baked noise image; everything else needs a snapshot.
	var noise_im: Image = null
	if kind == "noise":
		if not generator.noise_maps.has(src):
			return
		noise_im = generator.noise_img(src)

	var data: Dictionary = generator.snapshots.get(src, {})
	var height: PackedFloat32Array = data.get("height", PackedFloat32Array())
	var biome: PackedInt32Array = data.get("biome", PackedInt32Array())
	var rset: Dictionary = data.get("river_set", {})
	var lset: Dictionary = data.get("lake_set", {})
	if kind != "noise" and height.is_empty():
		return

	for ty in range(cell_px):
		for tx in range(cell_px):
			var ox: int = mini(int(tx / scale), w - 1)
			var oy: int = mini(int(ty / scale), h - 1)
			var idx: int = (oy * w) + ox
			var pos := Vector2i(ox, oy)
			var col: Color
			match kind:
				"noise":
					col = mono_color(noise_im.get_pixel(ox, oy).r)
				"mono", "travel", "cities":
					# Monotone land height only; below sea reads as flat dark so land pops.
					if height[idx] < oth:
						col = SUBSTRATE
					else:
						col = mono_color((height[idx] - oth) / maxf(0.001, 1.0 - oth))
				"rivers":
					if (lset.has(pos) or _near_river(rset, pos)) and height[idx] >= oth:
						var t := clampf((height[idx] - oth) / maxf(0.001, 1.0 - oth), 0.0, 1.0)
						col = RIVER_LO.lerp(RIVER_HI, t)
					else:
						col = SUBSTRATE
				"biome":
					col = _biome_color(biome[idx])
				"biome_river", "graph":
					col = _biome_color(biome[idx])
					if (_near_river(rset, pos) or lset.has(pos)) and height[idx] >= oth:
						col = RIVER_OVERLAY
				_:  # topo / tectonics base
					col = topo_color(height[idx], oth, mth)
			img.set_pixel(off.x + tx, off.y + ty, col)

	match kind:
		"tectonics":
			_burn_tectonics(img, data, off, scale)
		"graph":
			_burn_graph(img, off, scale, true)  # colored view: curved roads
		"cities":
			_burn_nodes(img, off, scale, true)
		"travel":
			_burn_nodes(img, off, scale, false)

## Plot node dots from the Cities snapshot: the sparse city set when `cities`,
## else the dense independent travel-node set.
func _burn_nodes(img: Image, offset: Vector2i, scale: float, cities: bool) -> void:
	if not generator.snapshots.has("Cities"):
		return
	var data: Dictionary = generator.snapshots["Cities"]
	if cities:
		for node in data["city_nodes"]:
			_plot_disc(img, (node * scale) + Vector2(offset), maxf(2.0, 4.0 * scale), Color("#ecc94b"))
	else:
		for node in data.get("travel_nodes", []):
			_plot_disc(img, (node * scale) + Vector2(offset), maxf(1.0, 1.6 * scale), Color("#9ca3af"))

# =================================================================
# PER-SLOT RASTERIZER
# =================================================================
func _paint_step(img: Image, slot: String, offset: Vector2i, scale: float) -> void:
	if not SLOT_DEF.has(slot): return
	var src_key: String = SLOT_DEF[slot][0]
	var mode: String = SLOT_DEF[slot][1]
	if not generator.snapshots.has(src_key): return
	var data: Dictionary = generator.snapshots[src_key]

	var w := generator.settings.map_width
	var h := generator.settings.map_height
	var oth := generator.settings.ocean_threshold
	var mth := generator.settings.mountain_threshold

	var height: PackedFloat32Array = data["height"]
	var biome: PackedInt32Array = data["biome"]
	var rset: Dictionary = data["river_set"]
	var lset: Dictionary = data.get("lake_set", {})
	# Erosion debug compares post-erosion height against pre-erosion (peaks).
	var pre_height: PackedFloat32Array = height
	if mode == "erosion_debug" and generator.snapshots.has("PeaksAndValleys"):
		pre_height = generator.snapshots["PeaksAndValleys"]["height"]

	var sw: int = int(w * scale)
	var sh: int = int(h * scale)
	for ty in range(sh):
		for tx in range(sw):
			var ox: int = int(tx / scale)
			var oy: int = int(ty / scale)
			var idx: int = (oy * w) + ox
			var pos := Vector2i(ox, oy)
			var col: Color

			match mode:
				"rivers":
					# Shade rivers AND lakes by elevation (same ramp) so their water
					# height is visible; everything else dark.
					if (lset.has(pos) or _near_river(rset, pos)) and height[idx] >= oth:
						var t := clampf((height[idx] - oth) / maxf(0.001, 1.0 - oth), 0.0, 1.0)
						col = RIVER_LO.lerp(RIVER_HI, t)
					else:
						col = SUBSTRATE
				"erosion_debug":
					var carved: float = pre_height[idx] - height[idx]
					col = SUBSTRATE.lerp(RIVER, clampf(carved * 30.0, 0.0, 1.0))
				"biome":
					col = _biome_color(biome[idx])
				"biome_river", "graph":
					col = _biome_color(biome[idx])
					if (_near_river(rset, pos) or lset.has(pos)) and height[idx] >= oth:
						col = RIVER_OVERLAY
				_:  # topo
					col = topo_color(height[idx], oth, mth)

			img.set_pixel(offset.x + tx, offset.y + ty, col)

	if slot == "Tectonics_Debug":
		_burn_tectonics(img, data, offset, scale)
	elif mode == "graph":
		_burn_graph(img, offset, scale)

## Vivid, maximally-separated color for the 3x3x3 biome scheme (id 1..27);
## id 0 = ocean. Golden-ratio hue spacing keeps even sequential ids far apart in
## color, and the height band adds a brightness tier. Bright + distinct so the
## map reads as a colorful patchwork and colors are reliable to sample back.
const GOLDEN := 0.6180339887498949
func _biome_color(bid: int) -> Color:
	if bid <= 0:
		return Color("#1a365d")  # ocean
	var id0 := bid - 1
	var per_height: int = maxi(1, generator.settings.temp_bands * generator.settings.humid_bands)
	var hbands: int = maxi(1, generator.settings.height_bands)
	var h_band := id0 / per_height               # height tier
	var hue := fposmod(float(id0) * GOLDEN, 1.0)
	var sat: float = 0.80
	var val: float = 0.78 + (float(h_band) / float(maxi(1, hbands - 1)) if hbands > 1 else 0.0) * 0.22
	return Color.from_hsv(hue, sat, val)

func _near_river(rset: Dictionary, pos: Vector2i) -> bool:
	for rx in range(-1, 2):
		for ry in range(-1, 2):
			if rset.has(pos + Vector2i(rx, ry)):
				return true
	return false

func _burn_tectonics(img: Image, data: Dictionary, offset: Vector2i, scale: float) -> void:
	var w := generator.settings.map_width
	var h := generator.settings.map_height
	var plate_ids: PackedInt32Array = data["plate_ids"]
	var stride: int = maxi(1, int(1.0 / scale))

	var sw: int = int(w * scale)
	var sh: int = int(h * scale)
	for ty in range(sh):
		for tx in range(sw):
			var ox: int = int(tx / scale)
			var oy: int = int(ty / scale)
			var idx: int = (oy * w) + ox
			var pid: int = plate_ids[idx]

			# Fault line if any 4-neighbour belongs to a different plate.
			var l: int = plate_ids[(oy * w) + maxi(ox - stride, 0)]
			var r: int = plate_ids[(oy * w) + mini(ox + stride, w - 1)]
			var u: int = plate_ids[(maxi(oy - stride, 0) * w) + ox]
			var dn: int = plate_ids[(mini(oy + stride, h - 1) * w) + ox]
			if pid != l or pid != r or pid != u or pid != dn:
				img.set_pixel(offset.x + tx, offset.y + ty, FAULT)

	for plate in data["landmarks"]:
		var c: Vector2 = (plate.pos * scale) + Vector2(offset)
		var col := Color("#0ea5e9") if plate.ocean else Color("#f43f5e")
		_plot_disc(img, c, maxf(2.0, 5.0 * scale), col)
		var tip: Vector2 = c + (plate.dir * 45.0 * scale)
		_plot_line(img, c, tip, col)
		_plot_arrowhead(img, c, tip, col, maxf(3.0, 7.0 * scale))

## Graph view: nodes from the full (pre-prune) Cities set so unused nodes show,
## edges + start/end from the pruned Graph snapshot, with directional arrows.
func _burn_graph(img: Image, offset: Vector2i, scale: float, curved: bool = false) -> void:
	var all_nodes: Array = []
	if generator.snapshots.has("Cities"):
		all_nodes = generator.snapshots["Cities"]["city_nodes"]
	var graph: Dictionary = {}
	var curves: Array = []
	var start := Vector2.ZERO
	var end := Vector2.ZERO
	var used_nodes: Dictionary = {}
	if generator.snapshots.has("Graph"):
		var g: Dictionary = generator.snapshots["Graph"]
		graph = g["gameplay_graph"]
		curves = g.get("edge_curves", [])
		start = g["start_node"]
		end = g["end_node"]
		for u in g["city_nodes"]:
			used_nodes[u] = true

	if curved and not curves.is_empty():
		# Cosmetic winding roads (routed around water / over passes).
		for poly in curves:
			for i in range(poly.size() - 1):
				var a: Vector2 = (poly[i] * scale) + Vector2(offset)
				var b: Vector2 = (poly[i + 1] * scale) + Vector2(offset)
				_plot_line(img, a, b, Color.WHITE)
			if poly.size() >= 2:
				var m = poly.size() / 2
				var f: Vector2 = (poly[m - 1] * scale) + Vector2(offset)
				var t: Vector2 = (poly[m] * scale) + Vector2(offset)
				_plot_arrowhead(img, f, t, Color("#fb923c"), maxf(3.0, 6.0 * scale))
	else:
		# Straight edges with a midpoint arrowhead for direction.
		for parent in graph.keys():
			for child in graph[parent]:
				var p1: Vector2 = (parent * scale) + Vector2(offset)
				var p2: Vector2 = (child * scale) + Vector2(offset)
				_plot_line(img, p1, p2, Color.WHITE)
				_plot_arrowhead(img, p1, p1.lerp(p2, 0.55), Color("#fb923c"), maxf(3.0, 6.0 * scale))

	# Nodes that participate in the routed graph (keys + children). City nodes are
	# bright/large anchors; routed travel nodes are medium; everything else dim.
	var route_nodes: Dictionary = {}
	for parent in graph.keys():
		route_nodes[parent] = true
		for child in graph[parent]:
			route_nodes[child] = true
	for node in all_nodes:
		var p: Vector2 = (node * scale) + Vector2(offset)
		if used_nodes.has(node):
			_plot_disc(img, p, maxf(2.0, 4.0 * scale), Color("#ecc94b"))
		else:
			_plot_disc(img, p, maxf(1.0, 2.0 * scale), Color("#6b7280"))
	for node in route_nodes.keys():
		if used_nodes.has(node):
			continue  # already drawn bright as a city
		_plot_disc(img, (node * scale) + Vector2(offset), maxf(1.5, 3.0 * scale), Color("#60a5fa"))

	if start != Vector2.ZERO:
		_plot_disc(img, (start * scale) + Vector2(offset), maxf(3.0, 6.0 * scale), Color.GREEN)
	if end != Vector2.ZERO:
		_plot_disc(img, (end * scale) + Vector2(offset), maxf(3.0, 6.0 * scale), Color.RED)

# --- pixel primitives --------------------------------------------------------
func _plot_disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	var ri: int = int(ceil(r))
	for ox in range(-ri, ri + 1):
		for oy in range(-ri, ri + 1):
			if Vector2(ox, oy).length() <= r:
				_safe_set(img, int(c.x) + ox, int(c.y) + oy, col)

func _plot_line(img: Image, p1: Vector2, p2: Vector2, col: Color) -> void:
	var steps: int = int(maxf(1.0, p1.distance_to(p2)))
	for s in range(steps + 1):
		var p := p1.lerp(p2, float(s) / float(steps))
		_safe_set(img, int(p.x), int(p.y), col)

func _plot_arrowhead(img: Image, from: Vector2, tip: Vector2, col: Color, size: float) -> void:
	var dir := (tip - from)
	if dir.length() < 0.001: return
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	_plot_line(img, tip, tip - dir * size + perp * size * 0.6, col)
	_plot_line(img, tip, tip - dir * size - perp * size * 0.6, col)

func _safe_set(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, col)

func _draw() -> void:
	if not cached_texture: return
	var screen := get_viewport_rect().size
	draw_texture_rect(cached_texture, Rect2(Vector2.ZERO, screen), false)
