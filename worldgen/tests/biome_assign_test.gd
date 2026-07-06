extends Node

## Phase-1 gate for the Biomes step (run with F6): generates real maps through
## the Graph step, runs BiomeAssign over the placed ctx, prints the per-rung
## draw table, and verifies the constructive guarantees:
##   1) every active node holds a biome
##   2) guarantee-rung cast draws are disjoint
##   3) every node in a guarantee rung holds one of that rung's cast biomes
##   4) bitmask DP over ctx.adj: EVERY start->end path crosses >= N distinct
##      required-cast biomes (N = rungs that actually received cast biomes)
##   5) same seed twice -> identical assignment (determinism)

@export var seeds: Array[int] = [1, 2, 3, 4, 5]

var _gen: WorldGenerator
var _fails := 0

func _ready() -> void:
	_gen = WorldGenerator.new()
	add_child(_gen)
	await get_tree().process_frame
	print("=== BiomeAssign test ===")
	for sd in seeds:
		await _run_seed(sd)
	print("=== BiomeAssign test complete: %s ===" % ("PASS" if _fails == 0 else "FAIL (%d checks)" % _fails))
	get_tree().quit()


## Print one PASS/FAIL line and count failures for the summary.
func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print("  [%s] %s" % ["PASS" if ok else "FAIL", msg])


## Generate seed `sd` up to Graph, assign biomes, print the rung table, run all checks.
func _run_seed(sd: int) -> void:
	var bs := WorldSettings.new()
	bs.main_seed = sd
	_gen.settings = bs
	await _gen.generate_up_to(WorldGenerator.GenStep.GRAPH)
	var ctx = _gen.graph_ctx
	if ctx == null:
		_fails += 1
		print("-- seed %d: FAIL - no graph ctx after generate_up_to(GRAPH)" % sd)
		return
	var bset := WorldBiomeSet.make_default()
	var res := BiomeAssign.assign(ctx, bset, sd + 7)
	var res2 := BiomeAssign.assign(ctx, bset, sd + 7)

	print("-- seed %d: %d active nodes, max_depth %d, required_count %d" % [
		sd, _active_count(ctx), ctx.max_depth, bset.required_count])
	print("   cast: %s" % _names(bset, res.cast))
	for r in res.rungs:
		print("   d%02d %s nodes=%2d -> %s" % [r.depth,
			"GUARD" if r.guarantee else "     ",
			_rung_nodes(ctx, r.depth).size(), _names(bset, r.biomes)])

	_check(res.node_biome == res2.node_biome, "deterministic (same seed -> same assignment)")
	_check_all_assigned(ctx, res)
	_check_disjoint(bset, res)
	_check_rung_membership(ctx, res)
	_check_min_distinct(ctx, res)


## Check 1: every active node (poles included) got a biome index.
func _check_all_assigned(ctx, res: Dictionary) -> void:
	var missing := 0
	for i in range(ctx.n):
		if ctx.active[i] == 1 and res.node_biome[i] < 0:
			missing += 1
	_check(missing == 0, "all active nodes assigned (missing: %d)" % missing)


## Check 2: no biome appears in two different guarantee-rung draws.
func _check_disjoint(bset: WorldBiomeSet, res: Dictionary) -> void:
	var seen := {}
	var dupes := 0
	for r in res.rungs:
		if not r.guarantee:
			continue
		for b in r.biomes:
			if seen.has(b):
				dupes += 1
			seen[b] = true
	_check(dupes == 0, "guarantee-rung casts disjoint (dupes: %d)" % dupes)


## Check 3: every node in a guarantee rung holds one of its rung's cast biomes.
func _check_rung_membership(ctx, res: Dictionary) -> void:
	var bad := 0
	for r in res.rungs:
		if not r.guarantee or r.biomes.is_empty():
			continue
		for id in _rung_nodes(ctx, r.depth):
			if not res.node_biome[id] in r.biomes:
				bad += 1
	_check(bad == 0, "guarantee-rung nodes hold rung-cast biomes (violations: %d)" % bad)


## Check 4: bitmask DP over ctx.adj -- the minimum over all start->end paths of
## DISTINCT cast biomes seen must be >= n_guaranteed. State = per-node set of
## achievable cast bitmasks (cast <= ~8 biomes -> tiny mask space).
func _check_min_distinct(ctx, res: Dictionary) -> void:
	var bit := {}
	for i in range(res.cast.size()):
		bit[res.cast[i]] = 1 << i
	var order: Array = []
	for i in range(ctx.n):
		if ctx.active[i] == 1:
			order.append(i)
	order.sort_custom(func(a, b): return ctx.depth[a] < ctx.depth[b])
	var masks := {}                          # node id -> {mask: true}
	masks[ctx.start_id] = {int(bit.get(res.node_biome[ctx.start_id], 0)): true}
	for u in order:
		if not masks.has(u):
			continue
		for v in ctx.adj[u]:
			if ctx.active[v] == 0:
				continue
			var vb: int = bit.get(res.node_biome[v], 0)
			if not masks.has(v):
				masks[v] = {}
			for m in masks[u]:
				masks[v][m | vb] = true
	var minb := 9999
	for m in masks.get(ctx.end_id, {}):
		minb = mini(minb, _popcount(m))
	var reached: bool = masks.has(ctx.end_id)
	_check(reached and minb >= res.n_guaranteed,
		"every path sees >= %d distinct required biomes (worst path: %s)" % [
		res.n_guaranteed, str(minb) if reached else "end unreachable"])


## Active non-pole node ids at depth d.
func _rung_nodes(ctx, d: int) -> Array:
	var ids: Array = []
	for i in range(ctx.n):
		if ctx.active[i] == 1 and ctx.depth[i] == d and i != ctx.start_id and i != ctx.end_id:
			ids.append(i)
	return ids


func _active_count(ctx) -> int:
	var c := 0
	for i in range(ctx.n):
		if ctx.active[i] == 1:
			c += 1
	return c


## "Forest, Desert" style list for a set of biome indices.
func _names(bset: WorldBiomeSet, idxs) -> String:
	var parts: Array = []
	for b in idxs:
		parts.append(String(bset.biomes[b].name) if b >= 0 and b < bset.biomes.size() else str(b))
	return "[" + ", ".join(parts) + "]"


func _popcount(m: int) -> int:
	var c := 0
	while m != 0:
		c += m & 1
		m >>= 1
	return c
