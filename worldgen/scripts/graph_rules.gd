class_name GraphRules
extends RefCounted

## Validation + statistics for the traversal graph. Kept separate from
## GraphBuilder so the test suite can validate/measure graphs produced by any
## future algorithm. All functions are static and pure (read-only on the gen).
##
## A graph is {Vector2 -> Array[Vector2]}; meta is {Vector2 -> {biome, landmass,
## is_city, height}} as produced by GraphBuilder. Paths are Array[Vector2].

# ---------------------------------------------------------------------------
# Path enumeration (DAG; capped to avoid combinatorial blow-up)
# ---------------------------------------------------------------------------
static func enumerate_paths(graph: Dictionary, start: Vector2, end: Vector2, cap: int) -> Array:
	var paths: Array = []
	var cur: Array[Vector2] = [start]
	_dfs_paths(graph, start, end, cur, paths, cap)
	return paths

static func _dfs_paths(graph: Dictionary, node: Vector2, end: Vector2, cur: Array, paths: Array, cap: int) -> void:
	if paths.size() >= cap:
		return
	if node == end:
		paths.append(cur.duplicate())
		return
	if not graph.has(node):
		return
	for child in graph[node]:
		if child in cur:
			continue  # safety against any accidental cycle
		cur.append(child)
		_dfs_paths(graph, child, end, cur, paths, cap)
		cur.pop_back()
		if paths.size() >= cap:
			return

# ---------------------------------------------------------------------------
# Per-path measurements
# ---------------------------------------------------------------------------
## Path "length" reported in NODE COUNT (number of nodes visited), not pixels.
static func path_node_count(path: Array) -> int:
	return path.size()

## Euclidean pixel length (internal use only: the max_path_length cap).
static func path_distance(path: Array) -> float:
	var d := 0.0
	for i in range(path.size() - 1):
		d += path[i].distance_to(path[i + 1])
	return d

## Summed length of LAND edges only (water edges = different landmass, exempt).
static func path_land_distance(path: Array, meta: Dictionary) -> float:
	var d := 0.0
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]; var b: Vector2 = path[i + 1]
		if _same_landmass(meta, a, b):
			d += a.distance_to(b)
	return d

static func biome_run_lengths(path: Array, meta: Dictionary) -> Array:
	var runs: Array = []
	var run := 0
	var prev := -999
	for p in path:
		var bid: int = meta.get(p, {}).get("biome", -1)
		if bid != prev:
			if run > 0: runs.append(run)
			run = 1; prev = bid
		else:
			run += 1
	if run > 0: runs.append(run)
	return runs  # one entry per contiguous same-biome run; length = node count

static func biomes_traversed(path: Array, meta: Dictionary) -> int:
	return biome_run_lengths(path, meta).size()

## Travel-node counts between consecutive cities, e.g. [2,3,1] for c..c..c..c.
static func nodes_between_cities(path: Array, meta: Dictionary) -> Array:
	var segs: Array = []
	var count := 0
	var seen_city := false
	for p in path:
		var is_city: bool = meta.get(p, {}).get("is_city", false)
		if is_city:
			if seen_city:
				segs.append(count)
			seen_city = true
			count = 0
		elif seen_city:
			count += 1
	return segs

## "Graph width" of a city: how many DISTINCT other cities it can directly reach
## by walking forward through travel nodes (stopping at the next cities). Travel
## nodes are transparent; cities are terminals. One value per city.
static func city_width_of(graph: Dictionary, meta: Dictionary, node: Vector2) -> int:
	var found := {}
	var seen := {}
	var stack: Array = graph.get(node, []).duplicate()
	while not stack.is_empty():
		var x = stack.pop_back()
		if seen.has(x):
			continue
		seen[x] = true
		if meta.get(x, {}).get("is_city", false):
			found[x] = true  # terminal: a reachable city, don't expand past it
		else:
			for c in graph.get(x, []):
				stack.push_back(c)
	return found.size()

