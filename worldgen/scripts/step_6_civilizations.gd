class_name Step6Civilizations
extends GenerationStep

func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	var valid_mainland_map := _label_continents(gen, settings)

	# --- Graph-demand-driven density --------------------------------------
	# Population is derived from the graph rules so the requested graph is
	# actually buildable (the old "scatter N, hope it's enough" was the flaw):
	#   * enough cities to fill every city-layer with branching room, and
	#   * enough travel nodes that each layer is populated for min..max_outgoing.
	# max_city_count / max_travel_count stay as the desired (rich-map) targets;
	# the derived numbers are hard FLOORS that adaptive relaxation guarantees.
	var gap := maxi(2, clampi(int(round(
		(settings.min_nodes_between_cities + settings.max_nodes_between_cities) / 2.0)),
		settings.min_nodes_between_cities, settings.max_nodes_between_cities) + 1)
	var city_layers := 0
	var L := gap
	while L < settings.layer_count:
		city_layers += 1
		L += gap
	var needed_cities: int = maxi(settings.min_cities_visited + 2,
		(city_layers + 2) * maxi(1, settings.min_graph_width))
	var needed_travel: int = settings.layer_count * maxi(3, settings.max_outgoing + 1)

	var city_target: int = maxi(settings.max_city_count, needed_cities)
	var travel_target: int = maxi(settings.max_travel_count, needed_travel)

	# Land candidate pools (reused across relaxation rounds).
	var city_pool := _land_pool(gen, settings, valid_mainland_map, city_target * 4)
	var travel_pool := _land_pool(gen, settings, valid_mainland_map, travel_target * 3)

	# Cities: prefer coasts AND spread evenly across biomes (round-robin by biome,
	# coastal-first within each biome). Travel nodes stay a uniform dense field.
	# Spacing ratios are resolution-independent (fractions of the map diagonal).
	var diag := settings.map_diag()
	_place_cities(gen, settings, gen.city_nodes, city_pool, settings.city_dist_ratio * diag, city_target, needed_cities)
	_place_spaced(gen.travel_nodes, travel_pool, settings.travel_dist_ratio * diag, travel_target, needed_travel)

	if gen.city_nodes.size() < needed_cities:
		push_warning("[Civilizations] only %d/%d cities placed (land too small/sparse)"
			% [gen.city_nodes.size(), needed_cities])

	_print_node_debug(gen, settings, needed_cities, needed_travel)
	gen._save_snapshot_bridge("Cities")

## Greedy biome-balanced city placement: round-robin over biomes (even spread),
## taking the most-coastal remaining candidate of each biome that respects
## spacing. Relaxes spacing if the graph's city floor isn't met.
func _place_cities(gen: WorldGenerator, settings: WorldSettings, into: Array, pool: Array, spacing: float, target: int, floor_count: int) -> void:
	# Water lookup (rivers + lakes) so cities can favour fresh water too, not just
	# the ocean coast. Cities sit a ring-radius AWAY from water (near, not on it).
	var water := {}
	for r in gen.river_nodes:
		water[r] = true
	for l in gen.lake_nodes:
		water[l] = true

	var buckets := {}  # biome id -> Array of {pos, coast}
	for c in pool:
		var b := _biome_at(gen, settings, c)
		if not buckets.has(b):
			buckets[b] = []
		buckets[b].append({"pos": c, "coast": _water_score(gen, settings, c, water)})
	for b in buckets.keys():
		buckets[b].sort_custom(func(a, c): return a["coast"] > c["coast"])

	var cursor := {}
	var s := spacing
	for relax in range(6):
		for b in buckets.keys():
			cursor[b] = 0
		var added_any := true
		while into.size() < target and added_any:
			added_any = false
			for b in buckets.keys():
				if into.size() >= target:
					break
				var lst: Array = buckets[b]
				var ci: int = cursor[b]
				while ci < lst.size():
					var pos: Vector2 = lst[ci]["pos"]
					ci += 1
					var ok := true
					for p in into:
						if p.distance_to(pos) < s:
							ok = false
							break
					if ok:
						into.append(pos)
						added_any = true
						break
				cursor[b] = ci
		if into.size() >= floor_count:
			break
		s *= 0.6

## Water (ocean OR river/lake) samples on a jittered ring of ~coast_radius_ratio
## of the map diagonal -> higher = closer to water. The radius jitter + ring
## sampling means a high score implies water is NEAR the candidate, not directly
## under it (random offset, so cities sit just back from the bank rather than on it).
func _water_score(gen: WorldGenerator, settings: WorldSettings, c: Vector2, water: Dictionary) -> int:
	var w := settings.map_width
	var h := settings.map_height
	var coast_px := settings.coast_radius_ratio * settings.map_diag()
	var hits := 0
	for ang in range(0, 360, 45):
		var rad := deg_to_rad(float(ang))
		var rr: float = coast_px * randf_range(0.7, 1.4)
		var nx := clampi(int(c.x + cos(rad) * rr), 0, w - 1)
		var ny := clampi(int(c.y + sin(rad) * rr), 0, h - 1)
		var idx := (ny * w) + nx
		if gen.height_buffer[idx] < settings.ocean_threshold or water.has(Vector2i(nx, ny)):
			hits += 1
	return hits

func _biome_at(gen: WorldGenerator, settings: WorldSettings, c: Vector2) -> int:
	var w := settings.map_width
	return gen.biome_id_buffer[(int(c.y) * w) + int(c.x)]

