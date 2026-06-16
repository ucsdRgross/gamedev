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

const LAYER_WINDOW := 1  # edges advance one layer at a time (so node-count between
						 # cities == the layer gap); widened only if a layer is empty

# Parallel node arrays (index-based for speed); emitted as Vector2-keyed at the end.
var _pos: Array[Vector2] = []
var _is_city: PackedByteArray = PackedByteArray()
var _landmass: PackedInt32Array = PackedInt32Array()
var _biome: PackedInt32Array = PackedInt32Array()
var _height: PackedFloat32Array = PackedFloat32Array()
var _layer: PackedInt32Array = PackedInt32Array()
var _dead: PackedByteArray = PackedByteArray()  # nodes culled by the repair pass
var _spine: PackedVector2Array = PackedVector2Array()  # meandering start->end progress curve
var _adj: Dictionary = {}   # int -> Array[int]
var _injected := 0

var _gen: WorldGenerator
var _settings: WorldSettings
var _dir := Vector2.RIGHT
var _start_i := -1
var _end_i := -1
var _axis_len := 1.0
var _inter_edges := 0

func build(gen: WorldGenerator, settings: WorldSettings) -> Dictionary:
	_gen = gen
	_settings = settings
	_gather_nodes()
	if _pos.size() < 2:
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
		_build_intra_landmass_edges()
		_build_water_edges()
		_ensure_min_water_edges()
		_failsafe_connect()
		_prune_unreachable()
		_failsafe_connect()  # re-guarantee after prune
		if pass_i < passes - 1:
			_repair_nodes()

	return _emit()

## Clear all edges/counters so a fresh pass can rebuild from the current (possibly
## repaired) node set. Node positions/layers/is_city/dead flags are preserved.
func _reset_edges() -> void:
	for i in range(_pos.size()):
		_adj[i] = []
	_inter_edges = 0
	_injected = 0

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

	# Clear non-city nodes off the city layers (nudge to the previous layer) so a
	# city layer contains cities only -> a guaranteed bottleneck.
	var clset := {}
	for cl in city_layers:
		clset[cl] = true
	for i in range(n):
		if i == _start_i or i == _end_i:
			continue
		if _is_city[i] == 0 and clset.has(_layer[i]):
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
# Intra-landmass forward edges (scored), per node
# ---------------------------------------------------------------------------
func _build_intra_landmass_edges() -> void:
	var buckets := _nodes_by_layer()
	var lc := _settings.layer_count
	for u in range(_pos.size()):
		if _layer[u] >= lc or _dead[u] == 1:
			continue  # end layer / culled node: no outgoing
		var cands: Array = _gather_candidates(u, buckets, lc)
		if cands.is_empty():
			continue
		cands.sort_custom(func(a, b): return a["score"] < b["score"])
		var want := mini(_settings.max_outgoing, cands.size())
		want = maxi(want, mini(_settings.min_outgoing, cands.size()))
		var chosen: Array[int] = []
		for k in range(want):
			chosen.append(cands[k]["i"])
		_adj[u] = chosen

func _gather_candidates(u: int, buckets: Array, lc: int) -> Array:
	var out: Array = []
	var lu := _layer[u]
	var window := LAYER_WINDOW
	# Expand the layer window if nothing close is found (failsafe-ish), so a node
	# isn't orphaned just because its immediate layers are sparse.
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
			# Intra-landmass only here; water edges handled separately.
			if _landmass[v] != _landmass[u] or _landmass[u] < 0:
				continue
			var d := _pos[u].distance_to(_pos[v])
			if d < _settings.min_path_dist or d > _settings.max_path_search_dist:
				continue
			# Same-landmass travel must stay on land; reject edges that clip a
			# bay/strait (that is what "water travel" between landmasses is for).
			if _edge_crosses_ocean(_pos[u], _pos[v]):
				continue
			var score := d
			# Lateral spread: reward candidates far to the SIDE of the start->end
			# axis (tapered to 0 at both ends so paths still converge on the goal).
			# This fans the graph across the continent instead of beelining.
			if _settings.graph_lateral_spread > 0.0:
				var perp := Vector2(-_dir.y, _dir.x)
				var lateral: float = absf((_pos[v] - _pos[_start_i]).dot(perp))
				var taper: float = sin(PI * float(lv) / float(lc))  # 0 at ends, 1 mid
				score -= _settings.graph_lateral_spread * lateral * taper
			# Mountain-pass preference: through high terrain, favor lower / closer
			# height targets so paths thread the passes, not the peaks.
			if _height[u] >= mt or _height[v] >= mt:
				score += _settings.mountain_pass_bias * 100.0 * (_height[v] + absf(_height[v] - _height[u]))
			# Mild nudge toward biome variety (kept small; windows are validated).
			if _biome[v] != _biome[u]:
				score -= _settings.min_path_dist * 0.1
			out.append({"i": v, "score": score})
	return out

# ---------------------------------------------------------------------------
# Inter-landmass (water) edges: connect consecutive landmasses by their cheapest
# ocean-only crossing. Treats landmasses as super-nodes ordered along the axis.
# ---------------------------------------------------------------------------
func _build_water_edges() -> void:
	if _gen.landmass_sizes.size() < 2:
		return
	var order := _landmass_order()
	for k in range(order.size() - 1):
		if _inter_edges >= _settings.max_inter_landmass_edges:
			break
		_connect_landmasses(order[k], order[k + 1])

