class_name GraphPlacement
extends RefCounted

## Step B of graph placement: take the fixed, rule-correct graph from GraphSpec and
## physically lay it onto the real map with force-directed layout. CONNECTIONS NEVER
## CHANGE here -- only positions. Nodes start as a filled disc around the map centre
## and the forces redistribute them evenly across the landmass.
##
## Design goals honoured:
##  - Pluggable, comparable integrators: every integrator shares the SAME force set
##    (`_compute_forces`) so they can be benchmarked head-to-head on identical maps.
##  - Depth stays monotonic along the start->end spatial axis -> an edge can never
##    jump backwards across the continent (anti-zigzag, per user requirement).
##  - Pure data (PackedArrays / Dictionaries) so it is thread-safe for the harness.

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
		# Seed: a cell inside the domain, near the (domain) centroid.
		var seed_pt := land_centroid
		if not in_domain(seed_pt):
			seed_pt = _find_any_land()
		if not in_domain(seed_pt):
			return
		_add_poisson(seed_pt, grid, gw, gh, cell, active)
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
	func nearest_sample_idx(p: Vector2, skip: Dictionary = {}, target_label: int = -1) -> int:
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

	func _cell_in(x: int, y: int, lab: int) -> bool:
		return label[(y * w) + x] == lab if lab >= 0 else _dom_cell(x, y)

	## Land extreme points along `dir`: [min_projection_point, max_projection_point].
	## `lab` >= 0 restricts to that landmass; otherwise the whole domain.
	func axis_extremes(dir: Vector2, lab: int = -1) -> Array:
		var lo := INF
		var hi := -INF
		var lo_pt := land_centroid
		var hi_pt := land_centroid
		for y in range(h):
			for x in range(w):
				if _cell_in(x, y, lab):
					var pr := Vector2(x, y).dot(dir)
					if pr < lo:
						lo = pr; lo_pt = Vector2(x, y)
					if pr > hi:
						hi = pr; hi_pt = Vector2(x, y)
		return [lo_pt, hi_pt]

	## (min, max) of land projected onto `perp`, measured from `origin`.
	func perp_range(origin: Vector2, perp: Vector2, lab: int = -1) -> Vector2:
		var lo := INF
		var hi := -INF
		for y in range(h):
			for x in range(w):
				if _cell_in(x, y, lab):
					var pr := (Vector2(x, y) - origin).dot(perp)
					lo = minf(lo, pr); hi = maxf(hi, pr)
		if lo == INF:
			return Vector2(-1, 1)
		return Vector2(lo, hi)

	## Principal-axis description of the whole land distribution (from the samples):
	## { center, axis, perp, amin, amax, pmin, pmax } in axis/perp coordinates relative
	## to center. The oval grid is laid along this so depth flows along the land's
	## longest dimension and the layout is centred on the actual land, not outliers.
	func land_pca() -> Dictionary:
		var n := samples.size()
		if n == 0:
			return {"center": land_centroid, "axis": Vector2(1, 0), "perp": Vector2(0, 1),
				"amin": -float(w) * 0.5, "amax": float(w) * 0.5, "pmin": -float(h) * 0.5, "pmax": float(h) * 0.5}
		var mean := Vector2.ZERO
		for s in samples:
			mean += s
		mean /= n
		var sxx := 0.0; var sxy := 0.0; var syy := 0.0
		for s in samples:
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
		for s in samples:
			var d := s - mean
			var a := d.dot(axis); var p := d.dot(perp)
			amin = minf(amin, a); amax = maxf(amax, a)
			pmin = minf(pmin, p); pmax = maxf(pmax, p)
		return {"center": mean, "axis": axis, "perp": perp,
			"amin": amin, "amax": amax, "pmin": pmin, "pmax": pmax}

	func centroid_of(lab: int) -> Vector2:
		var sum := Vector2.ZERO
		var n := 0
		for y in range(h):
			for x in range(w):
				if label[(y * w) + x] == lab:
					sum += Vector2(x, y); n += 1
		return sum / maxi(1, n) if n > 0 else land_centroid

	## Landmass ids with size >= `min_frac` of the largest, ordered along `dir`
	## (so a journey can flow island-to-island). Capped to `max_count`.
	func ordered_landmasses(dir: Vector2, min_frac: float, max_count: int) -> Array:
		var big := 0
		for id in sizes.keys():
			big = maxi(big, sizes[id])
		var chosen: Array = []
		for id in sizes.keys():
			if sizes[id] >= int(big * min_frac):
				chosen.append(id)
		var cents := {}
		for id in chosen:
			cents[id] = centroid_of(id)
		chosen.sort_custom(func(a, b): return cents[a].dot(dir) < cents[b].dot(dir))
		if chosen.size() > max_count:
			# keep the largest max_count, but preserve the along-dir order.
			var by_size := chosen.duplicate()
			by_size.sort_custom(func(a, b): return sizes[a] > sizes[b])
			var keep := {}
			for i in range(max_count):
				keep[by_size[i]] = true
			var out: Array = []
			for id in chosen:
				if keep.has(id):
					out.append(id)
			return out
		return chosen

