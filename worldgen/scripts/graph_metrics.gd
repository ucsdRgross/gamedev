class_name GraphMetrics
extends RefCounted

## Reward computation for the parameter-search harness. Pure CPU, no GPU and no
## shared mutation, so it is safe to call from worker threads against read-only
## base buffers. The composite reward scores a built graph by how much of the
## continent it covers AND how well it subdivides the land into medium-sized
## hollow regions (the "parallel-close vs spread-apart" discriminator), plus
## optional biome-variety and violation terms.
##
## Everything is computed on a coarse grid (cell size G px) so the score is
## map-size invariant. Land = cell-center height >= ocean_threshold; ocean is
## excluded from coverage, hollows, and total_land.

## Tunable reward levers (a plain search lever, NOT a WorldSettings field).
class RewardConfig extends RefCounted:
	var w_coverage: float = 1.0
	var w_hollow: float = 1.0
	# Hollow scoring mode. "uniform" = honeycomb: reward many EQUAL-sized hollows
	# via the inverse-Simpson effective count (no size target). "target" = legacy
	# gaussian bump peaked at hollow_target_cells.
	var hollow_mode: String = "uniform"
	var ref_cells_per_hollow: float = 40.0 # uniform-mode scale factor (NOT a size
											# target): normalizes k_eff so w_hollow
											# means the same across tiers
	var hollow_target_cells: float = 40.0  # target-mode only: hollow area (cells) that scores best
	var hollow_spread: float = 30.0        # target-mode only: gaussian falloff width
	var w_biome: float = 0.0  # disabled: map biome counts aren't yet a tunable lever (see plan backlog)
	var w_violation: float = 0.05
	var w_spread: float = 0.25             # reward node bbox area / land bbox area (anti corner-clustering)
	var grid_px: float = 8.0               # coarse-grid cell size in map px

	func duplicate_cfg() -> RewardConfig:
		var c := RewardConfig.new()
		c.w_coverage = w_coverage
		c.w_hollow = w_hollow
		c.hollow_mode = hollow_mode
		c.ref_cells_per_hollow = ref_cells_per_hollow
		c.hollow_target_cells = hollow_target_cells
		c.hollow_spread = hollow_spread
		c.w_biome = w_biome
		c.w_violation = w_violation
		c.w_spread = w_spread
		c.grid_px = grid_px
		return c

# ---------------------------------------------------------------------------
# Public: composite reward + its broken-out terms.
# ---------------------------------------------------------------------------
## Returns {reward, coverage, hollow, biome, violations}. reward is 0 if the
## graph has no path (empty graph) -- the search treats unsafe configs as 0 so
## they self-eject. `violations` is passed in (caller runs GraphRules.validate so
## this module stays free of WorldSettings/gen dependencies).
static func evaluate(graph_result: Dictionary, height: PackedFloat32Array,
		biome: PackedInt32Array, w: int, h: int, ocean_threshold: float,
		cfg: RewardConfig, violations: int) -> Dictionary:
	var graph: Dictionary = graph_result.get("graph", {})
	if graph.is_empty():
		return {"reward": 0.0, "coverage": 0.0, "hollow": 0.0, "keff": 0.0,
			"biome": 0.0, "spread": 0.0, "violations": violations}

	var grid := _build_grid(graph, height, w, h, ocean_threshold, cfg.grid_px)
	var coverage := _coverage_fraction(grid)
	var areas := _hollow_areas(grid)
	var keff := _k_eff(areas)
	var hollow := 0.0
	if cfg.hollow_mode == "target":
		hollow = _hollow_target(areas, grid["land_count"], cfg.hollow_target_cells, cfg.hollow_spread)
	else:
		hollow = _hollow_uniform(keff, grid["land_count"], cfg.ref_cells_per_hollow)
	var biome_score := _biome_fraction(graph, biome, w, h)
	var spread := _spread_fraction(graph, grid)

	var reward := maxf(0.0,
		cfg.w_coverage * coverage
		+ cfg.w_hollow * hollow
		+ cfg.w_biome * biome_score
		+ cfg.w_spread * spread
		- cfg.w_violation * float(violations))
	return {"reward": reward, "coverage": coverage, "hollow": hollow, "keff": keff,
		"biome": biome_score, "spread": spread, "violations": violations}