func _landmass_order() -> Array:
	# Order kept landmass ids by centroid projection along the travel axis.
	var centroids: Dictionary = {}
	var counts: Dictionary = {}
	for i in range(_pos.size()):
		var lm := _landmass[i]
		if lm < 0:
			continue
		centroids[lm] = centroids.get(lm, Vector2.ZERO) + _pos[i]
		counts[lm] = counts.get(lm, 0) + 1
	var ids: Array = centroids.keys()
	var projs: Dictionary = {}
	for lm in ids:
		projs[lm] = ((centroids[lm] / float(counts[lm])) - _pos[_start_i]).dot(_dir)
	ids.sort_custom(func(a, b): return projs[a] < projs[b])
	return ids

## Add the closest valid water edge between two landmasses (forward in layers,
## ocean-only straight line, within max_water_crossing_dist). Returns true if added.
func _connect_landmasses(a: int, b: int) -> bool:
	var nodes_a: Array = []
	var nodes_b: Array = []
	for i in range(_pos.size()):
		if _dead[i] == 1: continue
		if _landmass[i] == a: nodes_a.append(i)
		elif _landmass[i] == b: nodes_b.append(i)
	# Pick the GLOBALLY closest ocean-only pair (least water crossed). We do NOT
	# pre-filter on layer order here -- doing so used to reject the true nearest
	# crossing and instead land deep inside the other continent. Orientation
	# (for acyclicity) is decided afterwards from the chosen pair.
	var best := -1.0
	var bu := -1; var bv := -1
	for u in nodes_a:
		for v in nodes_b:
			var d := _pos[u].distance_to(_pos[v])
			if d > _settings.max_water_crossing_dist:
				continue
			if best >= 0.0 and d >= best:
				continue
			if not _ocean_only_between(_pos[u], _pos[v]):
				continue
			best = d; bu = u; bv = v
	if bu < 0:
		return false
	# Orient the crossing forward: from the earlier-layer node to the later one
	# (tie-break on axis projection). Bump the destination layer if needed so the
	# DAG stays acyclic without distorting which physical nodes are linked. Never
	# push a layer past the final layer (would overflow the per-layer arrays).
	var lc := _settings.layer_count
	if _layer[bv] < _layer[bu] or (_layer[bv] == _layer[bu] \
			and _pos[bv].dot(_dir) < _pos[bu].dot(_dir)):
		var t := bu; bu = bv; bv = t
	if _layer[bv] <= _layer[bu]:
		if _layer[bu] >= lc:
			return false  # source already at the final layer: no forward room
		_layer[bv] = mini(_layer[bu] + 1, lc)
	if not _adj[bu].has(bv):
		_adj[bu].append(bv)
		_inter_edges += 1
	return true

func _ensure_min_water_edges() -> void:
	# If below the minimum, try additional crossings between any landmass pair.
	if _gen.landmass_sizes.size() < 2:
		return
	var order := _landmass_order()
	var guard := 0
	while _inter_edges < _settings.min_inter_landmass_edges and guard < 50:
		guard += 1
		var added := false
		for k in range(order.size() - 1):
			if _inter_edges >= _settings.max_inter_landmass_edges:
				return
			if _connect_landmasses(order[k], order[k + 1]):
				added = true
		if not added:
			return

## True if more than a quarter of the straight line runs over ocean (matches
## GraphRules._crosses_ocean, used to keep same-landmass edges on land).
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

## Straight line touches land only at the endpoints (all interior samples ocean).
func _ocean_only_between(a: Vector2, b: Vector2) -> bool:
	var w := _settings.map_width
	var h := _settings.map_height
	var steps := maxi(8, int(a.distance_to(b) / 3.0))
	for s in range(1, steps):
		var p := a.lerp(b, float(s) / float(steps))
		var px := clampi(int(p.x), 0, w - 1)
		var py := clampi(int(p.y), 0, h - 1)
		if _gen.height_buffer[(py * w) + px] >= _settings.ocean_threshold:
			return false
	return true

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

# ---------------------------------------------------------------------------
# Failsafe: guarantee at least one start->end path exists. If not, inject nodes
# along the straight start->end line (matching the spec's "create a node in the
# gap" idea) and chain them, bounded by failsafe_max_injected_nodes.
# ---------------------------------------------------------------------------
func _failsafe_connect() -> void:
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

## How many other live same-landmass nodes sit within max_path_search_dist of
## node i -- a proxy for how many edges it could form (connectivity / population).
func _reach_count(i: int) -> int:
	var c := 0
	var lm := _landmass[i]
	if lm < 0:
		return 0
	var r := _settings.max_path_search_dist
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
	_gen.gameplay_graph = graph
	_gen.start_node = start_pos
	_gen.end_node = end_pos
	# Validated city set = cities that survived into the graph (bright in viewer).
	var cities: Array[Vector2] = []
	for p in meta.keys():
		if meta[p]["is_city"]:
			cities.append(p)
	_gen.city_nodes = cities

	return {"graph": graph, "start": start_pos, "end": end_pos, "meta": meta, "injected": _injected}
