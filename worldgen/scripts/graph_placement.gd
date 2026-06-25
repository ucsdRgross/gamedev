class_name GraphPlacement
extends RefCounted

## Step B of graph placement: GENERATE the gameplay graph directly on the real map as a
## LADDER overlaid on the land, then connect it with one forward sweep.
##  - `_make_ctx` lays D rungs (= spec depth) along the land's principal axis; each rung
##    is an independent slice divided into width-scaled, jittered sections (one node each).
##  - `_create_edges` connects each rung to the next by geometry (nearest same-landmass
##    node forward, ±locality branch), with coverage that guarantees start->end
##    connectivity by construction (no repair) and ferries across islands.
##  - Pure data (PackedArrays / Dictionaries) so it is thread-safe for the harness.
##  - Step C (GraphDetail) turns the straight edges into terrain-fitting curves.

# ---------------------------------------------------------------------------
# Map sampling field -- built once from the generator's height buffer. Thread-safe.
# ---------------------------------------------------------------------------
class MapField extends RefCounted:
	var w: int
	var h: int
	var oth: float                       # ocean threshold: land = height >= oth
	var height: PackedFloat32Array
	var land_min := Vector2.ZERO         # bounding box of the TARGET landmass
	var land_max := Vector2.ZERO
	var land_centroid := Vector2.ZERO
	# Connected-component landmass labels (cell -> id, -1 = water). The graph is
	# confined to `main_label` (the largest landmass) so it can't zigzag between
	# islands across water.
	var label := PackedInt32Array()
	var sizes := {}                      # landmass id -> cell count
	var label_seed := {}                 # landmass id -> a representative land cell
	var main_label := -1
	var total_land := 0                  # total land cells (all landmasses)
	var domain_land := 0                 # land cells in the graph's domain
	# Domain = the landmass(es) the graph may occupy. Default: confine to the largest
	# landmass (emergent multi-landmass collapses; clean multi-landmass needs ports).
	var confine_main := true

	## Is this cell inside the graph's allowed domain?
	func in_domain(p: Vector2) -> bool:
		if not in_bounds(p):
			return false
		var l := label[(int(p.y) * w) + int(p.x)]
		return l == main_label if confine_main else l >= 0
	func _dom_cell(x: int, y: int) -> bool:
		var l := label[(y * w) + x]
		return l == main_label if confine_main else l >= 0
	# Blue-noise land sample lattice. Graph nodes are attracted to / snapped to these
	# so they can never end up in water.
	var samples := PackedVector2Array()
	var sample_label := PackedInt32Array() # landmass id per sample
	var _shash := {}                     # Vector2i cell -> Array[int] sample indices
	var _cs := 1.0                       # hash cell size (= sample spacing)
	# Signed distance-to-coast field (positive inland = dist to water, negative in
	# water = -dist to land), on a downscaled grid. Powers land attraction (gradient
	# defined even in deep ocean), O(1) coastal test, and the Step C routing cost.
	var dt := PackedFloat32Array()
	var _dtds := 1                       # downscale factor
	var _dtw := 0
	var _dth := 0

	static func from_generator(gen, opts: Dictionary = {}) -> MapField:
		var f := MapField.new()
		f.w = gen.settings.map_width
		f.h = gen.settings.map_height
		f.oth = gen.settings.ocean_threshold
		f.height = gen.height_buffer
		f.confine_main = opts.get("landmass_mode", "multi") == "largest"
		f._label_landmasses()
		f.domain_land = f.sizes.get(f.main_label, 0) if f.confine_main else f.total_land
		f._measure_land()
		f._build_distance_transform(opts.get("dt_downscale", 2))
		# Dense enough that every graph node finds a distinct nearby land sample.
		var spacing: float = gen.settings.map_diag() * opts.get("sample_spacing_ratio", 0.012)
		f.build_land_samples(spacing, gen.settings.main_seed, opts.get("poisson", true))
		return f

	# --- Distance transform (two-pass chamfer, signed) -----------------------
	func _build_distance_transform(downscale: int) -> void:
		_dtds = maxi(1, downscale)
		_dtw = int(ceil(float(w) / _dtds))
		_dth = int(ceil(float(h) / _dtds))
		var n := _dtw * _dth
		var to_water := PackedFloat32Array(); to_water.resize(n)
		var to_land := PackedFloat32Array(); to_land.resize(n)
		var BIG := 1e9
		for gy in range(_dth):
			for gx in range(_dtw):
				var i := gy * _dtw + gx
				var landcell := height[(mini(gy * _dtds, h - 1) * w) + mini(gx * _dtds, w - 1)] >= oth
				to_water[i] = BIG if landcell else 0.0
				to_land[i] = 0.0 if landcell else BIG
		_chamfer(to_water)
		_chamfer(to_land)
		dt = PackedFloat32Array(); dt.resize(n)
		for gy in range(_dth):
			for gx in range(_dtw):
				var i := gy * _dtw + gx
				var landcell := height[(mini(gy * _dtds, h - 1) * w) + mini(gx * _dtds, w - 1)] >= oth
				dt[i] = (to_water[i] if landcell else -to_land[i]) * _dtds

	func _chamfer(d: PackedFloat32Array) -> void:
		const OR := 1.0
		const DI := 1.41421356
		for gy in range(_dth):           # forward
			for gx in range(_dtw):
				var i := gy * _dtw + gx
				var m := d[i]
				if gx > 0: m = minf(m, d[i - 1] + OR)
				if gy > 0: m = minf(m, d[i - _dtw] + OR)
				if gx > 0 and gy > 0: m = minf(m, d[i - _dtw - 1] + DI)
				if gx < _dtw - 1 and gy > 0: m = minf(m, d[i - _dtw + 1] + DI)
				d[i] = m
		for gy in range(_dth - 1, -1, -1): # backward
			for gx in range(_dtw - 1, -1, -1):
				var i := gy * _dtw + gx
				var m := d[i]
				if gx < _dtw - 1: m = minf(m, d[i + 1] + OR)
				if gy < _dth - 1: m = minf(m, d[i + _dtw] + OR)
				if gx < _dtw - 1 and gy < _dth - 1: m = minf(m, d[i + _dtw + 1] + DI)
				if gx > 0 and gy < _dth - 1: m = minf(m, d[i + _dtw - 1] + DI)
				d[i] = m

	func dt_at(p: Vector2) -> float:
		var gx := clampi(int(p.x / _dtds), 0, _dtw - 1)
		var gy := clampi(int(p.y / _dtds), 0, _dth - 1)
		return dt[gy * _dtw + gx]

	## Inland-pointing gradient of the signed field (toward increasing dt = land).
	## Defined and nonzero even in deep ocean, unlike the raw height gradient.
	func dt_gradient(p: Vector2) -> Vector2:
		var gx := clampi(int(p.x / _dtds), 1, _dtw - 2)
		var gy := clampi(int(p.y / _dtds), 1, _dth - 2)
		var gxv := dt[gy * _dtw + gx + 1] - dt[gy * _dtw + gx - 1]
		var gyv := dt[(gy + 1) * _dtw + gx] - dt[(gy - 1) * _dtw + gx]
		return Vector2(gxv, gyv)

	## Flood-fill connected components of land; pick the largest as `main_label`.
	func _label_landmasses() -> void:
		label = PackedInt32Array()
		label.resize(w * h)
		label.fill(-1)
		sizes = {}
		var cur := 0
		for sy in range(h):
			for sx in range(w):
				var si := sy * w + sx
				if height[si] < oth or label[si] != -1:
					continue
				var cnt := 0
				var stack: Array[int] = [si]
				label[si] = cur
				label_seed[cur] = Vector2(sx, sy)
				while not stack.is_empty():
					var idx: int = stack.pop_back()
					cnt += 1
					var x := idx % w
					var y := idx / w
					for off : Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx := x + off.x
						var ny := y + off.y
						if nx < 0 or ny < 0 or nx >= w or ny >= h:
							continue
						var ni := ny * w + nx
						if height[ni] >= oth and label[ni] == -1:
							label[ni] = cur
							stack.push_back(ni)
				sizes[cur] = cnt
				total_land += cnt
				cur += 1
		var best := -1
		for id in sizes.keys():
			if best < 0 or sizes[id] > sizes[best]:
				best = id
		main_label = best

	func label_at(p: Vector2) -> int:
		if not in_bounds(p):
			return -1
		return label[(int(p.y) * w) + int(p.x)]

	## On the target (main) landmass specifically.
	func is_main_land(p: Vector2) -> bool:
		return label_at(p) == main_label

	## Land samples on ALL landmasses. Bridson Poisson-disk (blue-noise) by default;
	## falls back to a jittered grid if `poisson` is false.
	func build_land_samples(spacing: float, seed_val: int, poisson: bool = true) -> void:
		_cs = maxf(2.0, spacing)
		samples = PackedVector2Array()
		_shash = {}
		if poisson:
			_poisson_samples(_cs, seed_val)
		else:
			_jittered_samples(_cs, seed_val)
		sample_label = PackedInt32Array()
		sample_label.resize(samples.size())
		for idx in range(samples.size()):
			sample_label[idx] = label_at(samples[idx])
			var key := Vector2i(int(samples[idx].x / _cs), int(samples[idx].y / _cs))
			if not _shash.has(key):
				_shash[key] = []
			_shash[key].append(idx)

	func _jittered_samples(cs: float, seed_val: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val * 100069
		var gx := int(ceil(w / cs))
		var gy := int(ceil(h / cs))
		for cy in range(gy):
			for cx in range(gx):
				var p := Vector2((cx + rng.randf()) * cs, (cy + rng.randf()) * cs)
				if in_domain(p):
					samples.append(p)

	## Bridson's algorithm: blue-noise points >= r apart, kept only on land.
	func _poisson_samples(r: float, seed_val: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val * 100069
		var cell := r / sqrt(2.0)
		var gw := int(ceil(w / cell))
		var gh := int(ceil(h / cell))
		var grid := PackedInt32Array()
		grid.resize(gw * gh)
		grid.fill(-1)
		var active: Array[int] = []
		# Seed ONE point per landmass in the domain. Bridson grows only within a
		# connected reachable region (can't jump open ocean), so a single seed would
		# sample just one island -- every separate landmass needs its own seed.
		for lab in label_seed.keys():
			var seed_pt: Vector2 = label_seed[lab]
			if in_domain(seed_pt) and _poisson_ok(seed_pt, grid, gw, gh, cell, r):
				_add_poisson(seed_pt, grid, gw, gh, cell, active)
		if active.is_empty():                       # no land in domain
			return
		while not active.is_empty():
			var ai := rng.randi_range(0, active.size() - 1)
			var center: Vector2 = samples[active[ai]]
			var found := false
			for _k in range(30):
				var ang := rng.randf() * TAU
				var rad := r * (1.0 + rng.randf())
				var cand := center + Vector2(cos(ang), sin(ang)) * rad
				if not in_domain(cand):
					continue
				if _poisson_ok(cand, grid, gw, gh, cell, r):
					_add_poisson(cand, grid, gw, gh, cell, active)
					found = true
					break
			if not found:
				active.remove_at(ai)

	func _add_poisson(p: Vector2, grid: PackedInt32Array, gw: int, gh: int, cell: float, active: Array[int]) -> void:
		var idx := samples.size()
		samples.append(p)
		active.append(idx)
		grid[int(p.y / cell) * gw + int(p.x / cell)] = idx

	func _poisson_ok(p: Vector2, grid: PackedInt32Array, gw: int, gh: int, cell: float, r: float) -> bool:
		var cx := int(p.x / cell)
		var cy := int(p.y / cell)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
					continue
				var si := grid[ny * gw + nx]
				if si >= 0 and samples[si].distance_to(p) < r:
					return false
		return true

	func _find_any_land() -> Vector2:
		for y in range(h):
			for x in range(w):
				if _dom_cell(x, y):
					return Vector2(x, y)
		return land_centroid

	## Index of the nearest land sample to p; -1 if none. `skip` marks already-used
	## sample indices to ignore (collision-free snapping). `target_label` >= 0 limits
	## to samples on that landmass.
	func nearest_sample_idx(p: Vector2, skip: Dictionary = {}, target_label: int = -1, allowed: Dictionary = {}) -> int:
		if samples.is_empty():
			return -1
		var cx := int(p.x / _cs)
		var cy := int(p.y / _cs)
		var best := -1
		var best_d := INF
		var best_ring := -1
		var ring := 0
		var max_ring := int(maxf(w, h) / _cs) + 1
		while ring <= max_ring:
			for dy in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					if maxi(absi(dx), absi(dy)) != ring:
						continue          # only the new ring shell
					var key := Vector2i(cx + dx, cy + dy)
					if not _shash.has(key):
						continue
					for idx in _shash[key]:
						if skip.has(idx):
							continue
						if target_label >= 0 and sample_label[idx] != target_label:
							continue
						if not allowed.is_empty() and not allowed.has(sample_label[idx]):
							continue
						var d: float = p.distance_squared_to(samples[idx])
						if d < best_d:
							best_d = d; best = idx
			if best >= 0 and best_ring < 0:
				best_ring = ring
			# Scan one full ring beyond the first hit (a farther shell can be closer).
			if best_ring >= 0 and ring >= best_ring + 1:
				break
			ring += 1
		return best

	func nearest_sample(p: Vector2) -> Vector2:
		var i := nearest_sample_idx(p)
		return samples[i] if i >= 0 else land_centroid

	## Bounding box + centroid of the graph's domain (largest landmass by default).
	func _measure_land() -> void:
		var lo := Vector2(w, h)
		var hi := Vector2.ZERO
		var sum := Vector2.ZERO
		var n := 0
		for y in range(h):
			for x in range(w):
				if _dom_cell(x, y):
					lo.x = minf(lo.x, x); lo.y = minf(lo.y, y)
					hi.x = maxf(hi.x, x); hi.y = maxf(hi.y, y)
					sum += Vector2(x, y); n += 1
		if n == 0:
			land_min = Vector2.ZERO; land_max = Vector2(w, h)
			land_centroid = Vector2(w, h) * 0.5
		else:
			land_min = lo; land_max = hi; land_centroid = sum / n

	func in_bounds(p: Vector2) -> bool:
		return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h

	func height_at(p: Vector2) -> float:
		var x := clampi(int(p.x), 0, w - 1)
		var y := clampi(int(p.y), 0, h - 1)
		return height[(y * w) + x]

	func is_land(p: Vector2) -> bool:
		return height_at(p) >= oth

	## Uphill height gradient (points toward higher ground / away from ocean).
	func gradient(p: Vector2) -> Vector2:
		var x := clampi(int(p.x), 1, w - 2)
		var y := clampi(int(p.y), 1, h - 2)
		var gx := height[(y * w) + x + 1] - height[(y * w) + x - 1]
		var gy := height[((y + 1) * w) + x] - height[((y - 1) * w) + x]
		return Vector2(gx, gy)

	## Land within `radius` of open water -> eligible for water travel. O(1) via DT
	## (dt is +distance-to-water on land), replacing the old neighbourhood scan.
	func is_coastal(p: Vector2, radius: float) -> bool:
		var d := dt_at(p)
		return d >= 0.0 and d <= radius

	## Principal-axis description of a land distribution (from the samples):
	## { center, axis, perp, amin, amax, pmin, pmax } in axis/perp coordinates relative
	## to center. The oval grid is laid along this so depth flows along the land's
	## longest dimension and the layout is centred on the actual land, not outliers.
	## `lab` >= 0 restricts to that landmass's samples (per-landmass oval); else all land.
	func land_pca(lab: int = -1) -> Dictionary:
		var pts := PackedVector2Array()
		if lab < 0:
			pts = samples
		else:
			for i in range(samples.size()):
				if sample_label[i] == lab:
					pts.append(samples[i])
			if pts.is_empty():
				pts = samples
		var n := pts.size()
		if n == 0:
			return {"center": land_centroid, "axis": Vector2(1, 0), "perp": Vector2(0, 1),
				"amin": -float(w) * 0.5, "amax": float(w) * 0.5, "pmin": -float(h) * 0.5, "pmax": float(h) * 0.5}
		var mean := Vector2.ZERO
		for s in pts:
			mean += s
		mean /= n
		var sxx := 0.0; var sxy := 0.0; var syy := 0.0
		for s in pts:
			var d := s - mean
			sxx += d.x * d.x; sxy += d.x * d.y; syy += d.y * d.y
		sxx /= n; sxy /= n; syy /= n
		var tr := sxx + syy
		var l1 := tr * 0.5 + sqrt(maxf(0.0, tr * tr * 0.25 - (sxx * syy - sxy * sxy)))
		var axis: Vector2
		if absf(sxy) > 1e-6:
			axis = Vector2(l1 - syy, sxy).normalized()
		else:
			axis = Vector2(1, 0) if sxx >= syy else Vector2(0, 1)
		var perp := Vector2(-axis.y, axis.x)
		var amin := INF; var amax := -INF; var pmin := INF; var pmax := -INF
		for s in pts:
			var d := s - mean
			var a := d.dot(axis); var p := d.dot(perp)
			amin = minf(amin, a); amax = maxf(amax, a)
			pmin = minf(pmin, p); pmax = maxf(pmax, p)
		return {"center": mean, "axis": axis, "perp": perp,
			"amin": amin, "amax": amax, "pmin": pmin, "pmax": pmax}

	## On-land perp coordinates of landmass `lab` along the slice line at axis-coord `a`
	## (line = origin + axis*a + perp*p, p in [pmin,pmax]). Used to spread a depth row's
	## nodes evenly across the island's ACTUAL width at that slice (2D grid cross-section).
	func slice_land_coords(origin: Vector2, axis: Vector2, perp: Vector2, a: float, pmin: float, pmax: float, lab: int, step: float) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		var base := origin + axis * a
		var p := pmin
		while p <= pmax:
			var wp := base + perp * p
			if label_at(wp) == lab:
				out.append(p)
			p += step
		return out

# ---------------------------------------------------------------------------
# Shared placement context (positions, depths, lanes, edges).
# ---------------------------------------------------------------------------
class Ctx extends RefCounted:
	var field: MapField
	var s: WorldSettings
	var pos: PackedVector2Array          # node id -> position
	var depth: PackedInt32Array          # node id -> rank
	var is_city: PackedByteArray         # node id -> 1 if city
	var max_depth: int
	var adj: Array                       # node id -> Array[int] forward neighbours
	var n: int
	var start_id: int
	var end_id: int
	var start_pos: Vector2
	var end_pos: Vector2
	var axis: Vector2                    # start->end direction (normalised)
	var perp: Vector2                    # axis rotated 90deg (lane spread direction)
	var node_label: PackedInt32Array     # node id -> assigned landmass id
	var active: PackedByteArray          # node id -> 1 if kept
	var lane: PackedInt32Array           # node id -> section index within its rung
	var coast_radius: float              # a node within this of water counts as coastal
	var lane_tol := 1.8                  # branch locality: extra forward links allowed only
										 # within this x the nearest one's distance (a ratio,
										 # so scale-free across map sizes). Tunable via opts.

# ---------------------------------------------------------------------------
# Public entry point.
# ---------------------------------------------------------------------------
## Place `graph` (a GraphSpec dict) on `field`. Returns a result dict with the placed
## context, the (one-shot) positions, and edge stats. `active` flags kept nodes.
static func place(graph: Dictionary, field: MapField, settings: WorldSettings,
		seed_val: int, opts: Dictionary = {}) -> Dictionary:
	# Placement (division + 2D cross-section grid + trimming) happens in _make_ctx;
	# positions are final and one-shot, so init/mid mirror the final layout.
	var ctx := _make_ctx(graph, field, settings, seed_val, opts)
	var init_pos := ctx.pos.duplicate()
	var mid_pos := ctx.pos.duplicate()

	# DIAGNOSTIC (remove later): node-share vs area-share per island (should track),
	# plus how many nodes were trimmed at thin slices.
	var _dist := {}
	var _kept := 0
	for i in range(ctx.n):
		if ctx.active[i] == 0:
			continue
		_kept += 1
		var l := ctx.node_label[i]
		_dist[l] = _dist.get(l, 0) + 1
	var _area_sum := 0
	for l in _dist.keys():
		_area_sum += field.sizes.get(l, 0)
	var _parts := []
	for l in _dist.keys():
		var node_pct :float= 100.0 * _dist[l] / maxi(1, _kept)
		var area_pct :float= 100.0 * field.sizes.get(l, 0) / maxi(1, _area_sum)
		_parts.append("%d:%dn(%.0f%%nodes/%.0f%%area)" % [l, _dist[l], node_pct, area_pct])
	print("    [JIGSAW] kept %d/%d nodes, %d islands: %s" % [_kept, ctx.n, _dist.size(), str(_parts)])

	# Edge creation -- ONE geography-aware forward sweep on the placed nodes.
	var edge_stats := _create_edges(ctx, graph, settings)

	return {"pos": ctx.pos, "ctx": ctx, "steps": 0, "init_pos": init_pos,
		"mid_pos": mid_pos, "edge_stats": edge_stats, "active": ctx.active}

# ---------------------------------------------------------------------------
# Pure-data export for gameplay traversal.
# ---------------------------------------------------------------------------
## Export the final graph as plain data the game can walk: compact node ids, per-node
## properties (position, depth/layer, landmass, height, biome), and forward edges with
## their routed curve points. `curves` is GraphDetail.compute_curves(...) output (each
## [u, v, points]); pass [] to use straight segments. `opts.biome_fn` is an optional
## Callable(Vector2)->int for the biome at a node (else -1).
## Traversal: from a node, pick any entry in `out` (each advances toward `end`); follow
## `points` for the 2D path; stop at `end`. `depth` is the layer (0 = start, max = end).
static func export_graph(ctx: Ctx, field: MapField, curves: Array = [], opts: Dictionary = {}) -> Dictionary:
	var has_biome: bool = opts.has("biome_fn")
	var biome_fn: Callable = opts.get("biome_fn", Callable())
	var pts_of := {}                                    # Vector2i(u,v) -> routed polyline
	for e in curves:
		pts_of[Vector2i(e[0], e[1])] = e[2]
	var id_map := {}                                    # old id -> compact id (drop inactive)
	var compact := 0
	for i in range(ctx.n):
		if ctx.active[i] == 1:
			id_map[i] = compact; compact += 1
	var nodes: Array = []
	for i in range(ctx.n):
		if ctx.active[i] == 0:
			continue
		var outs: Array = []
		for v in ctx.adj[i]:
			if ctx.active[v] == 0:
				continue
			var ferry := ctx.node_label[i] != ctx.node_label[v] or edge_crosses_water(field, ctx.pos[i], ctx.pos[v])
			var pts: PackedVector2Array = pts_of.get(Vector2i(i, v), PackedVector2Array([ctx.pos[i], ctx.pos[v]]))
			outs.append({"to": id_map[v], "ferry": ferry, "points": pts})
		nodes.append({
			"id": id_map[i],
			"pos": ctx.pos[i],
			"depth": ctx.depth[i],
			"landmass": ctx.node_label[i],
			"height": field.height_at(ctx.pos[i]),
			"biome": (biome_fn.call(ctx.pos[i]) if has_biome else -1),
			"out": outs,
		})
	return {
		"start": id_map.get(ctx.start_id, 0),
		"end": id_map.get(ctx.end_id, 0),
		"max_depth": ctx.max_depth,
		"nodes": nodes,
	}

# ---------------------------------------------------------------------------
# Edge creation -- ONE forward sweep, depth row by depth row (Slay-the-Spire).
# ---------------------------------------------------------------------------
## Single forward sweep over the populated depths. Within a step each node connects to its
## STRAIGHT-AHEAD same-landmass node plus at most one adjacent lane (+-1), so travel goes
## forward, not sideways. Coverage in the SAME step guarantees every node gets an incoming
## (reachable from start) and an outgoing (reaches end, since depth D is just `end`), so
## connectivity holds BY CONSTRUCTION -- no repair pass. Cross-island steps are legal
## ferries (coastal-to-coastal); a crossing is forced only as a last resort.
static func _create_edges(ctx: Ctx, graph: Dictionary, settings: WorldSettings) -> Dictionary:
	var D: int = ctx.max_depth
	var max_out: int = maxi(1, settings.spec_outgoing)
	var indeg := PackedInt32Array(); indeg.resize(ctx.n)
	var edges: Array = []                       # [u, v] for crossing tests
	# Active nodes grouped by depth; only populated depths take part in the sweep.
	var by_depth: Array = []
	by_depth.resize(D + 1)
	for d in range(D + 1):
		by_depth[d] = []
	for i in range(ctx.n):
		if ctx.active[i] == 1:
			by_depth[ctx.depth[i]].append(i)
	var pop: Array = []
	for d in range(D + 1):
		if not by_depth[d].is_empty():
			pop.append(d)
	for pi in range(pop.size() - 1):
		_connect_rows(ctx, by_depth[pop[pi]], by_depth[pop[pi + 1]], edges, indeg, max_out)

	var reaches_end := _reaches_id(ctx.adj, ctx.start_id, ctx.end_id)
	var total := 0
	for u in range(ctx.n):
		total += ctx.adj[u].size()
	return {"edges": total, "reaches_end": reaches_end}

## One forward step: connect row U (depth d) to row V (next populated depth).
static func _connect_rows(ctx: Ctx, U: Array, V: Array, edges: Array, indeg: PackedInt32Array, max_out: int) -> void:
	# 1. Forward to the NEAREST same-landmass node ("0 forward lane" -> short, never
	#    cross-landmass), plus extra branches within `lane_tol` x that nearest distance.
	#    If the nearest would cross a (local) same-landmass edge, skip to the next nearest
	#    that doesn't -- a LOCAL crossing fix (the next candidate is usually the neighbour's
	#    target, i.e. share the destination). Crossing prevention applies to on-land edges
	#    only; long ferries are NOT blocked here (they get curved in Step C).
	for u in U:
		var same: Array = []
		for v in V:
			if ctx.node_label[v] == ctx.node_label[u]:
				same.append(v)
		if same.is_empty():
			continue
		same.sort_custom(func(a, b):
			return ctx.pos[u].distance_squared_to(ctx.pos[a]) < ctx.pos[u].distance_squared_to(ctx.pos[b]))
		var d0: float = ctx.pos[u].distance_to(ctx.pos[same[0]])
		var cap: float = maxf(d0 * ctx.lane_tol, d0 + 1.0)
		var taken := 0
		for v in same:
			if taken >= max_out:
				break
			if taken >= 1 and ctx.pos[u].distance_to(ctx.pos[v]) > cap:
				break                           # locality: forward, not across the rung
			if (v in ctx.adj[u]) or edge_crosses_water(ctx.field, ctx.pos[u], ctx.pos[v]):
				continue
			if _crosses_any(ctx, u, v, edges):
				continue                        # local: pick the next nearest non-crossing
			ctx.adj[u].append(v); edges.append([u, v]); indeg[v] += 1; taken += 1
	# 2. Incoming coverage: every V node reachable from start.
	for v in V:
		if indeg[v] > 0:
			continue
		var su := _pick_link(ctx, U, v, edges, max_out, true)
		if su >= 0:
			ctx.adj[su].append(v); edges.append([su, v]); indeg[v] += 1
	# 3. Outgoing coverage: every U node can advance toward end.
	for u in U:
		if ctx.adj[u].size() > 0:
			continue
		var dv := _pick_link(ctx, V, u, edges, max_out, false)
		if dv >= 0:
			ctx.adj[u].append(dv); edges.append([u, dv]); indeg[dv] += 1

## Pick the best node in `pool` to link with `node` for coverage. `pool_is_src` true:
## pool->node (incoming); else node->pool (outgoing). Tiered cost: an on-land link wins; a
## legal strait ferry next; a forced water crossing is the LAST resort so connectivity is
## always preserved (no orphaned landmasses). On-land links must not overlap (local skip).
static func _pick_link(ctx: Ctx, pool: Array, node: int, edges: Array, max_out: int, pool_is_src: bool) -> int:
	var best := -1
	var best_key := INF
	for p in pool:
		var s: int = p if pool_is_src else node
		var t: int = node if pool_is_src else p
		if ctx.adj[s].size() >= max_out or (t in ctx.adj[s]):
			continue
		var tier := 0.0
		if edge_crosses_water(ctx.field, ctx.pos[s], ctx.pos[t]):
			tier = 1e3 if _legal_ferry(ctx, s, t) else 1e6   # real strait preferred; forced last
		elif _crosses_any(ctx, s, t, edges):
			continue                                          # on-land edges must not overlap (local)
		var key := tier + ctx.pos[node].distance_to(ctx.pos[p])
		if key < best_key:
			best_key = key; best = p
	return best

static func _crosses_any(ctx: Ctx, u: int, c: int, edges: Array) -> bool:
	for e in edges:
		if e[0] == u or e[0] == c or e[1] == u or e[1] == c:
			continue
		if _segments_cross(ctx.pos[u], ctx.pos[c], ctx.pos[e[0]], ctx.pos[e[1]]):
			return true
	return false

static func _reaches_id(adj: Array, src: int, dst: int) -> bool:
	var seen := {src: true}
	var stack: Array[int] = [src]
	while not stack.is_empty():
		var u: int = stack.pop_back()
		if u == dst:
			return true
		for v in adj[u]:
			if not seen.has(v):
				seen[v] = true; stack.push_back(v)
	return false

## Proper segment intersection (excluding shared endpoints, handled by caller).
static func _segments_cross(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var d1 := _orient(p3, p4, p1)
	var d2 := _orient(p3, p4, p2)
	var d3 := _orient(p1, p2, p3)
	var d4 := _orient(p1, p2, p4)
	return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0))

static func _orient(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)

## A water crossing is a LEGAL ferry iff: different landmasses, both endpoints coastal,
## neither is start/end, AND its straight line is essentially OPEN WATER between the
## coasts (`_ferry_line_open`) -- it must not cut across a landmass. (City/port requirement
## dropped while all nodes are one type.)
static func _legal_ferry(ctx: Ctx, u: int, v: int) -> bool:
	if u == ctx.start_id or v == ctx.start_id or u == ctx.end_id or v == ctx.end_id:
		return false
	if ctx.field.label_at(ctx.pos[u]) == ctx.field.label_at(ctx.pos[v]):
		return false
	if not (ctx.field.is_coastal(ctx.pos[u], ctx.coast_radius) and ctx.field.is_coastal(ctx.pos[v], ctx.coast_radius)):
		return false
	return _ferry_line_open(ctx.field, ctx.pos[u], ctx.pos[v])

## Is the straight a->b a clean gap crossing? Its interior (ignoring the coastal ends)
## must be mostly open water -- a line that cuts across a landmass has lots of interior
## land and is rejected (so a ferry can't span an island, only the sea between two).
static func _ferry_line_open(field: MapField, a: Vector2, b: Vector2) -> bool:
	var steps := maxi(6, int(a.distance_to(b)))
	var land := 0
	var inner := 0
	for i in range(1, steps):
		var t := float(i) / steps
		if t < 0.12 or t > 0.88:
			continue                                  # skip the coastal ends
		inner += 1
		if field.is_land(a.lerp(b, t)):
			land += 1
	return inner == 0 or float(land) / float(inner) <= 0.2

## True if the straight segment a->b passes over open water at any interior point.
static func edge_crosses_water(field: MapField, a: Vector2, b: Vector2) -> bool:
	var steps := int(a.distance_to(b)) + 1
	for i in range(1, steps):
		if not field.is_land(a.lerp(b, float(i) / steps)):
			return true
	return false

## Water-travel rule: an edge crossing open water is legal ONLY as a ferry (see
## _legal_ferry: cross-landmass, both coastal cities, not start/end). Returns the
## offending [u, v] edges. Step C trims/curves these; here it's a metric/validator.
static func water_edge_violations(ctx: Ctx, _coast_radius: float = 0.0) -> Array:
	var bad: Array = []
	for u in range(ctx.n):
		for v in ctx.adj[u]:
			if edge_crosses_water(ctx.field, ctx.pos[u], ctx.pos[v]):
				if not _legal_ferry(ctx, u, v):
					bad.append([u, v])
	return bad

# ---------------------------------------------------------------------------
## Snap an axis pole to the nearest large landmass (start/end sit on land, not in ocean).
static func _pole_pos(field: MapField, large: Dictionary, center: Vector2, dir: Vector2, a: float) -> Vector2:
	var pole := center + dir * a
	if large.has(field.label_at(pole)):
		return pole
	var si := field.nearest_sample_idx(pole, {}, -1, large)
	return field.samples[si] if si >= 0 else pole

# ---------------------------------------------------------------------------
## Build the placement context by overlaying a LADDER on the land (v4). Nodes are
## GENERATED, not taken from spec node counts: D rungs (= spec depth/journey length) are
## laid along the principal axis like the oval. Each rung is an INDEPENDENT slice across
## the land, divided into equal width-sections; the section count scales with that slice's
## land width between `min_width` (thinnest land) and `max_width` (widest). A node sits at
## each section centre, jittered. Lanes are per-rung (need not align); all nodes one type.
static func _make_ctx(graph: Dictionary, field: MapField, settings: WorldSettings, seed_val: int, opts: Dictionary = {}) -> Ctx:
	var ctx := Ctx.new()
	ctx.field = field
	ctx.s = settings
	var diag := settings.map_diag()
	ctx.coast_radius = settings.coast_radius_ratio * diag
	ctx.lane_tol = opts.get("lane_tol", 1.8)
	var min_frac: float = opts.get("landmass_min_frac", 0.12)
	var gpca := field.land_pca()
	var center: Vector2 = gpca["center"]
	var dir: Vector2 = gpca["axis"]
	var perp: Vector2 = gpca["perp"]
	ctx.axis = dir
	ctx.perp = perp
	var amin0: float = gpca["amin"]; var amax0: float = gpca["amax"]
	var pmin0: float = gpca["pmin"]; var pmax0: float = gpca["pmax"]
	var axis_ext: float = amax0 - amin0

	# LADDER model: rung count (= depth / journey length) comes from the spec, laid along
	# the principal axis exactly like the oval. Each rung is an independent slice across
	# the land, divided into equal width-sections; the SECTION COUNT scales with that
	# slice's land width between `min_width` (thinnest land) and `max_width` (widest land).
	var D: int = maxi(2, graph["ranks"])
	ctx.max_depth = D
	var min_w: int = maxi(1, opts.get("min_width", 1))
	var max_w: int = maxi(min_w, opts.get("max_width", 5))
	var scan_step: float = maxf(1.0, field._cs * 0.5)
	var rung_pitch: float = axis_ext / float(D)
	var jitter_amt: float = rung_pitch * opts.get("jitter", 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val * 100069 + 7

	# Large landmasses that carry samples = the islands the grid may occupy.
	var have_samples := {}
	for sl in field.sample_label:
		have_samples[sl] = true
	var big := 0
	for sid in field.sizes.keys():
		big = maxi(big, field.sizes[sid])
	var large := {}
	for sid in field.sizes.keys():
		if field.sizes[sid] >= int(big * min_frac) and have_samples.has(sid):
			large[sid] = true
	if large.is_empty() and field.main_label >= 0:
		large[field.main_label] = true

	# Pass 1: slice each interior rung across every landmass; record on-land coords and the
	# GLOBAL min/max slice width (so the thinnest land anywhere -> min_width sections, the
	# widest -> max_width).
	var slices := {}                                  # d -> { lab -> PackedFloat32Array coords }
	var gwmin := INF
	var gwmax := 0.0
	for d in range(1, D):
		var a := amin0 + axis_ext * (float(d) / float(D))
		var by_lab := {}
		for lab in large.keys():
			var coords := field.slice_land_coords(center, dir, perp, a, pmin0, pmax0, lab, scan_step)
			if coords.is_empty():
				continue
			by_lab[lab] = coords
			var w: float = coords[coords.size() - 1] - coords[0]
			gwmin = minf(gwmin, w); gwmax = maxf(gwmax, w)
		slices[d] = by_lab
	if gwmin == INF: gwmin = 0.0
	if gwmax <= gwmin: gwmax = gwmin + 1.0

	# Pass 2: place. Each rung's landmass slice is divided into `count` equal sections;
	# count scales with width between min_w and max_w. A node sits at each section centre,
	# jittered so the lattice isn't obvious. Lanes are PER-RUNG (independent) -> they need
	# not align across rungs; edges connect by geometry, not lane index.
	var g_pos := PackedVector2Array()
	var g_depth := PackedInt32Array()
	var g_lane := PackedInt32Array()
	var g_label := PackedInt32Array()
	var start_id := -1
	var end_id := -1
	# Start pole (d=0).
	var sp := _pole_pos(field, large, center, dir, amin0)
	start_id = g_pos.size()
	g_pos.append(sp); g_depth.append(0); g_lane.append(0); g_label.append(field.label_at(sp))
	for d in range(1, D):
		var a := amin0 + axis_ext * (float(d) / float(D))
		var by_lab: Dictionary = slices[d]
		for lab in by_lab.keys():
			var coords: PackedFloat32Array = by_lab[lab]
			var w: float = coords[coords.size() - 1] - coords[0]
			var gfrac := (w - gwmin) / (gwmax - gwmin)
			var count := clampi(int(round(min_w + (max_w - min_w) * gfrac)), min_w, max_w)
			count = mini(count, coords.size())
			for k in range(count):
				# Endpoint-INCLUSIVE division: k=0 and k=count-1 land on the slice's coasts,
				# so each rung spans coast-to-coast (no inland contraction); interior nodes
				# split the rest evenly.
				var frac := 0.5 if count <= 1 else float(k) / float(count - 1)
				var ci := clampi(int(round(frac * (coords.size() - 1))), 0, coords.size() - 1)
				var base := center + dir * a + perp * coords[ci]
				var wj := base + dir * ((rng.randf() - 0.5) * jitter_amt) + perp * ((rng.randf() - 0.5) * jitter_amt)
				if field.label_at(wj) == lab:
					base = wj                         # keep jitter only if it stays on this island
				g_pos.append(base); g_depth.append(d); g_lane.append(k); g_label.append(lab)
	# End pole (d=D).
	var ep := _pole_pos(field, large, center, dir, amax0)
	end_id = g_pos.size()
	g_pos.append(ep); g_depth.append(D); g_lane.append(0); g_label.append(field.label_at(ep))

	ctx.n = g_pos.size()
	ctx.pos = g_pos
	ctx.depth = g_depth
	ctx.lane = g_lane
	ctx.node_label = g_label
	ctx.is_city = PackedByteArray(); ctx.is_city.resize(ctx.n)        # all one type for now
	ctx.active = PackedByteArray(); ctx.active.resize(ctx.n); ctx.active.fill(1)
	ctx.adj = []
	ctx.adj.resize(ctx.n)
	for i in range(ctx.n):
		ctx.adj[i] = []
	ctx.start_id = start_id
	ctx.end_id = end_id
	ctx.start_pos = ctx.pos[start_id]
	ctx.end_pos = ctx.pos[end_id]
	return ctx
