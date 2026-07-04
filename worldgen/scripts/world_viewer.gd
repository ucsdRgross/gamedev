class_name WorldViewer
extends Node2D

## Colorizes the generator's array-backed snapshots on the CPU and renders
## them. Every visual (topography, rivers, fault lines, plate vectors, graph)
## is burned into an Image, so the on-screen grid and the exported PNG are
## pixel-identical (the PNG simply omits the text legends drawn on top).
## Colorized painting delegates to WorldMapPainter + WorldHeightColorizer.

var generator: WorldGenerator
var label: Label

var step_names: Array[String] = []
var _cells: Array = []          # flat [kind, src, label] list for arrow cycling
var current_step_index: int = -1
var cached_texture: ImageTexture
var _grid_texture: ImageTexture

# --- palettes ----------------------------------------------------------------
const SUBSTRATE := Color("#0f172a")
const RIVER_HI := Color("#e0f2fe")  # high-elevation end of the river height ramp
const RIVER_LO := Color("#0c4a6e")  # low-elevation (near sea) end of the ramp
const LAKE := Color("#1d4ed8")      # depression-fill lake tint
const FAULT := Color("#a855f7")

# Adjustable water colors (default to the constants above). map_viewer overrides
# these before painting so river/lake colors are tunable without touching code.
# Rivers ramp river_lo (near sea) -> river_hi (high); lakes are flat lake_col.
var river_lo: Color = RIVER_LO
var river_hi: Color = RIVER_HI
var lake_col: Color = LAKE
# Optional user-authored colorizer (custom bands + water colors). When set it is
# used AS-IS; when null a default ramp is built from the live thresholds.
var colorizer: WorldHeightColorizer = null
# Monotone (single-hue, not black/white) ramp for noise maps and raw heightmaps.
const MONO_LO := Color("#10212e")
const MONO_HI := Color("#a9d6ec")
const CELL := 256                   # px size of each cell in the debug composite

func mono_color(v: float) -> Color:
	return MONO_LO.lerp(MONO_HI, clampf(v, 0.0, 1.0))

