class_name GraphBuilder
extends RefCounted

## Builds the traversal graph: a layered, acyclic directed graph over the dense
## travel_nodes with city_nodes as anchors. Edges only ever advance to a later
## layer along the start->end spread axis, so there is no backtracking and a node
## is never revisited. See plan Part A.
##
## build() is pure w.r.t. the heightmap/biome buffers (read-only); it writes the
## result onto the generator (gameplay_graph / start_node / end_node / city_nodes)
## and returns a result Dictionary the stats + rule validators consume:
##   { graph: {Vector2 -> Array[Vector2]}, start: Vector2, end: Vector2,
##     meta: {Vector2 -> {biome, landmass, is_city, height}},
##     injected: int }
##
## Hard rules enforced here: no water nodes (Step6 already placed nodes on land),
## acyclic/no-revisit (layer ordering), outgoing-degree bounds, water edges only
## between different landmasses across an ocean-only straight line, inter-landmass
## edge cap, connectivity (failsafe). Count windows (nodes-between-cities, biomes,
## path length, cities-visited) are shaped softly and verified by GraphRules.

const LAYER_WINDOW := 2  # edges may reach up to 2 layers ahead, giving the scorer
						 # real choices (so anti-straight / zig-zag actually bite and
						 # the graph can explore laterally instead of a rigid 1-step chain)

# Parallel node arrays (index-based for speed); emitted as Vector2-keyed at the end.
var _pos: Array[Vector2] = []
var _is_city: PackedByteArray = PackedByteArray()
var _landmass: PackedInt32Array = PackedInt32Array()
var _biome: PackedInt32Array = PackedInt32Array()
var _height: PackedFloat32Array = PackedFloat32Array()
var _layer: PackedInt32Array = PackedInt32Array()
var _dead: PackedByteArray = PackedByteArray()  # nodes culled by the repair pass
var _spine: PackedVector2Array = PackedVector2Array()  # meandering start->end progress curve
var _band_cross_in: PackedInt32Array = PackedInt32Array()  # cross-ocean incoming edges per band
var _lat: PackedFloat32Array = PackedFloat32Array()    # signed perpendicular distance from spine
var _tan: Array[Vector2] = []                          # spine tangent at each node's nearest sample
var _adj: Dictionary = {}   # int -> Array[int]
var _injected := 0

var _gen: WorldGenerator
var _settings: WorldSettings
var _dir := Vector2.RIGHT
var _start_i := -1
var _end_i := -1
var _axis_len := 1.0
var _inter_edges := 0
var _write_to_gen := true
# Per-build seeded RNG (not the global randf) so builds are deterministic and
# safe to run concurrently on worker threads without racing a shared generator.
var _rng := RandomNumberGenerator.new()
# Pixel values derived once per build from resolution-independent ratios.
var _water_cross_px := 0.0
var _reach_radius := 0.0
var _coast_px := 0.0

## write_to_gen=false makes build side-effect-free: it returns the result dict but
## does NOT write gen.gameplay_graph/start_node/end_node/city_nodes. The param-search
## harness passes false so many builds can run on worker threads against the same
## read-only base buffers without racing on shared gen state.
func build(gen: WorldGenerator, settings: WorldSettings, write_to_gen: bool = true) -> Dictionary:
	_gen = gen
	_settings = settings
	_write_to_gen = write_to_gen
	_rng.seed = hash([settings.main_seed, settings.layer_count, settings.edge_trim_chance])
	var diag := settings.map_diag()
	_water_cross_px = settings.water_crossing_ratio * diag
	_reach_radius = maxf(8.0, settings.travel_dist_ratio * diag * 4.0)
	_coast_px = maxf(6.0, diag * 0.017)  # coastal-detection ring (~12px at 512)
	_gather_nodes()
	if _pos.size() < 2:
		if write_to_gen:
			gen.gameplay_graph = {}
		return {"graph": {}, "start": Vector2.ZERO, "end": Vector2.ZERO, "meta": {}, "injected": 0}

	_pick_start_end()
	_build_spine()
	_assign_layers()
	_designate_city_layers()

	# Multi-pass: build the whole graph, diagnose problems, modify the node set
	# (cull dead stubs, fill empty layers), then rebuild. The final pass emits.
	var passes := maxi(1, _settings.graph_build_passes)
	for pass_i in range(passes):
		_reset_edges()
		_build_edges()          # land + cross-ocean edges, unified
		_failsafe_connect()
		_prune_unreachable()
		_failsafe_connect()  # re-guarantee after prune
		if pass_i < passes - 1:
			_repair_nodes()

	_trim_edges()           # break the perfect NxN lattice for variety
	_prune_unreachable()    # drop anything the trim stranded
	_failsafe_connect()     # guarantee a path still exists

	return _emit()

