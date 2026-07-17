class_name BiomeAssign
extends RefCounted

## Node-side biome assignment over a placed graph ctx (GraphPlacement.Ctx).
## Constructive "guarantee rung" scheme -- no solver: N rungs spread evenly
## over the POPULATED interior depths each receive 1-2 required-cast biomes
## DISJOINT from every other rung's draw. Every start->end path crosses each
## populated depth exactly once, so every path sees >= N distinct required
## biomes; WHICH ones depends on the route (route choice = biome choice).
## Non-guarantee rungs get 1-2 ambient variety biomes (whole pool, weighted,
## avoiding the previous rung's picks). All draws come from one seeded rng.


## Assign a biome index (into bset.biomes) to every active ctx node.
## Returns {node_biome: PackedInt32Array (ctx.n long, -1 = inactive),
##   cast: PackedInt32Array, n_guaranteed: int,
##   rungs: [{depth: int, biomes: PackedInt32Array, guarantee: bool}, ...]}.
static func assign(ctx, bset: WorldBiomeSet, seed_val: int) -> Dictionary:
	var node_biome := PackedInt32Array()
	node_biome.resize(ctx.n)
	node_biome.fill(-1)
	var out := {"node_biome": node_biome, "cast": PackedInt32Array(),
		"n_guaranteed": 0, "rungs": []}
	if bset == null or bset.biomes.is_empty():
		push_warning("[BiomeAssign] empty WorldBiomeSet -- nodes stay biome -1.")
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Populated interior depths (poles are assigned last, by inheritance).
	var by_depth: Dictionary[int, Array] = {}                       # depth -> Array[int] of active node ids
	for i in range(ctx.n):
		if ctx.active[i] == 0 or i == ctx.start_id or i == ctx.end_id:
			continue
		var d: int = ctx.depth[i]
		if not by_depth.has(d):
			by_depth[d] = []
		by_depth[d].append(i)
	var depths: Array = by_depth.keys()
	depths.sort()
	if depths.is_empty():                    # degenerate graph: just the poles
		node_biome[ctx.start_id] = 0
		node_biome[ctx.end_id] = 0
		return out

	# Guarantee rung selection: even spread over the populated interior depths.
	var n_req: int = clampi(bset.required_count, 0, depths.size())
	var guard: Dictionary[int, bool] = {}                          # depth -> true
	for i in range(n_req):
		guard[depths[int((float(i) + 0.5) * depths.size() / n_req)]] = true

	# Cast draw: 1 biome per small guarantee rung, 2 per rung with >= 4 nodes
	# (a 2-biome rung splits geographically, so the route picks between them).
	var want: Dictionary[int, int] = {}                           # depth -> rung biome count
	var slots := 0
	for d in guard:
		want[d] = 2 if by_depth[d].size() >= 4 else 1
		slots += want[d]
	var cast := bset.draw_required_cast(rng, slots)
	if cast.size() < guard.size():
		push_warning("[BiomeAssign] pool too small: %d cast biomes for %d guarantee rungs (path guarantee weakened)." % [cast.size(), guard.size()])

	# Deal in depth order: round 1 gives every guarantee rung one biome, round 2
	# tops up the wide rungs while cast biomes remain. Disjoint by construction.
	var dealt: Dictionary[int, Array] = {}                          # depth -> Array[int]
	var ci := 0
	for d in depths:
		if guard.has(d):
			dealt[d] = []
			if ci < cast.size():
				dealt[d].append(cast[ci])
				ci += 1
	for d in depths:
		if guard.has(d) and want[d] == 2 and ci < cast.size():
			dealt[d].append(cast[ci])
			ci += 1

	# Walk rungs in depth order: guarantee rungs use their deal, the rest get
	# ambient variety avoiding the previous rung's picks.
	var prev: Array = []
	var rungs: Array = []
	var n_guaranteed := 0
	for d in depths:
		var nodes: Array = by_depth[d]
		var is_guard: bool = guard.has(d)
		var chosen: Array = dealt.get(d, [])
		if is_guard and not chosen.is_empty():
			n_guaranteed += 1
		if chosen.is_empty():                # ambient rung (or the cast ran dry)
			chosen = _pick_ambient(bset, rng, 2 if nodes.size() >= 4 else 1, prev)
		_split_rung(ctx, nodes, chosen, node_biome)
		rungs.append({"depth": d, "biomes": PackedInt32Array(chosen), "guarantee": is_guard})
		prev = chosen

	# Poles inherit the nearest adjacent-rung node's biome.
	node_biome[ctx.start_id] = node_biome[_nearest(ctx, by_depth[depths[0]], ctx.pos[ctx.start_id])]
	node_biome[ctx.end_id] = node_biome[_nearest(ctx, by_depth[depths[depths.size() - 1]], ctx.pos[ctx.end_id])]

	out["cast"] = cast
	out["n_guaranteed"] = n_guaranteed
	out["rungs"] = rungs
	return out


