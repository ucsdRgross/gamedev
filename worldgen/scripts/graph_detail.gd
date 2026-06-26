class_name GraphDetail
extends RefCounted

## Step C: turn the straight graph edges from GraphPlacement into terrain-fitting curves.
##  - WATER / ferry edges curve AROUND land (A* over a cost field where water is cheap and
##    land is expensive), so a crossing hugs open water instead of cutting through islands.
##  - LAND edges keep a CONSISTENT HEIGHT (A* penalising deviation from the endpoints'
##    average elevation) and avoid holes/lakes, so a route bends around peaks and water.
##
## Pure data (reads only the height field), so it stays thread-safe for the harness.
## Returns an Array of [u, v, PackedVector2Array world-points] — one polyline per edge.

static func compute_curves(ctx, field, opts: Dictionary = {}) -> Array:
	var ds: int = maxi(1, int(opts.get("route_downscale", 4)))
	var curves: Array = []
	var occ := {}                                  # cell (Vector2i @ ds) -> taken by a prior route
	for u in range(ctx.n):
		if ctx.active[u] == 0:
			continue
		for v in ctx.adj[u]:
			var a: Vector2 = ctx.pos[u]
			var b: Vector2 = ctx.pos[v]
			# A ferry = endpoints on different landmasses OR a straight line over water.
			var water_mode :bool= ctx.node_label[u] != ctx.node_label[v] or GraphPlacement.edge_crosses_water(field, a, b)
			var target_h :float= (field.height_at(a) + field.height_at(b)) * 0.5
			var pts := _route(field, a, b, water_mode, target_h, ds, opts, occ)
			_stamp(occ, pts, ds)                   # later routes avoid these cells -> no overlap
			curves.append([u, v, pts])
	return curves

## Mark a routed polyline's INTERIOR cells as occupied (skip near the endpoints, where
## many edges legitimately converge on a shared node).
static func _stamp(occ: Dictionary, pts: PackedVector2Array, ds: int) -> void:
	if pts.size() < 2:
		return
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	var walked := 0.0
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		var steps := maxi(1, int(seg / maxf(1.0, float(ds))))
		for s in range(steps + 1):
			var f := (walked + seg * float(s) / steps) / maxf(1.0, total)
			if f < 0.15 or f > 0.85:
				continue                           # leave node neighbourhoods free
			var pt := pts[i].lerp(pts[i + 1], float(s) / steps)
			var cxx := int(pt.x / ds)
			var cyy := int(pt.y / ds)
			for oy in range(-1, 2):                # thicken the wall so parallel routes keep a gap
				for ox in range(-1, 2):
					occ[Vector2i(cxx + ox, cyy + oy)] = true
		walked += seg