# ---------------------------------------------------------------------------
# Shared force/layout context (mutated in place during the sim).
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
	var axis_len: float
	var perp_extent: float               # landmass half-size across the axis
	var perp_target: PackedFloat32Array  # node id -> desired perpendicular offset
	var layout_target: PackedVector2Array # node id -> structured target position
	var node_label: PackedInt32Array     # node id -> assigned landmass id
	# Tunable distances (px), resolved from ratios * map_diag.
	var ideal_edge: float
	var repel_dist: float
	var coast_radius: float              # a node within this of water counts as coastal
	# Force weights (will move into WorldSettings in the param overhaul).
	var w_land := 6.0
	var w_repel := 1.0
	var w_spring := 0.35
	var w_axis := 0.5
	var w_perp := 0.8
	var w_structure := 0.5               # pull toward the structured layout target
	var w_bound := 1.0
	var w_longedge := 0.8                # steep extra contraction past long_edge_cap
	var w_edge_water := 1.2             # contraction for edges crossing open water
	var long_edge_mult := 2.2           # edge is "too long" past this x ideal_edge

# ---------------------------------------------------------------------------
# Integrators (pluggable). All share _compute_forces so they're comparable.
# ---------------------------------------------------------------------------
class Integrator extends RefCounted:
	var ctx: Ctx
	func setup(_c: Ctx) -> void: ctx = _c
	func step() -> float: return 0.0          # returns total movement this step
	func is_settled() -> bool: return false

## Fruchterman-Reingold: net force per node, displacement capped by a cooling
## temperature so it settles. The recommended default base.
class FruchtermanReingold extends Integrator:
	var temp: float
	var cool := 0.95
	var min_move := 0.0
	var _last_move := INF

	func setup(_c: Ctx) -> void:
		ctx = _c
		temp = ctx.field.land_max.distance_to(ctx.field.land_min) * 0.1 + 1.0
		min_move = ctx.field.w * 0.0005

	func step() -> float:
		var forces := GraphPlacement._compute_forces(ctx)
		var moved := 0.0
		for i in range(ctx.n):
			if i == ctx.start_id or i == ctx.end_id:
				continue                       # anchored
			var f := forces[i]
			var mag := f.length()
			if mag > 0.0001:
				var disp := f / mag * minf(mag, temp)
				ctx.pos[i] += disp
				moved += disp.length()
		temp = maxf(temp * cool, 0.5)
		_last_move = moved
		return moved

	func is_settled() -> bool:
		return _last_move < min_move * ctx.n