# ---------------------------------------------------------------------------
# Coarse grid: per-cell land flag + covered flag.
# ---------------------------------------------------------------------------
## Returns {gw, gh, land:PackedByteArray, covered:PackedByteArray, land_count}.
## land[i]=1 if the cell center is land; covered[i]=1 if any graph edge/node
## passes through the cell (dilated by one ring).
static func _build_grid(graph: Dictionary, height: PackedFloat32Array,
		w: int, h: int, ocean_threshold: float, gpx: float) -> Dictionary:
	var gw := maxi(1, int(ceil(float(w) / gpx)))
	var gh := maxi(1, int(ceil(float(h) / gpx)))
	var n := gw * gh
	var land := PackedByteArray()
	land.resize(n)
	var land_count := 0
	for gy in range(gh):
		var py := clampi(int((float(gy) + 0.5) * gpx), 0, h - 1)
		for gx in range(gw):
			var px := clampi(int((float(gx) + 0.5) * gpx), 0, w - 1)
			if height[(py * w) + px] >= ocean_threshold:
				land[(gy * gw) + gx] = 1
				land_count += 1

	# Rasterize edges (and implicitly nodes, as edge endpoints) into a raw mask.
	var raw := PackedByteArray()
	raw.resize(n)
	var step := gpx * 0.5
	for parent in graph.keys():
		var a: Vector2 = parent
		for child in graph[parent]:
			var b: Vector2 = child
			var d := a.distance_to(b)
			var samples := maxi(1, int(d / step))
			for s in range(samples + 1):
				var p := a.lerp(b, float(s) / float(samples))
				var cx := clampi(int(p.x / gpx), 0, gw - 1)
				var cy := clampi(int(p.y / gpx), 0, gh - 1)
				raw[(cy * gw) + cx] = 1

	# Dilate by one ring so thin diagonal lines read as a continuous footprint.
	var covered := PackedByteArray()
	covered.resize(n)
	for gy in range(gh):
		for gx in range(gw):
			if raw[(gy * gw) + gx] == 0:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := gx + dx
					var ny := gy + dy
					if nx >= 0 and nx < gw and ny >= 0 and ny < gh:
						covered[(ny * gw) + nx] = 1

	return {"gw": gw, "gh": gh, "gpx": gpx, "land": land, "covered": covered, "land_count": land_count}

# ---------------------------------------------------------------------------
# Coverage fraction: covered land / total land.
# ---------------------------------------------------------------------------
static func _coverage_fraction(grid: Dictionary) -> float:
	var land_count: int = grid["land_count"]
	if land_count == 0:
		return 0.0
	var land: PackedByteArray = grid["land"]
	var covered: PackedByteArray = grid["covered"]
	var hit := 0
	for i in range(land.size()):
		if land[i] == 1 and covered[i] == 1:
			hit += 1
	return float(hit) / float(land_count)

# ---------------------------------------------------------------------------
# Hollow analysis. Flood-fill the uncovered LAND into connected components
# ("hollows") and return each hollow's area (in grid cells). The two scoring
# modes (uniform/target) below consume this list.
# ---------------------------------------------------------------------------
static func _hollow_areas(grid: Dictionary) -> PackedInt32Array:
	var areas := PackedInt32Array()
	var land_count: int = grid["land_count"]
	if land_count == 0:
		return areas
	var gw: int = grid["gw"]
	var gh: int = grid["gh"]
	var land: PackedByteArray = grid["land"]
	var covered: PackedByteArray = grid["covered"]
	var n := gw * gh
	var visited := PackedByteArray()
	visited.resize(n)

	var stack: Array[int] = []
	for start in range(n):
		if visited[start] == 1:
			continue
		# Only flood through uncovered land.
		if land[start] == 0 or covered[start] == 1:
			visited[start] = 1
			continue
		var area := 0
		stack.clear()
		stack.append(start)
		visited[start] = 1
		while not stack.is_empty():
			var i: int = stack.pop_back()
			area += 1
			var ix := i % gw
			var iy := int(i / gw)
			for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := ix + off.x
				var ny := iy + off.y
				if nx < 0 or nx >= gw or ny < 0 or ny >= gh:
					continue
				var j := (ny * gw) + nx
				if visited[j] == 1:
					continue
				if land[j] == 1 and covered[j] == 0:
					visited[j] = 1
					stack.append(j)
				else:
					visited[j] = 1
		areas.append(area)
	return areas