## A* between world points a and b over a downscaled, bounded grid. There is NO straight-
## line fallback for long routes (it would look out of place among curves); instead, cells
## far from the straight line and cells used by earlier routes act as IMAGINARY WALLS
## (extra cost) so the route stays near its line and never overlaps another curve.
static func _route(field, a: Vector2, b: Vector2, water_mode: bool, target_h: float, ds: int, opts: Dictionary, occ: Dictionary = {}) -> PackedVector2Array:
	var straight := PackedVector2Array([a, b])
	var land_pen: float = opts.get("route_land_penalty", 8.0)     # cost of land for a ferry
	var water_pen: float = opts.get("route_water_penalty", 8.0)   # cost of water for a land route
	var slope_w: float = opts.get("route_slope_weight", 10.0)     # height-consistency weight
	var occ_pen: float = opts.get("route_occupancy_penalty", 10.0) # wall cost for a taken cell
	var corr_w: float = opts.get("route_corridor_penalty", 12.0)  # wall cost beyond the corridor
	var corridor: float = opts.get("route_corridor_ratio", 0.35) * a.distance_to(b) + ds * 2.0
	var over_w: float = opts.get("route_overshoot_penalty", 18.0) # wall cost for going PAST an endpoint
	var ab := b - a                                               # a->b axis; used to detect overshoot
	var ab_len2: float = maxf(1.0, ab.length_squared())
	var ab_len: float = sqrt(ab_len2)

	# Search box = bounding rect of a,b grown by a margin (room to detour), clamped to map.
	var margin: float = a.distance_to(b) * float(opts.get("route_margin", 0.7)) + 16.0
	var x0 := clampi(int((minf(a.x, b.x) - margin) / ds), 0, int(field.w / ds))
	var y0 := clampi(int((minf(a.y, b.y) - margin) / ds), 0, int(field.h / ds))
	var x1 := clampi(int((maxf(a.x, b.x) + margin) / ds), 0, int(field.w / ds))
	var y1 := clampi(int((maxf(a.y, b.y) + margin) / ds), 0, int(field.h / ds))
	var gw := x1 - x0 + 1
	var gh := y1 - y0 + 1
	if gw < 2 or gh < 2:
		return straight
	var n := gw * gh
	var start_i := (int(a.y / ds) - y0) * gw + (int(a.x / ds) - x0)
	var goal_i := (int(b.y / ds) - y0) * gw + (int(b.x / ds) - x0)
	if start_i < 0 or start_i >= n or goal_i < 0 or goal_i >= n:
		return straight

	var gscore := PackedFloat32Array(); gscore.resize(n); gscore.fill(INF)
	var came := PackedInt32Array(); came.resize(n); came.fill(-1)
	var closed := PackedByteArray(); closed.resize(n)
	var hf: Array = []      # heap: parallel f-scores
	var hi: Array = []      # heap: parallel cell indices
	gscore[start_i] = 0.0
	_heap_push(hf, hi, _heur(start_i, goal_i, gw, ds), start_i)

	var iter := 0
	var iter_cap := n * 4 + 64
	var found := false
	while not hf.is_empty():
		iter += 1
		if iter > iter_cap:
			break
		var cur := _heap_pop(hf, hi)
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		if cur == goal_i:
			found = true
			break
		var cx := cur % gw
		var cy := cur / gw
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
					continue
				var ni := ny * gw + nx
				if closed[ni] == 1:
					continue
				var base := _cell_cost(field, x0 + nx, y0 + ny, ds, water_mode, target_h, land_pen, water_pen, slope_w, occ, occ_pen)
				var world := Vector2((x0 + nx + 0.5) * ds, (y0 + ny + 0.5) * ds)
				var dseg := _dist_to_seg(world, a, b)
				if dseg > corridor:                 # imaginary wall: ramp cost outside the corridor
					base += corr_w * (dseg - corridor) / maxf(1.0, float(ds))
				# Overshoot wall: punish cells whose projection lands PAST b (t>1) or behind a
				# (t<0), so the route can't sail beyond its destination and loop back to it.
				var tproj: float = ab.dot(world - a) / ab_len2
				if tproj < 0.0 or tproj > 1.0:
					var over: float = (-tproj if tproj < 0.0 else tproj - 1.0) * ab_len
					base += over_w * over / maxf(1.0, float(ds))
				var step := (1.41421356 if dx != 0 and dy != 0 else 1.0) * base
				var ng: float = gscore[cur] + step
				if ng < gscore[ni]:
					gscore[ni] = ng
					came[ni] = cur
					_heap_push(hf, hi, ng + _heur(ni, goal_i, gw, ds), ni)

	if not found:
		return straight
	# Reconstruct (goal -> start), convert cells to world centres, then orient start->end.
	var rev := PackedVector2Array()
	var c := goal_i
	while c != -1:
		var cx := c % gw
		var cy := c / gw
		rev.append(Vector2((x0 + cx + 0.5) * ds, (y0 + cy + 0.5) * ds))
		if c == start_i:
			break
		c = came[c]
	var pts := PackedVector2Array()
	pts.append(a)
	for i in range(rev.size() - 1, -1, -1):       # reversed = start..goal
		pts.append(rev[i])
	pts.append(b)
	return _los_simplify(field, pts, water_mode, target_h, ds, opts, occ)