static func city_widths(graph: Dictionary, meta: Dictionary) -> Array:
	var out: Array = []
	for node in graph.keys():
		if not meta.get(node, {}).get("is_city", false):
			continue
		out.append(city_width_of(graph, meta, node))
	return out

## "Biome width" of a node (any node): how many DISTINCT differing biomes it can
## directly reach by walking forward through same-biome nodes (stopping when the
## biome changes). One value per node.
static func biome_widths(graph: Dictionary, meta: Dictionary) -> Array:
	var out: Array = []
	for node in graph.keys():
		var b0: int = meta.get(node, {}).get("biome", -1)
		var found := {}
		var seen := {}
		var stack: Array = graph.get(node, []).duplicate()
		while not stack.is_empty():
			var x = stack.pop_back()
			if seen.has(x):
				continue
			seen[x] = true
			var bx: int = meta.get(x, {}).get("biome", -2)
			if bx != b0:
				found[bx] = true  # reached a different biome; stop here
			else:
				for c in graph.get(x, []):
					stack.push_back(c)
		out.append(found.size())
	return out

## Path length (summed edge px) between each pair of consecutive cities -- the
## physical distance a player travels city-to-city.
static func city_lengths(path: Array, meta: Dictionary) -> Array:
	var out: Array = []
	var prev: Variant = null
	var acc := 0.0
	var seen_city := false
	for p in path:
		if prev != null:
			acc += (prev as Vector2).distance_to(p)
		if meta.get(p, {}).get("is_city", false):
			if seen_city:
				out.append(acc)
			seen_city = true
			acc = 0.0
		prev = p
	return out

static func cities_in_path(path: Array, meta: Dictionary) -> int:
	var c := 0
	for p in path:
		if meta.get(p, {}).get("is_city", false):
			c += 1
	return c

# ---------------------------------------------------------------------------
# Shorthand formatters (reused by the live print and the test report)
# ---------------------------------------------------------------------------
static func format_path_cities(path: Array, meta: Dictionary) -> String:
	var segs := nodes_between_cities(path, meta)
	if segs.is_empty():
		return "(no city-to-city segments)"
	return ",".join(segs.map(func(x): return str(x)))

static func format_path_biomes(path: Array, meta: Dictionary) -> String:
	var runs := biome_run_lengths(path, meta)
	return ",".join(runs.map(func(x): return str(x)))

# ---------------------------------------------------------------------------
# Aggregate stats over all (enumerated) paths
# ---------------------------------------------------------------------------
static func collect_stats(graph: Dictionary, start: Vector2, end: Vector2, settings: WorldSettings, meta: Dictionary) -> Dictionary:
	var paths := enumerate_paths(graph, start, end, settings.max_paths_enumerated)
	var out := {
		"path_count": paths.size(),
		"truncated": paths.size() >= settings.max_paths_enumerated,
	}
	if paths.is_empty():
		return out

	var dists: Array = []
	var biome_counts: Array = []
	var all_city_segs: Array = []
	var all_biome_runs: Array = []
	var cities_per_path: Array = []
	var all_city_lengths: Array = []
	for path in paths:
		dists.append(path_node_count(path))
		biome_counts.append(biomes_traversed(path, meta))
		cities_per_path.append(cities_in_path(path, meta))
		all_city_segs.append_array(nodes_between_cities(path, meta))
		all_biome_runs.append_array(biome_run_lengths(path, meta))
		all_city_lengths.append_array(city_lengths(path, meta))

	var graph_w := city_widths(graph, meta)
	var biome_w := biome_widths(graph, meta)

	out["path_dist"] = _stat_block(dists)
	out["biomes"] = _stat_block(biome_counts)
	out["steps_between_cities"] = _stat_block(all_city_segs)
	out["steps_in_biome"] = _stat_block(all_biome_runs)
	out["graph_width"] = _stat_block(graph_w)
	out["biome_width"] = _stat_block(biome_w)
	out["city_length"] = _stat_block(all_city_lengths)

	# Representative paths (by total distance).
	var idx_sorted: Array = range(paths.size())
	idx_sorted.sort_custom(func(a, b): return dists[a] < dists[b])
	var i_short: int = idx_sorted[0]
	var i_long: int = idx_sorted[idx_sorted.size() - 1]
	var i_med: int = idx_sorted[idx_sorted.size() / 2]
	out["longest_path_cities"] = format_path_cities(paths[i_long], meta)
	out["longest_path_biomes"] = format_path_biomes(paths[i_long], meta)
	out["shortest_path_cities"] = format_path_cities(paths[i_short], meta)
	out["shortest_path_biomes"] = format_path_biomes(paths[i_short], meta)
	out["median_path_cities"] = format_path_cities(paths[i_med], meta)
	out["median_path_biomes"] = format_path_biomes(paths[i_med], meta)

	# Raw arrays so the suite can build cross-run histograms.
	out["raw_cities_per_path"] = cities_per_path
	out["raw_nodes_between_cities"] = all_city_segs
	out["raw_biomes_per_path"] = biome_counts
	out["raw_nodes_per_biome"] = all_biome_runs
	out["raw_graph_width"] = graph_w
	out["raw_biome_width"] = biome_w
	return out