## Weighted sample of k distinct biome indices from the WHOLE pool (ambient
## rungs may use any biome), avoiding `exclude` unless that empties the pool.
static func _pick_ambient(bset: WorldBiomeSet, rng: RandomNumberGenerator, k: int, exclude: Array) -> Array:
	var pool: Array = []
	for i in range(bset.biomes.size()):
		if not exclude.has(i):
			pool.append(i)
	if pool.size() < k:                      # tiny pools: repeats vs prev rung beat starving
		pool.clear()
		for i in range(bset.biomes.size()):
			pool.append(i)
	var chosen: Array = []
	for _j in range(mini(k, pool.size())):
		var total := 0.0
		for i in pool:
			total += maxf(0.001, bset.biomes[i].weight)
		var roll := rng.randf() * total
		var pick: int = pool[pool.size() - 1]
		for i in pool:
			roll -= maxf(0.001, bset.biomes[i].weight)
			if roll <= 0.0:
				pick = i
				break
		chosen.append(pick)
		pool.erase(pick)
	return chosen


## Split one rung's nodes between its 1-2 biomes as CONTIGUOUS geographic runs:
## group by landmass (ctx.lane restarts per landmass), order in-group by lane
## then perp projection, order groups by mean perp, concatenate, cut into
## proportional runs. Landmass groups of < 3 nodes stay single-biome.
static func _split_rung(ctx, nodes: Array, biomes: Array, node_biome: PackedInt32Array) -> void:
	if biomes.is_empty():
		return
	var groups: Dictionary[int, Array] = {}                         # landmass label -> Array[int]
	for id in nodes:
		var lab: int = ctx.node_label[id]
		if not groups.has(lab):
			groups[lab] = []
		groups[lab].append(id)
	var glist: Array = groups.values()
	for g in glist:
		g.sort_custom(func(a, b):
			if ctx.lane[a] != ctx.lane[b]:
				return ctx.lane[a] < ctx.lane[b]
			return ctx.pos[a].dot(ctx.perp) < ctx.pos[b].dot(ctx.perp))
	glist.sort_custom(func(ga, gb):
		return _mean_perp(ctx, ga) < _mean_perp(ctx, gb))
	var ordered: Array = []
	for g in glist:
		ordered.append_array(g)
	var k := biomes.size()
	var total := ordered.size()
	for idx in range(total):
		node_biome[ordered[idx]] = biomes[clampi(idx * k / total, 0, k - 1)]
	for g in glist:                          # small islands stay coherent
		if g.size() > 1 and g.size() < 3:
			for id in g:
				node_biome[id] = node_biome[g[0]]


## Mean perp-axis projection of a node group (orders landmass groups across the rung).
static func _mean_perp(ctx, g: Array) -> float:
	var s := 0.0
	for id in g:
		s += ctx.pos[id].dot(ctx.perp)
	return s / maxi(1, g.size())


## Id of the node in `candidates` closest to `p` (pole biome inheritance).
static func _nearest(ctx, candidates: Array, p: Vector2) -> int:
	var best: int = candidates[0]
	var bd := INF
	for id in candidates:
		var d2: float = ctx.pos[id].distance_squared_to(p)
		if d2 < bd:
			bd = d2
			best = id
	return best