## Distance from point p to segment a-b.
static func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Line-of-sight "string pull": collapse the A* staircase to the fewest points whose
## straight segments still respect the terrain rule. Over a uniform region (e.g. open
## ocean for a ferry) the whole run becomes ONE straight segment -- no jaggedness; bends
## appear only where a straight line would hit forbidden terrain (land / water / a peak).
static func _los_simplify(field, pts: PackedVector2Array, water_mode: bool, target_h: float, ds: int, opts: Dictionary, occ: Dictionary = {}) -> PackedVector2Array:
	if pts.size() <= 2:
		return pts
	var tol: float = opts.get("route_height_tol", 0.15)
	var out := PackedVector2Array([pts[0]])
	var anchor := 0
	for i in range(2, pts.size()):
		if not _segment_clear(field, pts[anchor], pts[i], water_mode, target_h, tol, ds, occ):
			out.append(pts[i - 1])                # last point still in line of sight
			anchor = i - 1
	out.append(pts[pts.size() - 1])
	return out

## Is the straight a->b admissible? (ferry: all water; land: all land AND within `tol` of
## the target height) AND it must not pass through a cell another route already took (so
## straightening can't re-create an overlap the A* detour avoided).
static func _segment_clear(field, a: Vector2, b: Vector2, water_mode: bool, target_h: float, tol: float, ds: int, occ: Dictionary = {}) -> bool:
	var steps := maxi(1, int(a.distance_to(b) / maxf(1.0, float(ds))))
	for s in range(steps + 1):
		var pt := a.lerp(b, float(s) / steps)
		var f := float(s) / steps
		if f > 0.15 and f < 0.85 and occ.has(Vector2i(int(pt.x / ds), int(pt.y / ds))):
			return false                          # would overlap another route
		var hh :float= field.height_at(pt)
		if water_mode:
			if hh >= field.oth:
				return false                      # would cross land
		else:
			if hh < field.oth or absf(hh - target_h) > tol:
				return false                      # would cross water or a peak/hole
	return true

static func _cell_cost(field, cx: int, cy: int, ds: int, water_mode: bool, target_h: float, land_pen: float, water_pen: float, slope_w: float, occ: Dictionary = {}, occ_pen: float = 0.0) -> float:
	var extra := occ_pen if occ.has(Vector2i(cx, cy)) else 0.0   # steer away from taken cells
	var h :float= field.height_at(Vector2((cx + 0.5) * ds, (cy + 0.5) * ds))
	if water_mode:
		return (1.0 if h < field.oth else land_pen) + extra      # ferry: hug water, avoid land
	if h < field.oth:
		return water_pen + extra                                 # land route: avoid holes/lakes
	return 1.0 + slope_w * absf(h - target_h) + extra            # land route: keep height (avoid peaks)

static func _heur(i: int, goal: int, gw: int, ds: int) -> float:
	var dx: float = float((i % gw) - (goal % gw))
	var dy: float = float((i / gw) - (goal / gw))
	return sqrt(dx * dx + dy * dy)                          # admissible (min step cost = 1)

# --- binary min-heap over parallel Arrays (Array is by-reference; Packed* is not) ---
static func _heap_push(hf: Array, hi: Array, f: float, idx: int) -> void:
	hf.append(f); hi.append(idx)
	var c := hf.size() - 1
	while c > 0:
		var p := (c - 1) >> 1
		if hf[p] <= hf[c]:
			break
		var tf = hf[p]; hf[p] = hf[c]; hf[c] = tf
		var ti = hi[p]; hi[p] = hi[c]; hi[c] = ti
		c = p

static func _heap_pop(hf: Array, hi: Array) -> int:
	var top: int = hi[0]
	var last := hf.size() - 1
	hf[0] = hf[last]; hi[0] = hi[last]
	hf.remove_at(last); hi.remove_at(last)
	var n := hf.size()
	var c := 0
	while true:
		var l := 2 * c + 1
		var r := 2 * c + 2
		var s := c
		if l < n and hf[l] < hf[s]:
			s = l
		if r < n and hf[r] < hf[s]:
			s = r
		if s == c:
			break
		var tf = hf[c]; hf[c] = hf[s]; hf[s] = tf
		var ti = hi[c]; hi[c] = hi[s]; hi[s] = ti
		c = s
	return top