static func _stat_block(vals: Array) -> Dictionary:
	if vals.is_empty():
		return {"longest": 0.0, "shortest": 0.0, "median": 0.0, "average": 0.0}
	var s := vals.duplicate()
	s.sort()
	var total := 0.0
	for v in s: total += float(v)
	return {
		"longest": float(s[s.size() - 1]),
		"shortest": float(s[0]),
		"median": float(s[s.size() / 2]),
		"average": total / float(s.size()),
	}

# ---------------------------------------------------------------------------
# Pretty print (A5 statistics block) — used by step_7_graph
# ---------------------------------------------------------------------------
static func print_stats(stats: Dictionary) -> void:
	print("[Graph] --- Traversal statistics (", stats.get("path_count", 0), " paths",
		(" CAPPED" if stats.get("truncated", false) else ""), ") ---")
	if stats.get("path_count", 0) == 0:
		print("  (no start->end paths)")
		return
	_print_block("path length (nodes)  ", stats["path_dist"], true)
	_print_block("biomes per path      ", stats["biomes"], true)
	_print_block("steps between cities ", stats["steps_between_cities"], true)
	_print_block("steps in one biome   ", stats["steps_in_biome"], true)
	_print_block("graph width (cities) ", stats["graph_width"], true)
	_print_block("biome width (nodes)  ", stats["biome_width"], true)
	_print_block("city length (px)     ", stats["city_length"], false)
	# Shorthands: nodes-between-cities is the "2,3,1" form (travel nodes between
	# each consecutive pair of cities); nodes-per-biome is the "2,2" form (length
	# of each contiguous same-biome run).
	print("  longest  path | nodes-between-cities: %s | nodes-per-biome: %s" % [stats["longest_path_cities"], stats["longest_path_biomes"]])
	print("  shortest path | nodes-between-cities: %s | nodes-per-biome: %s" % [stats["shortest_path_cities"], stats["shortest_path_biomes"]])
	print("  median   path | nodes-between-cities: %s | nodes-per-biome: %s" % [stats["median_path_cities"], stats["median_path_biomes"]])

