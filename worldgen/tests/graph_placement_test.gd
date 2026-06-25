extends Node

## Step-B visual + robustness test (run with F6).
##
## Part 1 (named specs): for each spec x seed, generate a real map, build the
## abstract graph, place it, write init/mid/final PNGs to res://placement_debug/,
## and report on-land %, settle steps, edge-length spread, and water-edge rule
## violations (water crossings must run between TWO coastal nodes).
##
## Part 2 (chaos fuzz): many random specs with random params on random maps. Must
## not crash; reports aggregate on-land % and worst cases. A few are rendered.

const OUT_DIR := "res://placement_debug/"

@export var named_seeds: Array[int] = [1, 2, 3]
@export var chaos_count: int = 40
@export var chaos_render: int = 6      # how many chaos cases to also render

# Placement levers. v2: multi-landmass by breadth, structured init, edges built
# after settle.
# LADDER levers: min_width/max_width = sections per rung at thinnest/widest land; jitter =
# fraction of rung spacing to randomly offset nodes; landmass_min_frac = ignore small isles.
const PLACE_OPTS := {"min_width": 1, "max_width": 5, "jitter": 0.5, "landmass_min_frac": 0.12}

# {name, cities, nbc, outgoing}. v4 placement uses only: cities & nbc -> rung count (D),
# and `out` -> max edges per node. The old `w`/`lmin`/`lmax` no longer affect placement
# (the grid generates node counts from land width), so they're dropped here.
const SPECS := [
	{"name": "medium", "cities": 5,  "nbc": 2, "out": 3},
	{"name": "wide",   "cities": 4,  "nbc": 2, "out": 3},
	{"name": "big",    "cities": 8,  "nbc": 3, "out": 4},
	{"name": "huge",   "cities": 12, "nbc": 4, "out": 5},
]

# Apply a spec onto WorldSettings. build_nodes(cities,nbc,...) sets the rung count via
# `ranks`; _create_edges reads spec_outgoing for the per-node edge cap.
func _apply_spec(bs: WorldSettings, spec: Dictionary) -> void:
	bs.spec_cities = spec["cities"]
	bs.spec_nodes_between_cities = spec["nbc"]
	bs.spec_outgoing = spec["out"]

var _gen: WorldGenerator
var _coast_radius: float

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_clear_pngs()                            # drop stale images (e.g. old _2_mid) so renders stay consistent
	_gen = WorldGenerator.new()
	add_child(_gen)
	await get_tree().process_frame

	print("=== GraphPlacement test ===")
	print("-- named specs --")
	for sd in named_seeds:
		var bs := WorldSettings.new()
		bs.main_seed = sd
		_gen.settings = bs
		await _gen.generate_base_through_civilizations()
		var field := GraphPlacement.MapField.from_generator(_gen)
		_coast_radius = bs.coast_radius_ratio * bs.map_diag()
		for spec in SPECS:
			_apply_spec(bs, spec)
			var g := GraphSpec.build_nodes(spec["cities"], spec["nbc"], 2, 5, sd)   # lmin/lmax unused by v4 placement
			var res := GraphPlacement.place(g, field, bs, sd, PLACE_OPTS)
			_report(spec["name"], sd, g, res, field)
			_render(g, res, field, spec["name"], sd)

	print("-- chaos fuzz: %d random specs --" % chaos_count)
	await _run_chaos()
	print("=== GraphPlacement test complete (images in %s) ===" % OUT_DIR)
	get_tree().quit()

func _clear_pngs() -> void:
	var dir := DirAccess.open(OUT_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".png"):
			dir.remove(f)

func _run_chaos() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909090
	var total_on_land := 0.0
	var worst := 1.0
	var worst_desc := ""
	var rendered := 0
	# Reuse a few maps across chaos cases (map gen is the slow part).
	for ci in range(chaos_count):
		var sd := rng.randi_range(1, 9999)
		var bs := WorldSettings.new()
		bs.main_seed = sd
		_gen.settings = bs
		await _gen.generate_base_through_civilizations()
		var field := GraphPlacement.MapField.from_generator(_gen)
		_coast_radius = bs.coast_radius_ratio * bs.map_diag()
		var cities := rng.randi_range(2, 16)
		var nbc := rng.randi_range(0, 8)
		var lmin := rng.randi_range(1, 5)
		var lmax := rng.randi_range(lmin, lmin + 6)
		_apply_spec(bs, {"cities": cities, "nbc": nbc, "w": rng.randi_range(1, 12),
			"out": rng.randi_range(1, 8), "lmin": lmin, "lmax": lmax})
		var g := GraphSpec.build_nodes(cities, nbc, lmin, lmax, sd)
		var res := GraphPlacement.place(g, field, bs, sd, PLACE_OPTS)
		var pos: PackedVector2Array = res["pos"]
		var active: PackedByteArray = res["active"]
		var label := "ch%d[c%d n%d L%d-%d]" % [ci, cities, nbc, lmin, lmax]
		_report(label, sd, g, res, field)
		var on_land := 0
		var kept := 0
		for i in range(pos.size()):
			if active[i] == 0:
				continue
			kept += 1
			if field.is_land(pos[i]):
				on_land += 1
		var frac := float(on_land) / maxf(1, kept)
		total_on_land += frac
		if frac < worst:
			worst = frac
			worst_desc = "c=%d nbc=%d lmin=%d lmax=%d seed=%d (%d kept)" % [
				cities, nbc, lmin, lmax, sd, kept]
		if rendered < chaos_render:
			_render(g, res, field, "chaos%d" % ci, sd)
			rendered += 1
	print("  chaos done: avg on_land=%.0f%%, worst=%.0f%% [%s]" % [
		100.0 * total_on_land / maxf(1, chaos_count), 100.0 * worst, worst_desc])