## Inverse-Simpson / participation ratio: the EFFECTIVE number of equal-sized
## hollows. (Sum a)^2 / Sum(a^2). M equal hollows -> M; one huge hollow -> 1;
## a few big + many tiny slivers -> ~1 (Sum(a^2) dominated by the big ones).
static func _k_eff(areas: PackedInt32Array) -> float:
	var s := 0.0
	var s2 := 0.0
	for a in areas:
		s += float(a)
		s2 += float(a) * float(a)
	if s2 <= 0.0:
		return 0.0
	return (s * s) / s2

## Uniform (honeycomb) mode: reward many equal hollows. Normalize k_eff by a
## reference count (total_land / ref_cells_per_hollow) so the term sits ~0..1 and
## w_hollow means the same across tiers. ref_cells_per_hollow is a scale factor,
## NOT a per-hollow size target. Subdivision is bounded in practice by the node
## budget (more hollows need more edges -> higher coverage), so this does not
## chase infinite subdivision.
static func _hollow_uniform(keff: float, land_count: int, ref_cells: float) -> float:
	if land_count <= 0:
		return 0.0
	var ref_count := maxf(1.0, float(land_count) / maxf(1.0, ref_cells))
	return clampf(keff / ref_count, 0.0, 1.0)

## Legacy target mode: gaussian bump peaking at `target` cells, area-weighted,
## normalized by total land. Kept for A/B comparison against uniform mode.
static func _hollow_target(areas: PackedInt32Array, land_count: int, target: float, spread: float) -> float:
	if land_count <= 0:
		return 0.0
	var sp := maxf(1.0, spread)
	var total_weight := 0.0
	for a in areas:
		var bump := exp(-pow((float(a) - target) / sp, 2.0))
		total_weight += bump * float(a)
	return total_weight / float(land_count)

## Spread guard: node bounding-box area / land bounding-box area (0..1). Low when
## the graph clusters in one corner; high when nodes span the landmass. Cheap
## anti-clustering term beyond what coverage gives.
static func _spread_fraction(graph: Dictionary, grid: Dictionary) -> float:
	var nodes := {}
	for parent in graph.keys():
		nodes[parent] = true
		for child in graph[parent]:
			nodes[child] = true
	if nodes.size() < 2:
		return 0.0
	var minx := INF; var miny := INF; var maxx := -INF; var maxy := -INF
	for p in nodes.keys():
		var pos: Vector2 = p
		minx = minf(minx, pos.x); maxx = maxf(maxx, pos.x)
		miny = minf(miny, pos.y); maxy = maxf(maxy, pos.y)
	var node_area := maxf(0.0, maxx - minx) * maxf(0.0, maxy - miny)  # px^2
	# Land bbox from the grid, converted to px via the cell size.
	var gw: int = grid["gw"]
	var gh: int = grid["gh"]
	var gpx: float = grid["gpx"]
	var land: PackedByteArray = grid["land"]
	var lminx := gw; var lminy := gh; var lmaxx := -1; var lmaxy := -1
	for gy in range(gh):
		for gx in range(gw):
			if land[(gy * gw) + gx] == 1:
				lminx = mini(lminx, gx); lmaxx = maxi(lmaxx, gx)
				lminy = mini(lminy, gy); lmaxy = maxi(lmaxy, gy)
	if lmaxx < lminx:
		return 0.0
	var land_area := float((lmaxx - lminx + 1) * (lmaxy - lminy + 1)) * gpx * gpx  # px^2
	return clampf(node_area / maxf(1.0, land_area), 0.0, 1.0)

# ---------------------------------------------------------------------------
# Biome variety: distinct biome ids among graph nodes / distinct ids on the map.
# ---------------------------------------------------------------------------
static func _biome_fraction(graph: Dictionary, biome: PackedInt32Array, w: int, h: int) -> float:
	var map_ids := {}
	for v in biome:
		map_ids[v] = true
	if map_ids.is_empty():
		return 0.0
	var nodes := {}
	for parent in graph.keys():
		nodes[parent] = true
		for child in graph[parent]:
			nodes[child] = true
	var graph_ids := {}
	for p in nodes.keys():
		var pos: Vector2 = p
		var px := clampi(int(pos.x), 0, w - 1)
		var py := clampi(int(pos.y), 0, h - 1)
		graph_ids[biome[(py * w) + px]] = true
	return float(graph_ids.size()) / float(map_ids.size())