## Colorizer for painter-backed cells: the user-authored one if set, else the
## default topo band ramp keyed on the LIVE ocean/mountain thresholds with this
## viewer's adjustable water colors applied. Rebuilt per paint (cheap) so
## threshold changes always track.
func _make_colorizer(oth: float, mth: float) -> WorldHeightColorizer:
	if colorizer != null and not colorizer.bands.is_empty():
		return colorizer
	var c := WorldHeightColorizer.make_default(oth, mth)
	c.river_color_low = river_lo
	c.river_color_high = river_hi
	c.lake_color = lake_col
	return c

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
## heightmaps; full color only where color is meaningful (topo, rivers,
## fault lines/arrows, graph).
## Rows of cells; each cell is [kind, source, label].
func _debug_rows() -> Array:
	return [
		# Landmass: base noise, then colored heights.
		[["noise", "landmass", "Landmass Noise"], ["topo", "Landmass", "Landmass"]],
		# Tectonics: warp noise, then deformed terrain with fault lines + arrows.
		[["noise", "warp_x", "Tectonic Noise"], ["tectonics", "Tectonics_Debug", "Tectonics"]],
		# Peaks & valleys: ridged-multifractal + billow-multifractal noise (altitude
		# blended in the shader), then colored heights.
		[["noise", "peaks_ridge", "Ridge Noise"], ["noise", "peaks_billow", "Billow Noise"], ["topo", "PeaksAndValleys", "Peaks & Valleys"]],
		# Erosion: incoming height, the gabor erosion field (driven by that height),
		# then the eroded terrain.
		[["mono", "PeaksAndValleys", "Height (pre-erosion)"], ["noise", "erosion_field", "Erosion Noise"], ["topo", "Erosion", "Erosion"]],
		# Rivers: incoming height, rainfall humidity, river network, full composite.
		[["mono", "Erosion", "Height (pre-rivers)"], ["noise", "humidity", "Humidity"], ["rivers", "Rivers_Only", "Rivers"], ["composite", "Rivers_Only", "Rivers on Terrain"]],
		# Graph: the graph alone (lines + nodes on a flat background), then the
		# routed graph over the composite map.
		[["graph_only", "Graph", "Graph (lines only)"], ["graph", "Graph", "Graph on Terrain"]],
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
	_export_water_only()

## Water-only sheet: rivers + lakes painted (tinted by water-surface elevation) on
## a fully TRANSPARENT background, so a 3D pass can drop it straight onto a water
## mesh/material with no land. Ocean is omitted (it's the flat plane at oth).
## Delegates to WorldMapPainter over the Rivers_Only snapshot.
func water_only_image() -> Image:
	var w := generator.settings.map_width
	var h := generator.settings.map_height
	var oth := generator.settings.ocean_threshold
	var data: Dictionary = generator.snapshots.get("Rivers_Only", {})
	if data.is_empty():
		return Image.create(w, h, false, Image.FORMAT_RGBA8)
	return WorldMapPainter.water_only_image(data, w, h, oth,
		_make_colorizer(oth, generator.settings.mountain_threshold), false)

func _export_water_only() -> void:
	if generator.snapshots.get("Rivers_Only", {}).is_empty():
		return
	water_only_image().save_png("res://snapshot_water_only.png")
	print("[WorldViewer] Water-only sheet exported (snapshot_water_only.png, transparent bg)")

## Save full-resolution (map-sized) PNGs for every colored cell -- i.e. anything
## that isn't a pure noise map or a pure (monotone) heightmap, since those read
## fine downscaled. Lets the composite stay a compact overview while detailed
## views (composite, rivers, graph, tectonics, ...) are crisp.
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
## single-cell arrow view, or CELL for the composite). Colorized kinds (topo /
## composite / rivers / tectonics base / graph base) are rendered full-res by
## WorldMapPainter, then sampled into the cell; noise/mono stay local.
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
	if kind != "noise" and height.is_empty():
		return

	# Painter-backed kinds: build the full-res colorized image once, sample below.
	var src_img: Image = null
	var czr := _make_colorizer(oth, mth)
	match kind:
		"topo", "tectonics":
			# Pure terrain bands + ocean, no river/lake pixels: hand the painter a
			# snapshot view without the water sets.
			src_img = WorldMapPainter.composite_image({"height": height}, w, h, oth, czr)
		"composite", "graph":
			src_img = WorldMapPainter.composite_image(data, w, h, oth, czr)
		"rivers":
			src_img = WorldMapPainter.water_only_image(data, w, h, oth, czr, false)

	for ty in range(cell_px):
		for tx in range(cell_px):
			var ox: int = mini(int(tx / scale), w - 1)
			var oy: int = mini(int(ty / scale), h - 1)
			var idx: int = (oy * w) + ox
			var col: Color
			match kind:
				"noise":
					col = mono_color(noise_im.get_pixel(ox, oy).r)
				"mono":
					# Monotone land height only; below sea reads as flat dark so land pops.
					if height[idx] < oth:
						col = SUBSTRATE
					else:
						col = mono_color((height[idx] - oth) / maxf(0.001, 1.0 - oth))
				_:
					col = src_img.get_pixel(ox, oy)
					if col.a == 0.0:
						col = SUBSTRATE  # rivers sheet is transparent off-water
			img.set_pixel(off.x + tx, off.y + ty, col)

	match kind:
		"tectonics":
			_burn_tectonics(img, data, off, scale)
		"graph":
			_burn_graph(img, off, scale, true)  # colored view: curved roads

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

## Graph view from the exported gameplay graph (GraphPlacement.export_graph):
## each node's out-edges carry their routed polyline, drawn white with a midpoint
## direction arrowhead (`curved=false` forces straight segments). Nodes: green
## start, red end, blue interior; ferry edges tinted cyan.
func _burn_graph(img: Image, offset: Vector2i, scale: float, curved: bool = false) -> void:
	var ge: Dictionary = generator.snapshots.get("Graph", {}).get("graph_export", {})
	if ge.is_empty():
		return
	var nodes: Array = ge["nodes"]  # ordered by compact id -> index == id
	for nd in nodes:
		for e in nd["out"]:
			var pts: PackedVector2Array = e["points"] if curved \
				else PackedVector2Array([nd["pos"], nodes[e["to"]]["pos"]])
			var col: Color = Color("#7dd3fc") if e["ferry"] else Color.WHITE
			for i in range(pts.size() - 1):
				_plot_line(img, (pts[i] * scale) + Vector2(offset),
					(pts[i + 1] * scale) + Vector2(offset), col)
			if pts.size() >= 2:
				var m: int = maxi(1, pts.size() / 2)
				_plot_arrowhead(img, (pts[m - 1] * scale) + Vector2(offset),
					(pts[m] * scale) + Vector2(offset), Color("#fb923c"), maxf(3.0, 6.0 * scale))
	for nd in nodes:
		var p: Vector2 = (nd["pos"] * scale) + Vector2(offset)
		if nd["id"] == int(ge["start"]):
			_plot_disc(img, p, maxf(3.0, 6.0 * scale), Color.GREEN)
		elif nd["id"] == int(ge["end"]):
			_plot_disc(img, p, maxf(3.0, 6.0 * scale), Color.RED)
		else:
			_plot_disc(img, p, maxf(1.5, 3.0 * scale), Color("#60a5fa"))

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