## Human-readable dump of the seed + every graph parameter that shaped this
## graph (one labelled line each), so a glance explains what each lever does.
static func format_graph_params(s: WorldSettings) -> String:
	var lines: Array[String] = [
		"world seed: %d" % s.main_seed,
		"layers along the start->end axis: %d" % s.layer_count,
		"outgoing edges chosen per node: %d to %d" % [s.min_outgoing, s.max_outgoing],
		"land edge length (px): %.0f shortest, %.0f longest allowed" % [s.min_path_dist, s.max_path_search_dist],
		"max summed land length of a whole path (px): %.0f (water travel exempt)" % s.max_path_length,
		"travel nodes between two consecutive cities: %d to %d" % [s.min_nodes_between_cities, s.max_nodes_between_cities],
		"cities visited along a path: %d to %d" % [s.min_cities_visited, s.max_cities_visited],
		"graph width (distinct cities directly reachable from a city): at least %d" % s.min_graph_width,
		"biomes traversed per path: %d to %d" % [s.min_biomes_per_path, s.max_biomes_per_path],
		"continents that keep nodes (largest N by size): %d" % s.max_landmasses,
		"inter-continent water crossings in the graph: %d to %d" % [s.min_inter_landmass_edges, s.max_inter_landmass_edges],
		"longest single water crossing (px): %.0f" % s.max_water_crossing_dist,
		"mountain-pass routing bias (higher = hug low passes): %.2f" % s.mountain_pass_bias,
		"lateral spread (higher = wider, less direct graph): %.2f" % s.graph_lateral_spread,
		"penalty for starting/ending on a small island: %.0f" % s.start_end_island_penalty,
		"min nearby nodes required at start/end (else penalized): %d" % s.start_end_min_connections,
		"failsafe nodes the builder may inject to keep paths valid: %d" % s.failsafe_max_injected_nodes,
		"start->end paths enumerated for stats/validation: up to %d" % s.max_paths_enumerated,
		"build passes (diagnose + modify nodes between): %d" % s.graph_build_passes,
	]
	return "\n    " + "\n    ".join(lines)

static func _print_block(label: String, b: Dictionary, integral: bool) -> void:
	if integral:
		print("  %s  long=%d short=%d median=%d avg=%.2f" % [label, int(b["longest"]), int(b["shortest"]), int(b["median"]), b["average"]])
	else:
		print("  %s  long=%.1f short=%.1f median=%.1f avg=%.1f" % [label, b["longest"], b["shortest"], b["median"], b["average"]])

# ---------------------------------------------------------------------------
# Rule validation — returns Array of {rule, detail}; empty = all pass
# ---------------------------------------------------------------------------
static func validate(gen: WorldGenerator, graph: Dictionary, start: Vector2, end: Vector2, settings: WorldSettings, meta: Dictionary) -> Array:
	var v: Array = []

	# Structural: self/duplicate edges, water nodes, degree, dead-ends.
	for node in graph.keys():
		var children: Array = graph[node]
		var seen := {}
		var deg := 0
		for c in children:
			if c == node:
				v.append({"rule": "self_edge", "detail": str(node)})
			if seen.has(c):
				v.append({"rule": "duplicate_edge", "detail": "%s->%s" % [node, c]})
			seen[c] = true
			deg += 1
		var m: Dictionary = meta.get(node, {})
		if m.get("height", 1.0) < settings.ocean_threshold:
			v.append({"rule": "water_node", "detail": str(node)})
		if node != end:
			if deg == 0:
				v.append({"rule": "dead_end", "detail": str(node)})
			elif deg < settings.min_outgoing or deg > settings.max_outgoing:
				v.append({"rule": "outgoing_degree", "detail": "%s deg=%d" % [node, deg]})

	# Graph width: every city (except the end node, which is a terminal with no
	# outgoing edges) must directly reach at least min_graph_width cities.
	for node in graph.keys():
		if node == end or not meta.get(node, {}).get("is_city", false):
			continue
		var gw := city_width_of(graph, meta, node)
		if gw < settings.min_graph_width:
			v.append({"rule": "graph_width", "detail": "city reaches %d cities" % gw})

	# Acyclic check.
	if _has_cycle(graph, start):
		v.append({"rule": "cycle", "detail": "graph is not acyclic"})

	# Edge geometry: inter-landmass water edges + same-landmass ocean crossings.
	var inter := 0
	for node in graph.keys():
		for c in graph[node]:
			if not _same_landmass(meta, node, c):
				inter += 1
				var dist :float= node.distance_to(c)
				if dist > settings.max_water_crossing_dist:
					v.append({"rule": "water_edge_too_long", "detail": "%.0f>%.0f" % [dist, settings.max_water_crossing_dist]})
				if not _ocean_only(gen, node, c, settings):
					v.append({"rule": "water_edge_hits_land", "detail": "%s->%s" % [node, c]})
			else:
				# Same landmass must not travel across open ocean.
				if _crosses_ocean(gen, node, c, settings):
					v.append({"rule": "same_landmass_ocean", "detail": "%s->%s" % [node, c]})
	if inter < settings.min_inter_landmass_edges:
		v.append({"rule": "too_few_inter_landmass", "detail": "%d<%d" % [inter, settings.min_inter_landmass_edges]})
	if inter > settings.max_inter_landmass_edges:
		v.append({"rule": "too_many_inter_landmass", "detail": "%d>%d" % [inter, settings.max_inter_landmass_edges]})

	# Connectivity + per-path windows.
	var paths := enumerate_paths(graph, start, end, settings.max_paths_enumerated)
	if paths.is_empty():
		v.append({"rule": "no_path", "detail": "start cannot reach end"})
		return v
	for path in paths:
		var cv := cities_in_path(path, meta)
		if cv < settings.min_cities_visited or cv > settings.max_cities_visited:
			v.append({"rule": "cities_visited", "detail": "path has %d cities" % cv})
		var bt := biomes_traversed(path, meta)
		if bt < settings.min_biomes_per_path or bt > settings.max_biomes_per_path:
			v.append({"rule": "biomes_per_path", "detail": "path traverses %d biomes" % bt})
		var land := path_land_distance(path, meta)
		if land > settings.max_path_length:
			v.append({"rule": "path_too_long", "detail": "land=%.0f>%.0f" % [land, settings.max_path_length]})
		for seg in nodes_between_cities(path, meta):
			if seg < settings.min_nodes_between_cities or seg > settings.max_nodes_between_cities:
				v.append({"rule": "nodes_between_cities", "detail": "segment=%d" % seg})
	return v

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
static func _same_landmass(meta: Dictionary, a: Vector2, b: Vector2) -> bool:
	var la: int = meta.get(a, {}).get("landmass", -1)
	var lb: int = meta.get(b, {}).get("landmass", -1)
	return la == lb and la >= 0