# ---------------------------------------------------------------------------
# Force computation (shared by all integrators).
# ---------------------------------------------------------------------------
static func _compute_forces(ctx: Ctx) -> PackedVector2Array:
	var forces := PackedVector2Array()
	forces.resize(ctx.n)
	for i in range(ctx.n):
		forces[i] = Vector2.ZERO

	# 1. Land attraction: a node over ocean is pulled inland along the distance-
	#    transform gradient (defined and nonzero even in deep ocean). Falls back to
	#    the nearest land sample if the gradient is degenerate.
	for i in range(ctx.n):
		var p := ctx.pos[i]
		if not ctx.field.is_land(p):
			var g := ctx.field.dt_gradient(p)
			if g.length() > 0.0001:
				forces[i] += g.normalized() * ctx.w_land * ctx.repel_dist
			else:
				var d := ctx.field.nearest_sample(p) - p
				if d.length() > 0.0001:
					forces[i] += d.normalized() * ctx.w_land * ctx.repel_dist

	# 2. Node-node repulsion (inverse distance) within range -> even spacing.
	var rd := ctx.repel_dist
	for i in range(ctx.n):
		for j in range(i + 1, ctx.n):
			var d := ctx.pos[i] - ctx.pos[j]
			var dist := d.length()
			if dist < 0.001:
				d = Vector2(randf() - 0.5, randf() - 0.5); dist = 0.01
			if dist < rd * 2.0:
				var f := d / dist * (rd * rd / (dist * dist)) * ctx.w_repel
				forces[i] += f
				forces[j] -= f

	# 3. Edge springs (Hooke) toward the ideal edge length, plus:
	#    5. long-edge penalty (steep extra contraction past a cap), and
	#    4. illegal-water-crossing repulsion: an edge crossing open water contracts
	#       hard UNLESS it's a legal ferry (both endpoints coastal). This keeps travel
	#       local within a landmass while allowing proper coast-to-coast ferries.
	var cap := ctx.ideal_edge * ctx.long_edge_mult
	for u in range(ctx.n):
		for v in ctx.adj[u]:
			var d: Vector2 = ctx.pos[v] - ctx.pos[u]
			var dist := d.length()
			if dist < 0.001:
				continue
			var dir := d / dist
			forces[u] += dir * (dist - ctx.ideal_edge) * ctx.w_spring
			forces[v] -= dir * (dist - ctx.ideal_edge) * ctx.w_spring
			if dist > cap:
				var fl := dir * (dist - cap) * ctx.w_longedge
				forces[u] += fl
				forces[v] -= fl
			if _segment_hits_water(ctx.field, ctx.pos[u], ctx.pos[v]):
				if not _legal_ferry(ctx, u, v):
					var fw := dir * dist * ctx.w_edge_water
					forces[u] += fw
					forces[v] -= fw

	# 4+5. Structure anchor: pull each node toward its precomputed structured target
	#      (per-landmass depth-band + Sugiyama lane order). This keeps depth ordered
	#      in space (anti-zigzag/backtrack) and lanes spread, and works per landmass
	#      so the graph follows each island instead of a single straight axis.
	for i in range(ctx.n):
		if i == ctx.start_id or i == ctx.end_id:
			continue
		forces[i] += (ctx.layout_target[i] - ctx.pos[i]) * ctx.w_structure

	# 6. Boundary containment: keep nodes on/near the map's land box.
	for i in range(ctx.n):
		var p := ctx.pos[i]
		if not ctx.field.in_bounds(p):
			forces[i] += (ctx.field.land_centroid - p).normalized() * ctx.w_bound * ctx.repel_dist

	return forces

# ---------------------------------------------------------------------------
# Public entry point.
# ---------------------------------------------------------------------------
## Place `graph` (a GraphSpec dict) on `field`. Returns a result dict:
##   { "pos": PackedVector2Array, "ctx": Ctx, "steps": int, "init_pos": PackedVector2Array }
## `record_mid` (0..1) optionally captures positions at that fraction of the sim.
static func place(graph: Dictionary, field: MapField, settings: WorldSettings,
		seed_val: int, integrator: Integrator = null, opts: Dictionary = {}) -> Dictionary:
	var ctx := _make_ctx(graph, field, settings, seed_val, opts)
	# Adaptive density: clearly more land samples than nodes so assignment has room.
	if field.domain_land > 0:
		var ratio: float = opts.get("sample_spacing_ratio", 0.012)
		var want_sp := sqrt(float(field.domain_land) / float(maxi(1, ctx.n * 2)))
		var sp := minf(settings.map_diag() * ratio, want_sp)
		if absf(sp - field._cs) > 0.5:
			field.build_land_samples(sp, seed_val, opts.get("poisson", true))

	# Init visual: a structured CIRCULAR layout centred on the land (ordered by depth
	# & breadth, not random). Nodes don't "settle" -- final positions are assigned
	# deterministically below, so there is no post-settle jumping.
	_init_circular(ctx)
	var init_pos := ctx.pos.duplicate()

	# Deterministic placement: assign nodes onto land samples ordered by depth (axis)
	# and breadth (perp), per landmass. Guarantees 100% on land, even spacing, depth
	# order, and start/end pinned to the main landmass's global axis extremes.
	_assign_positions(ctx, field)
	var mid_pos := ctx.pos.duplicate()      # = final (assignment is one shot)

	# Edge creation -- ONE geography-aware pass on the placed nodes.
	var edge_stats := _create_edges(ctx, graph, settings)

	return {"pos": ctx.pos, "ctx": ctx, "steps": 0, "init_pos": init_pos,
		"mid_pos": mid_pos, "edge_stats": edge_stats}

