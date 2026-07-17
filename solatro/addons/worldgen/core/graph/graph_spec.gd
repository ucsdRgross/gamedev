class_name GraphSpec
extends RefCounted

## Step A of graph placement: build a rule-correct directed acyclic graph as PURE
## DATA -- no coordinates, no map. Topology is authored directly so every rule is
## satisfied by construction (cities per path, nodes between cities, graph width,
## outgoing degree, start/end connectivity, acyclic). Deterministic from a seed.
##
## Structure: a layered DAG. Ranks 0..R along the abstract start->end axis. Cities
## sit on every `gap = nodes_between_cities + 1`-th rank; the rest are travel ranks.
## Terminal ranks (start at 0, end at R) hold a single node; interior ranks hold
## `width` parallel lanes. Edges only go rank r -> r+1 (so the graph is acyclic and
## every start->end path visits exactly one node per rank).
##
## build() returns a plain Dictionary (thread-safe to pass around / cache):
##   {
##     "nodes": Array[Dictionary]  # {id, rank, lane, is_city, role}
##     "adj":   Dictionary         # id:int -> Array[int] forward neighbours
##     "start": int, "end": int, "ranks": int,
##   }

## v2 node-only generation (no edges). Depth layers 0..D: layer 0 = start, layer D =
## end (both single city nodes); city layers every gap. Each interior layer gets a
## RANDOM node count in [layer_min, layer_max], independent of the target width (it
## over-provisions nodes; edge creation later picks which to use). Returns:
##   { "nodes": [{id, depth, is_city}], "layers": Array[Array[int]], "ranks": D,
##     "start": int, "end": int, "gap": int }
static func build_nodes(cities: int, nodes_between_cities: int, layer_min: int,
		layer_max: int, seed_val: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	cities = maxi(2, cities)
	var gap := maxi(1, nodes_between_cities + 1)
	var ranks := (cities - 1) * gap
	layer_min = maxi(1, layer_min)
	layer_max = maxi(layer_min, layer_max)

	var nodes: Array[Dictionary] = []
	var layers: Array = []
	layers.resize(ranks + 1)
	for r in range(ranks + 1):
		layers[r] = []
		var is_city := (r % gap == 0)
		var count := 1 if (r == 0 or r == ranks) else rng.randi_range(layer_min, layer_max)
		for _i in range(count):
			var id := nodes.size()
			nodes.append({"id": id, "depth": r, "is_city": is_city})
			layers[r].append(id)
	return {"nodes": nodes, "layers": layers, "ranks": ranks,
		"start": layers[0][0], "end": layers[ranks][0], "gap": gap}

## Build from explicit spec values (used directly by unit tests).
static func build(cities: int, nodes_between_cities: int, width: int, outgoing: int,
		min_outgoing_after_trim: int, edge_trim_chance: float, seed_val: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	cities = maxi(2, cities)
	var gap := maxi(1, nodes_between_cities + 1)
	width = maxi(1, width)
	outgoing = maxi(1, outgoing)
	var after_trim := clampi(min_outgoing_after_trim, 1, outgoing)
	var ranks := (cities - 1) * gap          # rank 0 = start, rank `ranks` = end

	# Lane count per rank. A single start/end node can only fan to `outgoing`
	# targets per rank, so the graph physically cannot be `width` wide right next
	# to a terminal. We RAMP the width: fan out 1 -> .. -> width from the start
	# (bounded by outgoing each step) and narrow width -> .. -> 1 into the end.
	# This keeps the DAG valid (no orphans, degree cap respected) for ANY params.
	var lanes_at := _lane_ramp(ranks, width, outgoing)

	# --- Nodes, grouped by rank ---------------------------------------------
	var nodes: Array[Dictionary] = []
	var by_rank: Array = []                  # by_rank[r] = Array[int] of node ids
	by_rank.resize(ranks + 1)
	for r in range(ranks + 1):
		by_rank[r] = []
		var lanes: int = lanes_at[r]
		var is_city := (r % gap == 0)        # city ranks (incl. start & end)
		for lane in range(lanes):
			var role := "mid"
			if r == 0:
				role = "start"
			elif r == ranks:
				role = "end"
			var id := nodes.size()
			nodes.append({"id": id, "rank": r, "lane": lane, "is_city": is_city, "role": role})
			by_rank[r].append(id)

	var adj: Dictionary[int, Array] = {}
	for n in nodes:
		adj[n["id"]] = []

	# --- Edges: spread fan. Lane L of rank r connects to `outgoing` lanes of rank
	# r+1 at positions (L*outgoing + j) mod C1. This is a base-`outgoing` expansion:
	# it (a) covers every next-rank lane (no orphans, since C1 <= Cr*outgoing by the
	# lane ramp), (b) gives every node degree <= outgoing, and (c) maximises how
	# fast a single node's reachable set grows (x outgoing per rank), so graph-width
	# is met up to what's structurally achievable -- no coverage/widening hacks.
	for r in range(ranks):
		var src: Array = by_rank[r]
		var dst: Array = by_rank[r + 1]
		var c1: int = dst.size()
		var k := mini(outgoing, c1)
		for li in range(src.size()):
			var su: int = src[li]
			var seen: Dictionary[int, bool] = {}
			var chosen: Array[int] = []
			for j in range(k):
				var lane := (li * outgoing + j) % c1
				if not seen.has(lane):
					seen[lane] = true
					chosen.append(dst[lane])
			adj[su] = chosen

	var removed := _trim_edges(nodes, adj, by_rank, ranks, after_trim, edge_trim_chance, rng)
	_ensure_width(removed, lanes_at, nodes, adj, by_rank, ranks, gap, width, outgoing)

	return {
		"nodes": nodes, "adj": adj,
		"start": by_rank[0][0], "end": by_rank[ranks][0], "ranks": ranks,
	}

# ---------------------------------------------------------------------------
## Lane count per rank: 1 at both terminals, fanning to `width` in the middle but
## never wider than a chain of `outgoing`-fan-outs from the nearest terminal can
## feed/drain. Guarantees lanes_at[r+1] <= lanes_at[r] * outgoing on the growing
## side (so the incoming-coverage pass never has to exceed the outgoing cap).
static func _lane_ramp(ranks: int, width: int, outgoing: int) -> Array:
	var cap_l := []        # widest reachable fanning forward from the start
	var cap_r := []        # widest reachable fanning backward from the end
	cap_l.resize(ranks + 1)
	cap_r.resize(ranks + 1)
	cap_l[0] = 1
	for r in range(1, ranks + 1):
		cap_l[r] = mini(width, cap_l[r - 1] * outgoing)
	cap_r[ranks] = 1
	for r in range(ranks - 1, -1, -1):
		cap_r[r] = mini(width, cap_r[r + 1] * outgoing)
	var lanes := []
	lanes.resize(ranks + 1)
	for r in range(ranks + 1):
		if r == 0 or r == ranks:
			lanes[r] = 1
		else:
			lanes[r] = maxi(1, mini(width, mini(cap_l[r], cap_r[r])))
	return lanes

## Drop surplus edges (keeping >= after_trim per node and never orphaning a target)
## so the graph isn't a perfect lattice -- adds topological variety. Returns the
## list of removed [u, v] edges so width repair can re-add them if needed.
static func _trim_edges(nodes: Array, adj: Dictionary, by_rank: Array, ranks: int,
		after_trim: int, trim_chance: float, rng: RandomNumberGenerator) -> Array:
	var removed: Array = []
	if trim_chance <= 0.0:
		return removed
	var indeg: Dictionary[int, int] = {}
	for u in adj.keys():
		for v in adj[u]:
			indeg[v] = indeg.get(v, 0) + 1
	for u in adj.keys():
		var kept: Array[int] = []
		for v in adj[u]:
			if kept.size() < after_trim:
				kept.append(v)
				continue
			if indeg.get(v, 0) > 1 and rng.randf() < trim_chance:
				indeg[v] -= 1   # drop this edge
				removed.append([u, v])
			else:
				kept.append(v)
		adj[u] = kept
	return removed

## Distinct nodes a single city (at `r`, lane `lane`) reaches at rank `ncr` in the
## UNTRIMMED spread. Simulates the exact fan -- (L*outgoing + j) mod C1 -- so it
## accounts for mod-wrap collisions (a clean outgoing^gap product would overestimate).
## This is the genuine width ceiling: when `width` is larger, the graph just grows as
## wide as it can. Build & validate call this identically so the target always agrees.
static func _ideal_reach(lanes_at: Array, r: int, ncr: int, outgoing: int, lane: int) -> int:
	var cur := {lane: true}
	for k in range(r, ncr):
		var c1: int = lanes_at[k + 1]
		var kk := mini(outgoing, c1)
		var nxt: Dictionary[int, bool] = {}
		for L in cur.keys():
			for j in range(kk):
				nxt[(L * outgoing + j) % c1] = true
		cur = nxt
	return cur.size()

## Restore graph-width after trimming: each city must reach min(width, achievable)
## distinct cities at the next city rank. We re-add edges that trim removed -- any
## removed edge u->v with u reachable from the city and v not yet reachable makes
## progress, and re-adding never orphans a node or exceeds the outgoing cap (it just
## restores an original spread edge). Re-adding ALL removed edges would fully rebuild
## the width-complete spread, so `want` is always attainable.
static func _ensure_width(removed: Array, lanes_at: Array, nodes: Array, adj: Dictionary,
		by_rank: Array, ranks: int, gap: int, width: int, outgoing: int) -> void:
	if width <= 1 or removed.is_empty():
		return
	for r in range(0, ranks, gap):              # city ranks
		var ncr := r + gap
		if ncr > ranks:
			break
		for cu in by_rank[r]:
			var want := mini(width, _ideal_reach(lanes_at, r, ncr, outgoing, nodes[cu]["lane"]))
			var guard := 0
			var limit := removed.size() + want + 8
			while guard < limit:
				var reached := _reach_set(adj, nodes, cu, ncr)
				if _count_at_rank(reached, nodes, ncr) >= want:
					break
				guard += 1
				# Re-add a removed edge that extends this city's reachable frontier.
				var added := false
				for e in removed:
					var u: int = e[0]
					var v: int = e[1]
					if reached.has(u) and not reached.has(v) and nodes[v]["rank"] <= ncr:
						if not (v in adj[u]):
							adj[u].append(v)
							added = true
							break
				if not added:
					break

## Forward-reachable set from cu (ids), not expanding past rank ncr.
static func _reach_set(adj: Dictionary, nodes: Array, cu: int, ncr: int) -> Dictionary:
	var reached := {cu: true}
	var stack: Array[int] = [cu]
	while not stack.is_empty():
		var u: int = stack.pop_back()
		if nodes[u]["rank"] >= ncr:
			continue
		for v in adj[u]:
			if not reached.has(v):
				reached[v] = true
				stack.push_back(v)
	return reached

static func _count_at_rank(reached: Dictionary, nodes: Array, target_rank: int) -> int:
	var n := 0
	for id in reached.keys():
		if nodes[id]["rank"] == target_rank:
			n += 1
	return n

## Set of city ids at `target_rank` reachable from `src` going forward.
static func _cities_reached(adj: Dictionary, nodes: Array, src: int, target_rank: int) -> Dictionary:
	var seen: Dictionary[int, bool] = {}
	var out: Dictionary[int, bool] = {}
	var stack: Array[int] = [src]
	seen[src] = true
	while not stack.is_empty():
		var u: int = stack.pop_back()
		if nodes[u]["rank"] == target_rank:
			out[u] = true
			continue
		for v in adj[u]:
			if not seen.has(v):
				seen[v] = true
				stack.push_back(v)
	return out

# ---------------------------------------------------------------------------
# Data-only validation (used by graph_spec_test). Returns Array of violation dicts
# {rule, detail}; empty = all rules satisfied.
# ---------------------------------------------------------------------------
static func validate(g: Dictionary, cities: int, nodes_between_cities: int,
		width: int, outgoing: int, min_outgoing_after_trim: int) -> Array:
	var v: Array = []
	var nodes: Array = g["nodes"]
	var adj: Dictionary = g["adj"]
	var start: int = g["start"]
	var end: int = g["end"]
	var ranks: int = g["ranks"]
	# Clamp inputs exactly as build() does, so invalid values (0, negatives, at>out)
	# are judged against what build actually produced.
	cities = maxi(2, cities)
	width = maxi(1, width)
	outgoing = maxi(1, outgoing)
	var gap := maxi(1, nodes_between_cities + 1)
	var after_trim := clampi(min_outgoing_after_trim, 1, outgoing)

	# Precompute rank -> node ids and lane counts once (otherwise O(nodes^2)).
	var by_rank: Array = []
	by_rank.resize(ranks + 1)
	for r in range(ranks + 1):
		by_rank[r] = []
	for n in nodes:
		by_rank[n["rank"]].append(n["id"])
	var lanes_at: Array = []
	lanes_at.resize(ranks + 1)
	for r in range(ranks + 1):
		lanes_at[r] = by_rank[r].size()

	# Degrees + acyclic-by-rank (every edge must go to a strictly later rank).
	var indeg: Dictionary[int, int] = {}
	for u in adj.keys():
		for w in adj[u]:
			indeg[w] = indeg.get(w, 0) + 1
			if nodes[w]["rank"] <= nodes[u]["rank"]:
				v.append({"rule": "not_forward", "detail": "%d->%d" % [u, w]})
	for n in nodes:
		var id: int = n["id"]
		var od: int = adj[id].size()
		if id == end:
			if od != 0:
				v.append({"rule": "end_has_outgoing", "detail": str(od)})
		else:
			# Degree range is capped by how many targets actually exist on the next
			# rank (e.g. the rank before `end` can only reach the single end node).
			var dcount: int = by_rank[n["rank"] + 1].size()
			var min_deg := mini(after_trim, dcount)
			var max_deg := mini(outgoing, dcount)
			if od < min_deg or od > max_deg:
				v.append({"rule": "outgoing_degree", "detail": "node %d deg=%d (want %d..%d)" % [id, od, min_deg, max_deg]})
		if id != start and indeg.get(id, 0) == 0:
			v.append({"rule": "orphan", "detail": "node %d" % id})

	# Start/end connectivity: start reaches end.
	if not _reaches(adj, start, end):
		v.append({"rule": "no_path", "detail": "start cannot reach end"})

	# Cities per path, nodes-between-cities: guaranteed by rank structure, but
	# verify the rank math produced the intended counts.
	var city_ranks := 0
	for r in range(ranks + 1):
		if r % gap == 0:
			city_ranks += 1
	if city_ranks != cities:
		v.append({"rule": "cities_visited", "detail": "%d city ranks, wanted %d" % [city_ranks, cities]})
	if ranks != (cities - 1) * gap:
		v.append({"rule": "nodes_between_cities", "detail": "ranks=%d" % ranks})

	# Graph width: every city reaches min(width, ideal-spread-reach) distinct cities
	# at the next city rank. ideal reach is the exact untrimmed fan reach for this
	# city's lane (so an unattainable `width` just means "as wide as the fan grows").
	for r in range(0, ranks, gap):
		var ncr := r + gap
		if ncr > ranks:
			break
		for cu in by_rank[r]:
			var want := mini(width, _ideal_reach(lanes_at, r, ncr, outgoing, nodes[cu]["lane"]))
			var reached := _cities_reached(adj, nodes, cu, ncr).size()
			if reached < want:
				v.append({"rule": "graph_width", "detail": "city %d reaches %d/%d" % [cu, reached, want]})
	return v

static func _reaches(adj: Dictionary, src: int, dst: int) -> bool:
	var seen := {src: true}
	var stack: Array[int] = [src]
	while not stack.is_empty():
		var u: int = stack.pop_back()
		if u == dst:
			return true
		for w in adj[u]:
			if not seen.has(w):
				seen[w] = true
				stack.push_back(w)
	return false
