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
	# Blue-noise land-only sample lattice (on the target landmass only). Graph nodes
	# are attracted to / snapped to these so they can never end up in water.
	var samples := PackedVector2Array()
	var _shash := {}                     # Vector2i cell -> Array[int] sample indices
	var _cs := 1.0                       # hash cell size (= sample spacing)

	static func from_generator(gen) -> MapField:
		var f := MapField.new()
		f.w = gen.settings.map_width
		f.h = gen.settings.map_height
		f.oth = gen.settings.ocean_threshold
		f.height = gen.height_buffer
		f._label_landmasses()
		f._measure_land()
		# Match the old travel-node spacing -> dense enough that every graph node
		# finds a distinct nearby land sample (~1000+ samples on a typical map).
		f.build_land_samples(gen.settings.map_diag() * 0.012, gen.settings.main_seed)
		return f

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

	## Jittered-grid land samples on ALL landmasses (one jittered point per cell).
	func build_land_samples(spacing: float, seed_val: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val * 100069
		_cs = maxf(2.0, spacing)
		samples = PackedVector2Array()
		_shash = {}
		var gx := int(ceil(w / _cs))
		var gy := int(ceil(h / _cs))
		for cy in range(gy):
			for cx in range(gx):
				var p := Vector2((cx + rng.randf()) * _cs, (cy + rng.randf()) * _cs)
				if in_bounds(p) and is_land(p):
					var idx := samples.size()
					samples.append(p)
					var key := Vector2i(int(p.x / _cs), int(p.y / _cs))
					if not _shash.has(key):
						_shash[key] = []
					_shash[key].append(idx)

	## Index of the nearest land sample to p; -1 if none. `skip` (optional) marks
	## already-used sample indices to ignore (for collision-free snapping).
	func nearest_sample_idx(p: Vector2, skip: Dictionary = {}) -> int:
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

	## Bounding box + centroid of ALL land (the graph spans every landmass).
	func _measure_land() -> void:
		var lo := Vector2(w, h)
		var hi := Vector2.ZERO
		var sum := Vector2.ZERO
		var n := 0
		for y in range(h):
			for x in range(w):
				if height[(y * w) + x] >= oth:
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

	## A land cell with open water within `radius` -> eligible for water travel.
	func is_coastal(p: Vector2, radius: float) -> bool:
		if not is_land(p):
			return false
		var r := maxi(1, int(radius))
		var stepi := maxi(1, r / 4)
		for dy in range(-r, r + 1, stepi):
			for dx in range(-r, r + 1, stepi):
				if not is_land(p + Vector2(dx, dy)):
					return true
		return false

	## Land extreme points along `dir`: [min_projection_point, max_projection_point].
	func axis_extremes(dir: Vector2) -> Array:
		var lo := INF
		var hi := -INF
		var lo_pt := land_centroid
		var hi_pt := land_centroid
		for y in range(h):
			for x in range(w):
				if height[(y * w) + x] >= oth:
					var pr := Vector2(x, y).dot(dir)
					if pr < lo:
						lo = pr; lo_pt = Vector2(x, y)
					if pr > hi:
						hi = pr; hi_pt = Vector2(x, y)
		return [lo_pt, hi_pt]

	## (min, max) of land projected onto `perp`, measured from `origin`.
	func perp_range(origin: Vector2, perp: Vector2) -> Vector2:
		var lo := INF
		var hi := -INF
		for y in range(h):
			for x in range(w):
				if height[(y * w) + x] >= oth:
					var pr := (Vector2(x, y) - origin).dot(perp)
					lo = minf(lo, pr); hi = maxf(hi, pr)
		if lo == INF:
			return Vector2(-1, 1)
		return Vector2(lo, hi)

# ---------------------------------------------------------------------------
# Shared force/layout context (mutated in place during the sim).
# ---------------------------------------------------------------------------
class Ctx extends RefCounted:
	var field: MapField
	var s: WorldSettings
	var pos: PackedVector2Array          # node id -> position
	var depth: PackedInt32Array          # node id -> rank
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

	# 1. Land attraction: a node over ocean is pulled toward the nearest land SAMPLE
	#    (well-defined even in deep ocean, where the height gradient is ~0). Combined
	#    with the final snap, nodes reliably end up on land.
	for i in range(ctx.n):
		var p := ctx.pos[i]
		if not ctx.field.is_land(p):
			var target := ctx.field.nearest_sample(p)
			var d := target - p
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
				var legal := ctx.field.is_coastal(ctx.pos[u], ctx.coast_radius) \
					and ctx.field.is_coastal(ctx.pos[v], ctx.coast_radius)
				if not legal:
					var fw := dir * dist * ctx.w_edge_water
					forces[u] += fw
					forces[v] -= fw

	# 4. Depth-axis monotonicity: pull each node's projection onto the start->end
	#    axis toward depth/max_depth of the way along it. Keeps depth ordered in
	#    space so edges never jump backwards across the map (anti-zigzag).
	# 5. Lane spread: pull each node toward its lane's perpendicular offset, fanning
	#    the graph across the landmass width (otherwise it collapses to a thin band).
	if ctx.axis_len > 0.0:
		for i in range(ctx.n):
			if i == ctx.start_id or i == ctx.end_id:
				continue
			var rel := ctx.pos[i] - ctx.start_pos
			var t := float(ctx.depth[i]) / float(maxi(1, ctx.max_depth))
			var along := rel.dot(ctx.axis)
			var want_along := t * ctx.axis_len
			forces[i] += ctx.axis * (want_along - along) * ctx.w_axis
			var perp := rel.dot(ctx.perp)
			forces[i] += ctx.perp * (ctx.perp_target[i] - perp) * ctx.w_perp

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
		seed_val: int, integrator: Integrator = null) -> Dictionary:
	var ctx := _make_ctx(graph, field, settings, seed_val)
	# Adaptive density: ensure clearly more land samples than nodes (so the final
	# snap finds a distinct sample per node and rarely needs the overlap fallback).
	if field.total_land > 0:
		var want_sp := sqrt(float(field.total_land) / float(maxi(1, ctx.n * 2)))
		var sp := minf(settings.map_diag() * 0.012, want_sp)
		if absf(sp - field._cs) > 0.5:
			field.build_land_samples(sp, seed_val)
	_init_filled_disc(ctx, seed_val)
	var init_pos := ctx.pos.duplicate()

	if integrator == null:
		integrator = FruchtermanReingold.new()
	integrator.setup(ctx)

	var max_steps := mini(2000, 40 + ctx.n * 8)   # cap scaled by node count
	var settled_for := 0
	var mid_pos := PackedVector2Array()
	var steps := 0
	for st in range(max_steps):
		steps = st + 1
		integrator.step()
		if st == max_steps / 2:
			mid_pos = ctx.pos.duplicate()
		if integrator.is_settled():
			settled_for += 1
			if settled_for >= 5:
				break
		else:
			settled_for = 0
	if mid_pos.is_empty():
		mid_pos = ctx.pos.duplicate()

	# Final snap: every node moves to the nearest UNUSED land sample, guaranteeing
	# no node sits in water and no two nodes overlap.
	_snap_to_land(ctx)

	return {"pos": ctx.pos, "ctx": ctx, "steps": steps,
		"init_pos": init_pos, "mid_pos": mid_pos}