func _report(name: String, sd: int, g: Dictionary, res: Dictionary, field) -> void:
	var pos: PackedVector2Array = res["pos"]
	var active: PackedByteArray = res["active"]
	var on_land := 0
	var kept := 0
	for i in range(pos.size()):
		if active[i] == 0:
			continue
		kept += 1
		if field.is_land(pos[i]):
			on_land += 1
	var adj: Array = res["ctx"].adj
	var lo := INF
	var hi := -INF
	var sum := 0.0
	var cnt := 0
	for u in range(adj.size()):
		for v in adj[u]:
			var d: float = pos[u].distance_to(pos[v])
			lo = minf(lo, d); hi = maxf(hi, d); sum += d; cnt += 1
	var water_bad: int = GraphPlacement.water_edge_violations(res["ctx"]).size()
	var st: Dictionary = res.get("edge_stats", {})
	print("  %-12s seed%d: kept=%d/%d on_land=%d (%.0f%%) edges=%d reaches_end=%s water_viol=%d edgelen avg=%.0f [%.0f..%.0f]" % [
		name, sd, kept, pos.size(), on_land, 100.0 * on_land / maxi(1, kept),
		st.get("edges", cnt), str(st.get("reaches_end", false)), water_bad,
		sum / maxf(1, cnt), lo, hi])

# ---------------------------------------------------------------------------
func _render(g: Dictionary, res: Dictionary, field, name: String, sd: int) -> void:
	var base := _base_image(field)
	var ctx = res["ctx"]
	# Init: nodes only. Final: straight edges. Detail: terrain-fitting curved edges.
	_draw_graph(base.duplicate(), ctx, res["init_pos"], [], "%s%s_s%d_1_init.png" % [OUT_DIR, name, sd])
	_draw_graph(base.duplicate(), ctx, res["pos"], _straight_curves(ctx), "%s%s_s%d_3_final.png" % [OUT_DIR, name, sd])
	var curves := GraphDetail.compute_curves(ctx, field)
	_draw_graph(base.duplicate(), ctx, res["pos"], curves, "%s%s_s%d_4_curved.png" % [OUT_DIR, name, sd])

# Straight one-segment polylines per edge (for the pre-detail final image).
func _straight_curves(ctx) -> Array:
	var out: Array = []
	for u in range(ctx.n):
		if ctx.active[u] == 0:
			continue
		for v in ctx.adj[u]:
			out.append([u, v, PackedVector2Array([ctx.pos[u], ctx.pos[v]])])
	return out

func _base_image(field) -> Image:
	var w: int = field.w
	var h: int = field.h
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var ht: float = field.height[(y * w) + x]
			var col: Color
			if ht >= field.oth:
				var t := clampf((ht - field.oth) / maxf(0.001, 1.0 - field.oth), 0.0, 1.0)
				col = Color(0.25, 0.45, 0.25).lerp(Color(0.6, 0.55, 0.4), t)
			else:
				col = Color(0.12, 0.18, 0.35)
			img.set_pixel(x, y, col)
	return img

func _draw_graph(img: Image, ctx, pos: PackedVector2Array, curves: Array, path: String) -> void:
	for e in curves:                         # each curve = [u, v, PackedVector2Array points]
		var pts: PackedVector2Array = e[2]
		for i in range(pts.size() - 1):
			_line(img, pts[i], pts[i + 1], Color(0.9, 0.9, 0.95))
	var maxd: int = ctx.max_depth
	for id in range(ctx.n):
		if ctx.active[id] == 0:
			continue
		var p: Vector2 = pos[id]
		var d: int = ctx.depth[id]
		var col := Color(0.9, 0.3, 0.3)      # all nodes one type for now
		if d == 0:
			col = Color(0.2, 1, 0.3)
		elif d == maxd:
			col = Color(0.3, 0.6, 1)
		_disc(img, p, 1.8, col)
	img.save_png(path)

func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / steps)
		_px(img, int(p.x), int(p.y), col)

func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy <= r * r:
				_px(img, int(c.x) + dx, int(c.y) + dy, col)

func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)