## Init visual = the lens grid laid over the map (depth pole->pole, breadth fanned).
static func _init_circular(ctx: Ctx) -> void:
	for i in range(ctx.n):
		ctx.pos[i] = ctx.layout_target[i]

## Snap each node to the nearest UNUSED land sample to its grid target (ANY island).
## Geography partitions the graph; node_label is recorded from the final position.
static func _assign_positions(ctx: Ctx, field: MapField) -> void:
	var used := {}
	var ids: Array = []
	for i in range(ctx.n):
		if i != ctx.start_id and i != ctx.end_id:
			ids.append(i)
	ids.sort_custom(func(a, b):
		if ctx.depth[a] != ctx.depth[b]:
			return ctx.depth[a] < ctx.depth[b]
		return ctx.perp_target[a] < ctx.perp_target[b])
	for id in ids:
		var idx := field.nearest_sample_idx(ctx.layout_target[id], used)   # nearest land, any island
		if idx < 0:
			idx = field.nearest_sample_idx(ctx.layout_target[id])
		if idx >= 0:
			ctx.pos[id] = field.samples[idx]
			used[idx] = true
	_force_anchor(ctx, field, ctx.start_id, ctx.start_pos, used)
	_force_anchor(ctx, field, ctx.end_id, ctx.end_pos, used)
	for i in range(ctx.n):                          # landmass derived from final position
		ctx.node_label[i] = field.label_at(ctx.pos[i])

static func _force_anchor(ctx: Ctx, field: MapField, node: int, target: Vector2, used: Dictionary) -> void:
	var idx := field.nearest_sample_idx(target, used)
	if idx < 0:
		idx = field.nearest_sample_idx(target)
	if idx >= 0:
		ctx.pos[node] = field.samples[idx]
		used[idx] = true

# ---------------------------------------------------------------------------
# Edge creation -- ONE geography-aware pass on the settled node positions.
# ---------------------------------------------------------------------------
## Build the whole graph: forward depth-adjacent edges chosen by proximity, never
## crossing water (unless a legal ferry) and never crossing another edge; then ensure
## every node is covered (>=1 in/out) and start can reach end. Returns stats.
static func _create_edges(ctx: Ctx, graph: Dictionary, settings: WorldSettings) -> Dictionary:
	var layers: Array = graph["layers"]
	var D: int = ctx.max_depth
	var max_out: int = maxi(1, settings.spec_outgoing)
	var min_out: int = clampi(settings.spec_min_outgoing, 1, max_out)
	var edges: Array = []                       # [u, v] for crossing tests
	var indeg := PackedInt32Array(); indeg.resize(ctx.n)

	# 1. Forward proximity connect (each node -> up to max_out nearest next-layer nodes).
	for d in range(D):
		for u in layers[d]:
			var cands: Array = layers[d + 1].duplicate()
			cands.sort_custom(func(a, b):
				return ctx.pos[u].distance_squared_to(ctx.pos[a]) < ctx.pos[u].distance_squared_to(ctx.pos[b]))
			for c in cands:
				if ctx.adj[u].size() >= max_out:
					break
				if _can_connect(ctx, u, c, edges):
					ctx.adj[u].append(c)
					edges.append([u, c])
					indeg[c] += 1

	# 2. Coverage: every non-start node needs >=1 incoming; every non-end >=1 outgoing.
	for d in range(1, D + 1):
		for c in layers[d]:
			if indeg[c] > 0:
				continue
			var src := _nearest_connectable(ctx, c, layers[d - 1], edges, max_out, true)
			if src >= 0:
				ctx.adj[src].append(c); edges.append([src, c]); indeg[c] += 1
	for d in range(D):
		for u in layers[d]:
			if ctx.adj[u].size() > 0:
				continue
			var dstn := _nearest_connectable(ctx, u, layers[d + 1], edges, max_out, false)
			if dstn >= 0:
				ctx.adj[u].append(dstn); edges.append([u, dstn]); indeg[dstn] += 1

	# 3. Top up toward min_out where possible (without crossings/water).
	for d in range(D):
		for u in layers[d]:
			if ctx.adj[u].size() >= min_out:
				continue
			var cands: Array = layers[d + 1].duplicate()
			cands.sort_custom(func(a, b):
				return ctx.pos[u].distance_squared_to(ctx.pos[a]) < ctx.pos[u].distance_squared_to(ctx.pos[b]))
			for c in cands:
				if ctx.adj[u].size() >= min_out:
					break
				if not (c in ctx.adj[u]) and _can_connect(ctx, u, c, edges):
					ctx.adj[u].append(c); edges.append([u, c]); indeg[c] += 1

	# 4. Connectivity guarantee: every node reachable from start AND able to reach end
	#    (so side-landmass routes connect via ferries; no isolated clusters). Repair
	#    edges may relax the no-cross/no-water rule to keep the graph connected.
	_repair_forward(ctx, layers, D, max_out)
	_repair_backward(ctx, layers, D, max_out)

	var reaches_end := _reaches_id(ctx.adj, ctx.start_id, ctx.end_id)
	var total := 0
	for u in range(ctx.n):
		total += ctx.adj[u].size()
	return {"edges": total, "reaches_end": reaches_end}