## Greedy assign each node to the nearest land sample not already taken.
static func _snap_to_land(ctx: Ctx) -> void:
	if ctx.field.samples.is_empty():
		return
	var used := {}
	for i in range(ctx.n):
		var idx := ctx.field.nearest_sample_idx(ctx.pos[i], used)
		if idx < 0:                       # all samples taken -> reuse nearest (overlap
			idx = ctx.field.nearest_sample_idx(ctx.pos[i])   # ok, still guarantees land)
		if idx >= 0:
			ctx.pos[i] = ctx.field.samples[idx]
			used[idx] = true

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

## Water-travel rule: an edge crossing open water must run BETWEEN TWO COASTAL nodes
## (both endpoints are land cells near open water). Returns the list of offending
## edges [u, v] (water crossings where an endpoint isn't coastal). Step C trims
## these; here it's a metric/validator.
static func water_edge_violations(ctx: Ctx, coast_radius: float) -> Array:
	var bad: Array = []
	for u in range(ctx.n):
		for v in ctx.adj[u]:
			if edge_crosses_water(ctx.field, ctx.pos[u], ctx.pos[v]):
				if not (ctx.field.is_coastal(ctx.pos[u], coast_radius) and ctx.field.is_coastal(ctx.pos[v], coast_radius)):
					bad.append([u, v])
	return bad