static func _ocean_only(gen: WorldGenerator, a: Vector2, b: Vector2, settings: WorldSettings) -> bool:
	# Interior samples must all be ocean (touch land only at the endpoints).
	var w := settings.map_width; var h := settings.map_height
	var steps := maxi(8, int(a.distance_to(b) / 3.0))
	for s in range(1, steps):
		var p := a.lerp(b, float(s) / float(steps))
		var px := clampi(int(p.x), 0, w - 1); var py := clampi(int(p.y), 0, h - 1)
		if gen.height_buffer[(py * w) + px] >= settings.ocean_threshold:
			return false
	return true

static func _crosses_ocean(gen: WorldGenerator, a: Vector2, b: Vector2, settings: WorldSettings) -> bool:
	# True if a meaningful run of the straight line is over ocean (a bay/strait).
	var w := settings.map_width; var h := settings.map_height
	var steps := maxi(8, int(a.distance_to(b) / 3.0))
	var ocean := 0
	for s in range(1, steps):
		var p := a.lerp(b, float(s) / float(steps))
		var px := clampi(int(p.x), 0, w - 1); var py := clampi(int(p.y), 0, h - 1)
		if gen.height_buffer[(py * w) + px] < settings.ocean_threshold:
			ocean += 1
	return float(ocean) / float(maxi(1, steps - 1)) > 0.25

static func _has_cycle(graph: Dictionary, start: Vector2) -> bool:
	# Iterative DFS coloring over all graph nodes.
	var color := {}  # 0=unvisited,1=in-stack,2=done
	for node in graph.keys():
		if color.get(node, 0) != 0:
			continue
		var stack: Array = [[node, 0]]
		color[node] = 1
		while not stack.is_empty():
			var top: Array = stack[stack.size() - 1]
			var u: Vector2 = top[0]
			var ci: int = top[1]
			var children: Array = graph.get(u, [])
			if ci < children.size():
				top[1] = ci + 1
				var c: Vector2 = children[ci]
				var col: int = color.get(c, 0)
				if col == 1:
					return true
				elif col == 0:
					color[c] = 1
					stack.append([c, 0])
			else:
				color[u] = 2
				stack.pop_back()
	return false