## Ensure every node is reachable from start: connect each unreached node from the
## nearest reached node on the previous layer (forced -- connectivity over purity).
static func _repair_forward(ctx: Ctx, layers: Array, D: int, max_out: int) -> void:
	var reached := _reach_from(ctx.adj, ctx.start_id, ctx.n)
	for d in range(1, D + 1):
		var changed := false
		for c in layers[d]:
			if reached.has(c):
				continue
			var u := _nearest_in(ctx, layers[d - 1], c, reached, true, max_out)
			if u >= 0:
				ctx.adj[u].append(c); changed = true
		if changed:
			reached = _reach_from(ctx.adj, ctx.start_id, ctx.n)

## Ensure every node can reach end: connect each dead-end toward the nearest node on
## the next layer that can already reach end.
static func _repair_backward(ctx: Ctx, layers: Array, D: int, max_out: int) -> void:
	var can_end := _reach_to(ctx.adj, ctx.end_id, ctx.n)
	for d in range(D - 1, -1, -1):
		var changed := false
		for u in layers[d]:
			if can_end.has(u):
				continue
			var c := _nearest_in(ctx, layers[d + 1], u, can_end, false, max_out)
			if c >= 0:
				ctx.adj[u].append(c); changed = true
		if changed:
			can_end = _reach_to(ctx.adj, ctx.end_id, ctx.n)

## Nearest node in pool that's in `flag_set`. `as_source` true: pool node is the
## source (connect pool->node), prefer outdeg<max_out. Else pool node is the target.
static func _nearest_in(ctx: Ctx, pool: Array, node: int, flag_set: Dictionary, as_source: bool, max_out: int) -> int:
	var best := -1
	var best_d := INF
	for p in pool:
		if not flag_set.has(p):
			continue
		var s : int = p if as_source else node
		if ctx.adj[s].size() >= max_out:
			continue
		if node in ctx.adj[s] or p in ctx.adj[node]:
			continue
		var dd: float = ctx.pos[node].distance_squared_to(ctx.pos[p])
		if dd < best_d:
			best_d = dd; best = p
	return best

static func _reach_from(adj: Array, src: int, n: int) -> Dictionary:
	var seen := {src: true}
	var stack: Array[int] = [src]
	while not stack.is_empty():
		var u: int = stack.pop_back()
		for v in adj[u]:
			if not seen.has(v):
				seen[v] = true; stack.push_back(v)
	return seen

static func _reach_to(adj: Array, dst: int, n: int) -> Dictionary:
	var preds: Array = []
	preds.resize(n)
	for i in range(n):
		preds[i] = []
	for u in range(n):
		for v in adj[u]:
			preds[v].append(u)
	var seen := {dst: true}
	var stack: Array[int] = [dst]
	while not stack.is_empty():
		var u: int = stack.pop_back()
		for p in preds[u]:
			if not seen.has(p):
				seen[p] = true; stack.push_back(p)
	return seen

## Can we add edge u->c? Not already present, stays on land OR is a legal ferry, and
## doesn't cross any existing edge.
static func _can_connect(ctx: Ctx, u: int, c: int, edges: Array) -> bool:
	if c in ctx.adj[u]:
		return false
	if edge_crosses_water(ctx.field, ctx.pos[u], ctx.pos[c]) and not _legal_ferry(ctx, u, c):
		return false
	return not _crosses_any(ctx, u, c, edges)

static func _crosses_any(ctx: Ctx, u: int, c: int, edges: Array) -> bool:
	for e in edges:
		if e[0] == u or e[0] == c or e[1] == u or e[1] == c:
			continue
		if _segments_cross(ctx.pos[u], ctx.pos[c], ctx.pos[e[0]], ctx.pos[e[1]]):
			return true
	return false