## Randomly drop surplus edges so fan-in/fan-out isn't a perfect lattice (e.g.
## 3 nodes -> 3 nodes all-to-all). Never drops below min_outgoing and never
## removes a child's last incoming edge, so connectivity/degree stay valid.
func _trim_edges() -> void:
	if _settings.edge_trim_chance <= 0.0:
		return
	var indeg := {}
	for u in range(_pos.size()):
		for v in _adj[u]:
			indeg[v] = indeg.get(v, 0) + 1
	var floor_deg := maxi(1, _settings.min_outgoing_after_trim)
	for u in range(_pos.size()):
		var kept: Array[int] = []
		for v in _adj[u]:
			if kept.size() < floor_deg:
				kept.append(v)
				continue
			if indeg.get(v, 0) > 1 and _rng.randf() < _settings.edge_trim_chance:
				indeg[v] -= 1  # drop this edge
			else:
				kept.append(v)
		_adj[u] = kept

## Clear all edges/counters so a fresh pass can rebuild from the current (possibly
## repaired) node set. Node positions/layers/is_city/dead flags are preserved.
func _reset_edges() -> void:
	for i in range(_pos.size()):
		_adj[i] = []
	_inter_edges = 0
	_injected = 0
	_band_cross_in = PackedInt32Array()
	_band_cross_in.resize(_settings.layer_count + 1)
	_band_cross_in.fill(0)

## Between passes: use the just-built graph to modify nodes, so the next pass is
## cleaner. (1) Cull interior nodes the prune left with no outgoing edge (dead
## stubs). (2) Inject a land node into any empty interior layer so every step is
## a single layer (avoids long skip-edges across gaps).
func _repair_nodes() -> void:
	var lc := _settings.layer_count
	for u in range(_pos.size()):
		if u == _start_i or u == _end_i or _dead[u] == 1:
			continue
		if _layer[u] < lc and _adj[u].is_empty():
			_dead[u] = 1

	var live := PackedInt32Array(); live.resize(lc + 1); live.fill(0)
	for u in range(_pos.size()):
		if _dead[u] == 0:
			live[_layer[u]] += 1
	var w := _settings.map_width
	var h := _settings.map_height
	for l in range(1, lc):
		if live[l] > 0:
			continue
		var p := _nearest_land(_pos[_start_i].lerp(_pos[_end_i], float(l) / float(lc)))
		_append_node(p, false, w, h)
		var ni := _pos.size() - 1
		_adj[ni] = []
		_layer[ni] = l

# ---------------------------------------------------------------------------
# Node gathering + per-node metadata
# ---------------------------------------------------------------------------
func _gather_nodes() -> void:
	var w := _settings.map_width
	var h := _settings.map_height
	# Cities first (anchors), then travel nodes.
	for c in _gen.city_nodes:
		_append_node(c, true, w, h)
	for t in _gen.travel_nodes:
		_append_node(t, false, w, h)
	_adj.clear()
	for i in range(_pos.size()):
		_adj[i] = []