# ---------------------------------------------------------------------------
static func _make_ctx(graph: Dictionary, field: MapField, settings: WorldSettings, seed_val: int) -> Ctx:
	var ctx := Ctx.new()
	ctx.field = field
	ctx.s = settings
	var nodes: Array = graph["nodes"]
	var adj_d: Dictionary = graph["adj"]
	ctx.n = nodes.size()
	ctx.pos = PackedVector2Array(); ctx.pos.resize(ctx.n)
	ctx.depth = PackedInt32Array(); ctx.depth.resize(ctx.n)
	ctx.adj = []
	ctx.adj.resize(ctx.n)
	ctx.max_depth = graph["ranks"]
	for nd in nodes:
		ctx.depth[nd["id"]] = nd["rank"]
	for id in range(ctx.n):
		ctx.adj[id] = adj_d.get(id, [])
	ctx.start_id = graph["start"]
	ctx.end_id = graph["end"]

	var diag := settings.map_diag()
	ctx.ideal_edge = diag * 0.05
	ctx.repel_dist = diag * 0.04
	ctx.coast_radius = settings.coast_radius_ratio * diag

	# Anchor start/end at the land extremes along a RANDOM axis direction (so the
	# run can span the continent in any orientation -- horizontal, vertical, or any
	# diagonal, in either direction depending on seed).
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val * 2654435761
	var ang := rng.randf() * TAU
	var dir := Vector2(cos(ang), sin(ang))
	var ext := field.axis_extremes(dir)
	ctx.start_pos = ext[0]
	ctx.end_pos = ext[1]
	ctx.pos[ctx.start_id] = ctx.start_pos
	ctx.pos[ctx.end_id] = ctx.end_pos
	ctx.axis = (ctx.end_pos - ctx.start_pos)
	ctx.axis_len = ctx.axis.length()
	if ctx.axis_len > 0.0:
		ctx.axis = ctx.axis / ctx.axis_len
	ctx.perp = Vector2(-ctx.axis.y, ctx.axis.x)     # axis rotated 90deg

	# Lanes fan out across the FULL landmass width perpendicular to the axis.
	var pr := field.perp_range(ctx.start_pos, ctx.perp)
	ctx.perp_extent = (pr.y - pr.x) * 0.5
	var perp_center := (pr.x + pr.y) * 0.5

	# Per-node perpendicular target from its lane within its rank -> lanes spread
	# symmetrically across the whole width (outermost lanes reach the coasts).
	var rank_count := {}
	for nd in nodes:
		rank_count[nd["rank"]] = rank_count.get(nd["rank"], 0) + 1
	ctx.perp_target = PackedFloat32Array()
	ctx.perp_target.resize(ctx.n)
	for nd in nodes:
		var cnt: int = rank_count[nd["rank"]]
		var frac := 0.0 if cnt <= 1 else (float(nd["lane"]) + 0.5) / float(cnt) - 0.5
		ctx.perp_target[nd["id"]] = perp_center + frac * (pr.y - pr.x)
	return ctx

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