## Nearest node in `pool` we can connect to `node` (respecting max_out on the SOURCE
## side). `incoming` = pool nodes are the source (edge pool->node); else node->pool.
static func _nearest_connectable(ctx: Ctx, node: int, pool: Array, edges: Array, max_out: int, incoming: bool) -> int:
	var sorted: Array[int]
	sorted.assign(pool.duplicate())
	sorted.sort_custom(func(a, b):
		return ctx.pos[node].distance_squared_to(ctx.pos[a]) < ctx.pos[node].distance_squared_to(ctx.pos[b]))
	for p in sorted:
		var s := p if incoming else node
		var t := node if incoming else p
		if ctx.adj[s].size() >= max_out:
			continue
		if _can_connect(ctx, s, t, edges):
			return p
	# Fallback: nearest regardless of water/cross (avoid orphaning a node entirely).
	for p in sorted:
		var s := p if incoming else node
		var t := node if incoming else p
		if not (t in ctx.adj[s]):
			return p
	return -1

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

## Greedy assign each node to the nearest land sample not already taken.
static func _snap_to_land(ctx: Ctx) -> void:
	if ctx.field.samples.is_empty():
		return
	var used := {}
	for i in range(ctx.n):
		var lab: int = ctx.node_label[i]      # snap onto the node's assigned landmass
		var idx := ctx.field.nearest_sample_idx(ctx.pos[i], used, lab)
		if idx < 0:                           # that landmass full -> reuse nearest on it
			idx = ctx.field.nearest_sample_idx(ctx.pos[i], {}, lab)
		if idx < 0:                           # last resort -> any land
			idx = ctx.field.nearest_sample_idx(ctx.pos[i], used)
		if idx >= 0:
			ctx.pos[i] = ctx.field.samples[idx]
			used[idx] = true

## A water crossing is a LEGAL ferry iff: it links two DIFFERENT landmasses, both
## endpoints are coastal cities (ports), and neither endpoint is start/end. Within a
## single landmass every water crossing (a bay short-cut) is illegal, and non-city
## or start/end water edges are always illegal.
static func _legal_ferry(ctx: Ctx, u: int, v: int) -> bool:
	if u == ctx.start_id or v == ctx.start_id or u == ctx.end_id or v == ctx.end_id:
		return false
	if ctx.is_city[u] == 0 and ctx.is_city[v] == 0:   # at least one must be a city
		return false
	if not (ctx.field.is_coastal(ctx.pos[u], ctx.coast_radius) and ctx.field.is_coastal(ctx.pos[v], ctx.coast_radius)):
		return false
	return ctx.field.label_at(ctx.pos[u]) != ctx.field.label_at(ctx.pos[v])