func _append_node(p: Vector2, is_city: bool, w: int, h: int) -> void:
	var px := clampi(int(p.x), 0, w - 1)
	var py := clampi(int(p.y), 0, h - 1)
	var idx := (py * w) + px
	_pos.append(p)
	_is_city.append(1 if is_city else 0)
	_landmass.append(Step6Civilizations.landmass_at(_gen, p))
	_biome.append(_gen.biome_id_buffer[idx])
	_height.append(_gen.height_buffer[idx])
	_layer.append(0)
	_dead.append(0)
	_lat.append(0.0)
	_tan.append(_dir)

# ---------------------------------------------------------------------------
# Start/end via principal spread axis, biased away from small islands
# ---------------------------------------------------------------------------
func _pick_start_end() -> void:
	# Covariance of node positions -> dominant eigenvector = spread axis.
	var n := _pos.size()
	var mean := Vector2.ZERO
	for p in _pos:
		mean += p
	mean /= float(n)
	var cxx := 0.0; var cyy := 0.0; var cxy := 0.0
	for p in _pos:
		var d := p - mean
		cxx += d.x * d.x; cyy += d.y * d.y; cxy += d.x * d.y
	var theta := 0.5 * atan2(2.0 * cxy, cxx - cyy)
	var axis := Vector2(cos(theta), sin(theta))

	# Largest landmass id is 0 (Step6 sorts by size); penalize starting/ending on
	# any smaller landmass so runs don't begin/end on a tiny island.
	# ALSO penalize poorly-connected candidates (few nearby same-landmass nodes) so
	# start/end land somewhere that can form several connections -- a believable
	# high-population terminus, not an isolated dot that yields a single edge.
	var needed_conn := maxi(2, _settings.start_end_min_connections)
	var best_lo := INF; var best_hi := -INF
	var lo_i := 0; var hi_i := 0
	for i in range(n):
		if _is_city[i] == 0:
			continue
		var proj := _pos[i].dot(axis)
		var island_pen: float = 0.0 if _landmass[i] == 0 else _settings.start_end_island_penalty
		var reach := _reach_count(i)
		if reach < needed_conn:
			island_pen += _settings.start_end_island_penalty * float(needed_conn - reach)
		if proj + island_pen < best_lo:
			best_lo = proj + island_pen; lo_i = i
		if proj - island_pen > best_hi:
			best_hi = proj - island_pen; hi_i = i
	# Fallback to any node if there are too few cities.
	if best_lo == INF or best_hi == -INF or lo_i == hi_i:
		lo_i = 0; hi_i = n - 1
		var plo := INF; var phi := -INF
		for i in range(n):
			var pr := _pos[i].dot(axis)
			if pr < plo: plo = pr; lo_i = i
			if pr > phi: phi = pr; hi_i = i

	_start_i = lo_i
	_end_i = hi_i
	_dir = (_pos[_end_i] - _pos[_start_i])
	_axis_len = maxf(1.0, _dir.length())
	_dir = _dir.normalized()

# ---------------------------------------------------------------------------
# Layer assignment (progress along start->end), start=0, end=layer_count
# ---------------------------------------------------------------------------
## Layer = progress along the (meandering) spine: each node is bucketed by the
## arc position of its nearest spine sample. Because the spine bulges into the
## landmass, "forward" follows the continent's body rather than the straight
## chord, so the graph spreads across more terrain instead of beelining.
func _assign_layers() -> void:
	var lc := _settings.layer_count
	var samples := _spine.size()
	for i in range(_pos.size()):
		var bestd := INF
		var bi := 0
		for s in range(samples):
			var dd := _pos[i].distance_squared_to(_spine[s])
			if dd < bestd:
				bestd = dd; bi = s
		_layer[i] = clampi(int(round(float(bi) / float(maxi(1, samples - 1)) * float(lc))), 0, lc)
		# Spine tangent + signed perpendicular offset (the 2nd grid axis).
		var sa := _spine[bi]
		var sb := _spine[mini(bi + 1, samples - 1)]
		var tang := sb - sa
		tang = tang.normalized() if tang.length() > 0.001 else _dir
		_tan[i] = tang
		var rel := _pos[i] - sa
		_lat[i] = (rel.x * -tang.y) + (rel.y * tang.x)  # signed cross => side of spine
	_layer[_start_i] = 0
	_layer[_end_i] = lc