## Counts, biome variety per node type, and median nearest-neighbour spacing.
func _print_node_debug(gen: WorldGenerator, settings: WorldSettings, need_c: int, need_t: int) -> void:
	var city_biomes := {}
	for c in gen.city_nodes:
		city_biomes[_biome_at(gen, settings, c)] = true
	var travel_biomes := {}
	for t in gen.travel_nodes:
		travel_biomes[_biome_at(gen, settings, t)] = true
	print("[Civilizations] nodes total=%d" % (gen.city_nodes.size() + gen.travel_nodes.size()))
	print("    cities: %d (floor %d) spanning %d distinct biomes | median spacing %.1f px"
		% [gen.city_nodes.size(), need_c, city_biomes.size(), _median_nn(gen.city_nodes)])
	print("    travel: %d (floor %d) spanning %d distinct biomes | median spacing %.1f px"
		% [gen.travel_nodes.size(), need_t, travel_biomes.size(), _median_nn(gen.travel_nodes)])

## Median of each point's nearest-neighbour distance (a robust spacing measure).
func _median_nn(points: Array) -> float:
	if points.size() < 2:
		return 0.0
	var ds: Array = []
	for i in range(points.size()):
		var best := INF
		for j in range(points.size()):
			if i == j:
				continue
			best = minf(best, points[i].distance_to(points[j]))
		ds.append(best)
	ds.sort()
	return ds[ds.size() / 2]

## Random above-sea points on the kept continents, up to `count`. Bounded attempts.
func _land_pool(gen: WorldGenerator, settings: WorldSettings, mask: Dictionary, count: int) -> Array:
	var w := settings.map_width
	var h := settings.map_height
	var out: Array[Vector2] = []
	var attempts := 0
	var cap := count * 12 + 2000
	while out.size() < count and attempts < cap:
		attempts += 1
		var c := Vector2(randf() * w, randf() * h)
		if not mask.has(Vector2i(c)):
			continue
		var idx := (int(c.y) * w) + int(c.x)
		if gen.height_buffer[idx] > settings.ocean_threshold + 0.05:
			out.append(c)
	return out

## Greedily place points from `pool` keeping `spacing` apart, up to `target`. If
## fewer than `floor_count` land (small/sparse continent), relax spacing and add
## more, so the graph's minimum density is met without thinning a rich map.
func _place_spaced(into: Array, pool: Array, spacing: float, target: int, floor_count: int) -> void:
	var s := spacing
	for round_i in range(6):
		for c in pool:
			if into.size() >= target:
				break
			var ok := true
			for p in into:
				if p.distance_to(c) < s:
					ok = false
					break
			if ok:
				into.append(c)
		if into.size() >= floor_count:
			break
		s *= 0.6

## Coarse (4px) flood fill that LABELS every above-sea landmass, keeps the
## top-N by size (settings.max_landmasses), and writes a per-cell continent id
## map onto the generator (gen.landmass_labels / gen.landmass_sizes) so the graph
## step can treat landmasses as nodes. Returns the placement mask (Vector2i ->
## true) covering all pixels of the kept continents.
func _label_continents(gen: WorldGenerator, settings: WorldSettings) -> Dictionary:
	var visited := {}
	var continents: Array[Array] = []
	var w = settings.map_width
	var h = settings.map_height
	
	for y in range(0, h, 4): 
		for x in range(0, w, 4):
			var start_p = Vector2i(x, y)
			if visited.has(start_p): continue
			
			var idx = (y * w) + x
			if gen.height_buffer[idx] <= settings.ocean_threshold: 
				continue
				
			var current_continent: Array[Vector2i] = []
			var queue: Array[Vector2i] = [start_p]
			visited[start_p] = true
			
			while not queue.is_empty():
				var curr = queue.pop_back()
				current_continent.append(curr)
				
				for offset in [Vector2i(-4,0), Vector2i(4,0), Vector2i(0,-4), Vector2i(0,4)]:
					var n = curr + offset
					if n.x >= 0 and n.x < w and n.y >= 0 and n.y < h:
						var n_idx = (n.y * w) + n.x
						if not visited.has(n) and gen.height_buffer[n_idx] > settings.ocean_threshold:
							visited[n] = true
							queue.push_back(n)
			continents.append(current_continent)
			
	gen.landmass_labels.clear()
	gen.landmass_sizes.clear()
	var major_continents_dict := {}
	if not continents.is_empty():
		continents.sort_custom(func(a, b): return a.size() > b.size())
		var kept = mini(maxi(1, settings.max_landmasses), continents.size())
		for i in range(kept):
			gen.landmass_sizes[i] = continents[i].size()
			for pos in continents[i]:
				gen.landmass_labels[pos] = i  # coarse 4px label grid
				for ox in range(4):
					for oy in range(4):
						var fill_p = pos + Vector2i(ox, oy)
						if fill_p.x < w and fill_p.y < h:
							major_continents_dict[fill_p] = true
							
	return major_continents_dict

## Continent id at a world position (snaps to the coarse 4px label grid, with a
## small neighbour search so near-coast nodes still resolve). -1 if none.
static func landmass_at(gen: WorldGenerator, pos: Vector2) -> int:
	var base := Vector2i(int(pos.x) & ~3, int(pos.y) & ~3)
	if gen.landmass_labels.has(base):
		return gen.landmass_labels[base]
	for r in [4, 8]:
		for oy in [-r, 0, r]:
			for ox in [-r, 0, r]:
				var k := base + Vector2i(ox, oy)
				if gen.landmass_labels.has(k):
					return gen.landmass_labels[k]
	return -1