## Cheap water test along a segment (fixed sample count) for the per-step force.
static func _segment_hits_water(field: MapField, a: Vector2, b: Vector2) -> bool:
	for i in range(1, 7):
		if not field.is_land(a.lerp(b, i / 7.0)):
			return true
	return false

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
static func _make_ctx(graph: Dictionary, field: MapField, settings: WorldSettings, seed_val: int, opts: Dictionary = {}) -> Ctx:
	var ctx := Ctx.new()
	ctx.field = field
	ctx.s = settings
	# Optional force-weight overrides (levers).
	for k in ["w_land", "w_repel", "w_spring", "w_axis", "w_perp", "w_bound",
			"w_longedge", "w_edge_water", "long_edge_mult"]:
		if opts.has(k):
			ctx.set(k, opts[k])
	# v2: node-only graph (no edges yet). Supports both "depth" (v2) and "rank" (v1).
	var nodes: Array = graph["nodes"]
	ctx.n = nodes.size()
	ctx.pos = PackedVector2Array(); ctx.pos.resize(ctx.n)
	ctx.depth = PackedInt32Array(); ctx.depth.resize(ctx.n)
	ctx.is_city = PackedByteArray(); ctx.is_city.resize(ctx.n)
	ctx.adj = []
	ctx.adj.resize(ctx.n)
	ctx.max_depth = graph["ranks"]
	for nd in nodes:
		ctx.depth[nd["id"]] = nd.get("depth", nd.get("rank", 0))
		ctx.is_city[nd["id"]] = 1 if nd["is_city"] else 0
	for id in range(ctx.n):
		ctx.adj[id] = []                      # edges built AFTER settle (edge pass)
	ctx.start_id = graph["start"]
	ctx.end_id = graph["end"]

	var diag := settings.map_diag()
	ctx.ideal_edge = diag * 0.05
	ctx.repel_dist = diag * 0.04
	ctx.coast_radius = settings.coast_radius_ratio * diag

	# JIGSAW: lay the whole graph oval over ALL land in (depth-axis, breadth-perp)
	# coordinates from the land's principal axis (centred on the actual land, oriented
	# along its longest dimension). Each node's oval position is later snapped to the
	# nearest land -> every landmass receives the overlapping piece of the oval,
	# proportional to its footprint (spine splits by depth where ocean interrupts the
	# axis; lanes split by breadth across side-by-side land).
	var oval_width: float = opts.get("oval_width", 1.0)
	var pca := field.land_pca()
	var center: Vector2 = pca["center"]
	var dir: Vector2 = pca["axis"]
	var perp: Vector2 = pca["perp"]
	ctx.axis = dir
	ctx.perp = perp
	var amin: float = pca["amin"]; var amax: float = pca["amax"]
	var pmid: float = (pca["pmin"] + pca["pmax"]) * 0.5
	var pext: float = (pca["pmax"] - pca["pmin"])

	var layer_count := {}
	for nd in nodes:
		var dd: int = nd.get("depth", nd.get("rank", 0))
		layer_count[dd] = layer_count.get(dd, 0) + 1
	var layer_idx := {}

	ctx.node_label = PackedInt32Array(); ctx.node_label.resize(ctx.n)
	ctx.layout_target = PackedVector2Array(); ctx.layout_target.resize(ctx.n)
	ctx.perp_target = PackedFloat32Array(); ctx.perp_target.resize(ctx.n)
	for nd in nodes:
		var id: int = nd["id"]
		var d: int = nd.get("depth", nd.get("rank", 0))
		var t := float(d) / float(maxi(1, ctx.max_depth))
		var cnt: int = layer_count[d]
		var li: int = layer_idx.get(d, 0)
		layer_idx[d] = li + 1
		var b := 0.0 if cnt <= 1 else (float(li) + 0.5) / float(cnt) - 0.5   # breadth -0.5..0.5
		var ew := sqrt(maxf(0.0, 1.0 - pow(2.0 * t - 1.0, 2.0)))             # lens profile
		var a_coord := amin + t * (amax - amin)                              # depth along axis
		var p_coord := pmid + b * pext * ew * oval_width                     # breadth across
		ctx.perp_target[id] = b
		ctx.layout_target[id] = center + dir * a_coord + perp * p_coord

	# Start at the axis-min pole, end at the axis-max pole (opposite ends of the land).
	ctx.start_pos = center + dir * amin
	ctx.end_pos = center + dir * amax
	ctx.axis_len = float((ctx.end_pos as Vector2).distance_to(ctx.start_pos))
	ctx.layout_target[ctx.start_id] = ctx.start_pos
	ctx.layout_target[ctx.end_id] = ctx.end_pos
	ctx.pos[ctx.start_id] = ctx.start_pos
	ctx.pos[ctx.end_id] = ctx.end_pos
	return ctx

## Sugiyama within-rank ordering: barycenter sweeps (down then up) so a node sits
## near the average position of its neighbours in the adjacent rank -> fewer edge
## crossings. Returns order[node_id] = index within its rank. `passes` 0 = off
## (keeps raw lane order). Written without mutable-capture lambdas (GDScript pitfall).
static func _sugiyama_order(graph: Dictionary, ctx: Ctx, passes: int) -> PackedInt32Array:
	var nodes: Array = graph["nodes"]
	var by_rank: Array = []                 # rank -> Array[int] node ids (ordered)
	by_rank.resize(ctx.max_depth + 1)
	for r in range(ctx.max_depth + 1):
		by_rank[r] = []
	# Initial order = lane order (nodes are emitted rank-major, lane-minor).
	var tmp := nodes.duplicate()
	tmp.sort_custom(func(a, b):
		return a["rank"] < b["rank"] or (a["rank"] == b["rank"] and a["lane"] < b["lane"]))
	for nd in tmp:
		by_rank[nd["rank"]].append(nd["id"])

	var pred: Array = []
	pred.resize(ctx.n)
	for i in range(ctx.n):
		pred[i] = []
	for u in range(ctx.n):
		for v in ctx.adj[u]:
			pred[v].append(u)

	var idx_of := _reindex(by_rank, ctx.n)
	for _p in range(maxi(0, passes)):
		for r in range(1, by_rank.size()):          # down sweep: order by parents
			_order_rank(by_rank[r], pred, idx_of)
			idx_of = _reindex(by_rank, ctx.n)
		for r in range(by_rank.size() - 2, -1, -1): # up sweep: order by children
			_order_rank(by_rank[r], ctx.adj, idx_of)
			idx_of = _reindex(by_rank, ctx.n)
	return idx_of