## A smooth start->end curve that bulges into the landmass at a few control
## points, so layering follows the continent's body. Control points are snapped
## to land and pushed toward whichever side has more land, then Catmull-Rom
## smoothed. Falls back to a near-straight line when the terrain is symmetric.
func _build_spine() -> void:
	var a := _pos[_start_i]
	var b := _pos[_end_i]
	var ctrl: Array[Vector2] = [a]
	for f in [0.25, 0.5, 0.75]:
		var base := _nearest_land(a.lerp(b, f))
		ctrl.append(_bulge_into_land(base, a, b))
	ctrl.append(b)
	_spine = _catmull_rom(ctrl, 16)

## Offset a spine control point perpendicular to the chord toward the side with
## more land reach (bounded), keeping it on land.
func _bulge_into_land(base: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var perp := (b - a).normalized().orthogonal()
	var cap := minf(0.3 * a.distance_to(b), 120.0)
	var land_r := _land_extent(base, perp)
	var land_l := _land_extent(base, -perp)
	var off := clampf(float(land_r - land_l) * 8.0, -cap, cap)
	return _nearest_land(base + perp * off)

## How many 10px steps of continuous land extend from p along dir (stops at the
## first ocean cell or after ~130px).
func _land_extent(p: Vector2, dir: Vector2) -> int:
	var steps := 0
	for d in range(10, 140, 10):
		if _is_land(p + dir * float(d)):
			steps += 1
		else:
			break
	return steps

func _is_land(p: Vector2) -> bool:
	var w := _settings.map_width
	var h := _settings.map_height
	var px := clampi(int(p.x), 0, w - 1)
	var py := clampi(int(p.y), 0, h - 1)
	return _gen.height_buffer[(py * w) + px] >= _settings.ocean_threshold

## Uniform Catmull-Rom through the control points -> dense sampled polyline.
func _catmull_rom(pts: Array, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		for p in pts:
			out.append(p)
		return out
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		for s in range(seg):
			var t := float(s) / float(seg)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[pts.size() - 1])
	return out

## Enforce nodes-between-cities: pick evenly-spaced "city layers" and make each a
## bottleneck containing only cities, so EVERY path crosses a city there. With
## one-layer edge steps, the travel-node count between consecutive cities equals
## the layer gap minus one, which we choose inside [min,max]_nodes_between_cities.
## Cities not on a city layer are demoted to travel nodes; empty city layers
## promote their nearest node to a city (matches the spec's "create a node" idea).
func _designate_city_layers() -> void:
	var lc := _settings.layer_count
	var between := clampi(
		int(round((_settings.min_nodes_between_cities + _settings.max_nodes_between_cities) / 2.0)),
		_settings.min_nodes_between_cities, _settings.max_nodes_between_cities)
	var gap := maxi(2, between + 1)  # layers between consecutive cities

	var city_layers: Array[int] = []
	var L := gap
	while L < lc:
		city_layers.append(L)
		L += gap

	var n := _pos.size()
	var keep_city := {}  # node index kept as a city
	for cl in city_layers:
		var has := false
		for i in range(n):
			if i == _start_i or i == _end_i:
				continue
			if _is_city[i] == 1 and _layer[i] == cl:
				keep_city[i] = true; has = true
		if not has:
			# Promote the node nearest this layer (then a city is guaranteed here).
			var best := -1; var best_d := 1 << 30
			for i in range(n):
				if i == _start_i or i == _end_i or _is_city[i] == 1:
					continue
				var d: int = absi(_layer[i] - cl)
				if d < best_d:
					best_d = d; best = i
			if best >= 0:
				_layer[best] = cl; _is_city[best] = 1; keep_city[best] = true

	# Demote cities that did not land on a city layer.
	for i in range(n):
		if i == _start_i or i == _end_i:
			continue
		if _is_city[i] == 1 and not keep_city.has(i):
			_is_city[i] = 0

	# Bottleneck strength: nudge only a FRACTION of non-city nodes off the city
	# layers. At 1.0 a city layer holds cities only (strict funnel); at 0.0 nothing
	# is moved (cities are ordinary anchors, paths may bypass them). The fraction is
	# chosen deterministically per node so the result is stable across passes.
	var strength: float = clampf(_settings.city_bottleneck_strength, 0.0, 1.0)
	var clset := {}
	for cl in city_layers:
		clset[cl] = true
	for i in range(n):
		if i == _start_i or i == _end_i:
			continue
		if _is_city[i] == 0 and clset.has(_layer[i]):
			# Deterministic [0,1) keyed on node index; move when below strength.
			var r: float = fmod(float(i) * 0.61803398875, 1.0)
			if r < strength:
				_layer[i] = maxi(0, _layer[i] - 1)

func _nodes_by_layer() -> Array:
	var lc := _settings.layer_count
	var buckets: Array = []
	for l in range(lc + 1):
		buckets.append([])
	for i in range(_pos.size()):
		buckets[_layer[i]].append(i)
	return buckets

# ---------------------------------------------------------------------------
# Unified forward edges (land + cross-ocean), per node. Bands ignore oceans, so
# a forward neighbour may sit across water; such cross-ocean edges are allowed
# ONLY onto a coastal city and capped at max_cross_ocean_per_band INCOMING per
# band (covers same-landmass bay crossings AND different-landmass crossings).
# ---------------------------------------------------------------------------
func _build_edges() -> void:
	var buckets := _nodes_by_layer()
	var lc := _settings.layer_count
	for u in range(_pos.size()):
		if _layer[u] >= lc or _dead[u] == 1:
			continue  # end layer / culled node: no outgoing
		var cands: Array = _gather_candidates(u, buckets, lc)
		if cands.is_empty():
			continue
		cands.sort_custom(func(a, b): return a["score"] < b["score"])
		var chosen: Array[int] = []
		for c in cands:
			if chosen.size() >= _settings.max_outgoing:
				break
			var v: int = c["i"]
			if c["cross"]:
				# Cross-ocean edge: only onto a coastal city, and only if this band
				# still has an incoming-water slot free.
				if _is_city[v] == 0 or not _is_coastal(v):
					continue
				if _band_cross_in[_layer[v]] >= _settings.max_cross_ocean_per_band:
					continue
				_band_cross_in[_layer[v]] += 1
			chosen.append(v)
		_adj[u] = chosen

func _gather_candidates(u: int, buckets: Array, lc: int) -> Array:
	var out: Array = []
	var lu := _layer[u]
	var window := LAYER_WINDOW
	while out.is_empty() and lu + 1 <= lc:
		out = _candidates_in_window(u, buckets, lc, window)
		if not out.is_empty():
			break
		window += LAYER_WINDOW
		if lu + window > lc + LAYER_WINDOW:
			break
	return out

func _candidates_in_window(u: int, buckets: Array, lc: int, window: int) -> Array:
	var out: Array = []
	var lu := _layer[u]
	var mt := _settings.mountain_threshold
	for lv in range(lu + 1, mini(lu + window, lc) + 1):
		for v in buckets[lv]:
			if _dead[v] == 1:
				continue
			var edge := _pos[v] - _pos[u]
			var d := edge.length()
			var edir := edge / maxf(d, 0.001)
			var along: float = absf(edir.dot(_tan[u]))
			# Is this a water crossing? (different landmass, or the straight line
			# runs mostly over ocean -- a bay/strait on the same landmass).
			var cross: bool = (_landmass[v] != _landmass[u]) or (_landmass[u] < 0) or _edge_crosses_ocean(_pos[u], _pos[v])
			# Candidates are simply the nodes in the next band(s); we do NOT gate land
			# edges by a hardcoded pixel radius (that didn't scale with map/node
			# density). The only hard reach limit is for water crossings, which must
			# stay within the water-crossing reach (else a graph could span an ocean).
			if cross and d > _water_cross_px:
				continue
			# Nearer next-band nodes score better (so each node connects to its closest
			# forward neighbours), then the usual shape penalties apply.
			var score := d
			# Anti-straight: penalize edges that beeline at the goal.
			score += _settings.graph_anti_straight * along * d
			# Zig-zag guard: discourage crossing back over the spine centerline.
			if signf(_lat[u]) != signf(_lat[v]) and absf(_lat[u]) > 8.0 and absf(_lat[v]) > 8.0:
				score += _settings.graph_zigzag_penalty
			# Water travel costs extra so land routes are preferred where they exist.
			if cross:
				score += d * 0.5 + 30.0
			# Mountain-pass preference.
			if _height[u] >= mt or _height[v] >= mt:
				score += _settings.mountain_pass_bias * 100.0 * (_height[v] + absf(_height[v] - _height[u]))
			# Mild biome-variety nudge (relative to the edge's own length, so it stays
			# scale-free now that there is no min_path_dist to key off).
			if _biome[v] != _biome[u]:
				score -= d * 0.05
			out.append({"i": v, "score": score, "cross": cross})
	return out

## True if more than a quarter of the straight line runs over ocean (a bay/strait).
func _edge_crosses_ocean(a: Vector2, b: Vector2) -> bool:
	var w := _settings.map_width
	var h := _settings.map_height
	var steps := maxi(8, int(a.distance_to(b) / 3.0))
	var ocean := 0
	for s in range(1, steps):
		var p := a.lerp(b, float(s) / float(steps))
		var px := clampi(int(p.x), 0, w - 1)
		var py := clampi(int(p.y), 0, h - 1)
		if _gen.height_buffer[(py * w) + px] < _settings.ocean_threshold:
			ocean += 1
	return float(ocean) / float(maxi(1, steps - 1)) > 0.25

## A node is coastal if ocean sits within the coastal ring (map-relative) on a
## sampled ring.
func _is_coastal(i: int) -> bool:
	var w := _settings.map_width
	var h := _settings.map_height
	var p := _pos[i]
	for ang in range(0, 360, 45):
		var rad := deg_to_rad(float(ang))
		var nx := clampi(int(p.x + cos(rad) * _coast_px), 0, w - 1)
		var ny := clampi(int(p.y + sin(rad) * _coast_px), 0, h - 1)
		if _gen.height_buffer[(ny * w) + nx] < _settings.ocean_threshold:
			return true
	return false

# ---------------------------------------------------------------------------
# Reachability prune: keep only nodes on some start->end path. Nodes whose
# (unchosen) outgoing left them unable to reach end are dropped entirely.
# ---------------------------------------------------------------------------
func _prune_unreachable() -> void:
	var n := _pos.size()
	# Forward reachable from start.
	var fwd := PackedByteArray(); fwd.resize(n); fwd.fill(0)
	var stack: Array[int] = [_start_i]; fwd[_start_i] = 1
	while not stack.is_empty():
		var u: int = stack.pop_back()
		for v in _adj[u]:
			if fwd[v] == 0:
				fwd[v] = 1; stack.push_back(v)
	# Backward reachable to end (reverse adjacency).
	var rev: Dictionary = {}
	for i in range(n): rev[i] = []
	for u in range(n):
		for v in _adj[u]:
			rev[v].append(u)
	var back := PackedByteArray(); back.resize(n); back.fill(0)
	stack = [_end_i]; back[_end_i] = 1
	while not stack.is_empty():
		var u: int = stack.pop_back()
		for v in rev[u]:
			if back[v] == 0:
				back[v] = 1; stack.push_back(v)
	# Keep nodes on a start->end path; rewrite adjacency to kept-only edges.
	for u in range(n):
		var keep_u: bool = fwd[u] == 1 and back[u] == 1
		if not keep_u:
			_adj[u] = []
			continue
		var kept: Array[int] = []
		for v in _adj[u]:
			if fwd[v] == 1 and back[v] == 1:
				kept.append(v)
		_adj[u] = kept

## Bidirectional join: the layered build can fragment into spatially separate
## "lanes", so start's forward component may never reach the specific end node even
## when both touch every layer. Grow the forward set (from start) and the backward
## set (reaching end); while they're disjoint, add the cheapest forward bridge
## edge from a forward node to a backward node on a later layer. A handful of
## bridges merges the components without throwing away the existing graph.
func _stitch_components() -> void:
	var n := _pos.size()
	var lc := _settings.layer_count
	for _attempt in range(6):
		var fwd := _reach_set(_start_i, false)   # forward from start
		if fwd[_end_i] == 1:
			return                               # connected
		var back := _reach_set(_end_i, true)     # backward to end (reverse edges)
		var best_u := -1; var best_v := -1; var best_cost := INF
		for u in range(n):
			if _dead[u] == 1 or fwd[u] == 0 or _layer[u] >= lc:
				continue
			for v in range(n):
				if _dead[v] == 1 or back[v] == 0 or _layer[v] <= _layer[u]:
					continue
				var cost := _pos[u].distance_to(_pos[v]) + float(_layer[v] - _layer[u]) * 8.0
				if cost < best_cost:
					best_cost = cost; best_u = u; best_v = v
		if best_u < 0:
			return                               # nothing to bridge with -> caller injects
		if not _adj[best_u].has(best_v):
			_adj[best_u].append(best_v)

## Reachable-node bitmask from `src`. reverse=false follows _adj (forward),
## reverse=true follows incoming edges (who can reach src).
func _reach_set(src: int, reverse: bool) -> PackedByteArray:
	var n := _pos.size()
	var seen := PackedByteArray(); seen.resize(n); seen.fill(0)
	var rev: Dictionary = {}
	if reverse:
		for i in range(n):
			rev[i] = []
		for u in range(n):
			for v in _adj[u]:
				rev[v].append(u)
	var stack: Array[int] = [src]; seen[src] = 1
	while not stack.is_empty():
		var u: int = stack.pop_back()
		var nbrs: Array = rev[u] if reverse else _adj[u]
		for v in nbrs:
			if seen[v] == 0:
				seen[v] = 1; stack.push_back(v)
	return seen

# ---------------------------------------------------------------------------
# Failsafe: guarantee at least one start->end path exists. First try to STITCH
# the start-forward component to the end-backward component with minimal bridge
# edges through existing nodes (bidirectional join -- keeps the rich graph). Only
# if that can't connect them do we inject a straight chain (last resort).
# ---------------------------------------------------------------------------
func _failsafe_connect() -> void:
	if _reaches_end():
		return
	_stitch_components()
	if _reaches_end():
		return
	var lc := _settings.layer_count
	var budget := _settings.failsafe_max_injected_nodes
	var prev := _start_i
	var w := _settings.map_width
	var h := _settings.map_height
	for step in range(1, lc + 1):
		var t := float(step) / float(lc)
		var node_i: int
		if step == lc:
			node_i = _end_i
		else:
			if budget <= 0:
				break
			var p := _nearest_land(_pos[_start_i].lerp(_pos[_end_i], t))
			_append_node(p, false, w, h)
			node_i = _pos.size() - 1
			_adj[node_i] = []
			_layer[node_i] = clampi(int(t * lc), 0, lc)
			_injected += 1
			budget -= 1
		if not _adj[prev].has(node_i):
			_adj[prev].append(node_i)
		prev = node_i

## Nearest above-sea pixel to p (spiral-ish ring search); falls back to p if the
## whole neighbourhood is ocean. Keeps failsafe-injected nodes out of the water.
func _nearest_land(p: Vector2) -> Vector2:
	var w := _settings.map_width
	var h := _settings.map_height
	var px := clampi(int(p.x), 0, w - 1)
	var py := clampi(int(p.y), 0, h - 1)
	if _gen.height_buffer[(py * w) + px] >= _settings.ocean_threshold:
		return p
	for r in range(4, 64, 4):
		for a in range(0, 360, 30):
			var rad := deg_to_rad(a)
			var nx := clampi(px + int(cos(rad) * r), 0, w - 1)
			var ny := clampi(py + int(sin(rad) * r), 0, h - 1)
			if _gen.height_buffer[(ny * w) + nx] >= _settings.ocean_threshold:
				return Vector2(nx, ny)
	return p

## How many other live same-landmass nodes sit within a density-relative radius of
## node i -- a proxy for how many edges it could form (connectivity / population).
## Radius scales with the travel-node spacing (travel_dist_ratio x map diagonal)
## instead of a fixed pixel value, so it adapts to map size / node density.
func _reach_count(i: int) -> int:
	var c := 0
	var lm := _landmass[i]
	if lm < 0:
		return 0
	var r := _reach_radius
	for j in range(_pos.size()):
		if j == i or _dead[j] == 1 or _landmass[j] != lm:
			continue
		if _pos[i].distance_to(_pos[j]) <= r:
			c += 1
	return c

func _reaches_end() -> bool:
	var n := _pos.size()
	var seen := PackedByteArray(); seen.resize(n); seen.fill(0)
	var stack: Array[int] = [_start_i]; seen[_start_i] = 1
	while not stack.is_empty():
		var u: int = stack.pop_back()
		if u == _end_i:
			return true
		for v in _adj[u]:
			if seen[v] == 0:
				seen[v] = 1; stack.push_back(v)
	return false

# ---------------------------------------------------------------------------
# Emit Vector2-keyed graph + metadata onto the generator
# ---------------------------------------------------------------------------
func _emit() -> Dictionary:
	var graph: Dictionary = {}
	var meta: Dictionary = {}
	var used: Dictionary = {}
	for u in range(_pos.size()):
		if _adj[u].is_empty() and u != _end_i:
			continue
		used[u] = true
		for v in _adj[u]:
			used[v] = true
	# Build adjacency + meta only for used nodes.
	for u in used.keys():
		var children: Array[Vector2] = []
		for v in _adj[u]:
			children.append(_pos[v])
		graph[_pos[u]] = children
		meta[_pos[u]] = {
			"biome": _biome[u], "landmass": _landmass[u],
			"is_city": _is_city[u] == 1, "height": _height[u],
		}
	if not graph.has(_pos[_end_i]):
		graph[_pos[_end_i]] = []
		meta[_pos[_end_i]] = {
			"biome": _biome[_end_i], "landmass": _landmass[_end_i],
			"is_city": _is_city[_end_i] == 1, "height": _height[_end_i],
		}

	var start_pos := _pos[_start_i]
	var end_pos := _pos[_end_i]
	# Validated city set = cities that survived into the graph (bright in viewer).
	var cities: Array[Vector2] = []
	for p in meta.keys():
		if meta[p]["is_city"]:
			cities.append(p)
	if _write_to_gen:
		_gen.gameplay_graph = graph
		_gen.start_node = start_pos
		_gen.end_node = end_pos
		_gen.city_nodes = cities

	return {"graph": graph, "start": start_pos, "end": end_pos, "meta": meta, "injected": _injected}