static func _reindex(by_rank: Array, n: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	idx.resize(n)
	for r in range(by_rank.size()):
		for i in range(by_rank[r].size()):
			idx[by_rank[r][i]] = i
	return idx

## Reorder rank_ids in place by ascending barycenter of each node's neighbours.
static func _order_rank(rank_ids: Array, neigh_lists: Array, idx_of: PackedInt32Array) -> void:
	var arr: Array = []
	for node in rank_ids:
		var neigh: Array = neigh_lists[node]
		var b: float
		if neigh.is_empty():
			b = float(idx_of[node])
		else:
			var s := 0.0
			for m in neigh:
				s += idx_of[m]
			b = s / neigh.size()
		arr.append([b, node])
	arr.sort_custom(func(a, b2): return a[0] < b2[0])
	rank_ids.clear()
	for e in arr:
		rank_ids.append(e[1])

## Initial positions. "structured" (default): place each node directly at its
## layout target (axis = depth fraction, perp = Sugiyama lane order) so it starts
## already spread in the graph's shape -> forces only fit it to terrain, avoiding the
## chaos/clumping of a random scatter. "filled_disc": uniform-in-circle scatter.
static func _init_positions(ctx: Ctx, seed_val: int, strategy: String) -> void:
	if strategy == "filled_disc":
		_init_filled_disc(ctx, seed_val)
		return
	for i in range(ctx.n):
		if i == ctx.start_id or i == ctx.end_id:
			continue
		ctx.pos[i] = ctx.layout_target[i]

## Lloyd / k-means relaxation: move each node to the centroid of the land samples
## nearest to it (a centroidal/even distribution -> de-clumps), then reset the
## along-axis coordinate to the structured depth band so depth ordering is preserved.
static func _lloyd(ctx: Ctx, iters: int) -> void:
	if iters <= 0 or ctx.field.samples.is_empty():
		return
	for _it in range(iters):
		var sum := PackedVector2Array(); sum.resize(ctx.n)
		var cnt := PackedInt32Array(); cnt.resize(ctx.n)
		for s in ctx.field.samples:
			var ni := _nearest_node(ctx, s)
			if ni >= 0:
				sum[ni] += s
				cnt[ni] += 1
		for i in range(ctx.n):
			if i == ctx.start_id or i == ctx.end_id or cnt[i] == 0:
				continue
			var c: Vector2 = sum[i] / cnt[i]
			var t := float(ctx.depth[i]) / float(maxi(1, ctx.max_depth))
			var new_perp := (c - ctx.start_pos).dot(ctx.perp)
			ctx.pos[i] = ctx.start_pos + ctx.axis * (t * ctx.axis_len) + ctx.perp * new_perp

## Nearest city rank to `target` within [lo, hi]; falls back to round(target).
static func _nearest_city_rank(city_ranks: Array, target: float, lo: int, hi: int) -> int:
	var best := -1
	var best_d := INF
	for r in city_ranks:
		if r < lo or r > hi:
			continue
		var d: float = absf(r - target)
		if d < best_d:
			best_d = d; best = r
	return best if best >= 0 else clampi(int(round(target)), lo, hi)

static func _nearest_node(ctx: Ctx, p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in range(ctx.n):
		var d := p.distance_squared_to(ctx.pos[i])
		if d < best_d:
			best_d = d; best = i
	return best

## Filled-disc init: points spread uniformly WITHIN a circle (not just the ring)
## around the land centroid, via a sunflower/Fibonacci pattern + jitter. Start and
## end stay pinned at their anchors.
static func _init_filled_disc(ctx: Ctx, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var c := ctx.field.land_centroid
	var bb := ctx.field.land_max - ctx.field.land_min
	var radius := maxf(bb.x, bb.y) * 0.4 + 1.0
	var golden := PI * (3.0 - sqrt(5.0))
	for i in range(ctx.n):
		if i == ctx.start_id or i == ctx.end_id:
			continue
		# sqrt for uniform area density; golden-angle for even angular spread.
		var t := (float(i) + 0.5) / float(ctx.n)
		var r := radius * sqrt(t)
		var a := golden * i
		var jitter := Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * (radius * 0.04)
		ctx.pos[i] = c + Vector2(cos(a), sin(a)) * r + jitter
