class_name MapNodeRoles
extends RefCounted

## Deterministic node-role assignment for the world map graph. Roles are a pure function
## of (world_seed, graph, lap) written into WorldGraphNode.meta — they are NEVER saved
## (graph.json does not round-trip meta), so this must re-run on every graph_populated
## and on every lap change (goals rescale with the lap).

const ROLE_KEY := "role"        ## "anchor" | "game" | "booster"
const GOAL_KEY := "goal"        ## int fame requirement (game + lap-target anchor)
const BOOSTER_KEY := "booster"  ## BoosterTemplate instance on booster nodes

const ROLE_ANCHOR := "anchor"
const ROLE_GAME := "game"
const ROLE_BOOSTER := "booster"

## Every path crosses every rank of the layered DAG, so making whole ranks boosters
## guarantees one booster per window of this many steps on ANY path (≈33% of mid nodes).
const BOOSTER_RANK_WINDOW := 3

## Write role/goal/booster meta onto every node of the populated overlay. Goals come from
## a per-progress ladder (§15b): boosters are WHOLE ranks (_booster_ranks), so every path
## crosses the same booster set and boosters_on_path reduces exactly to "booster ranks
## strictly before this node's progress" — the max-booster-path rule on convergent branches
## is trivially satisfied. (If per-node boosters ever replace whole ranks, generalize
## _boosters_before to a max-count DAG walk over overlay edges.)
static func assign(overlay: WorldGraphOverlay, world_seed: int, run: RunState) -> void:
	var max_depth :int= overlay.graph_data.get("max_depth", 0)
	var booster_ranks := _booster_ranks(world_seed, max_depth)
	var ladder := _goal_ladder(max_depth, booster_ranks, run)
	for n: WorldGraphNode in overlay.nodes():
		if n.is_start or n.is_end:
			n.meta[ROLE_KEY] = ROLE_ANCHOR
			# Only the lap TARGET anchor is a boss show; the origin anchor is a rest stop.
			var is_target := n.is_start if run.is_reversed() else n.is_end
			# Boss sees every booster of the lap; never below the last game goal.
			var boss_goal := maxi(RunManager.goal_for(booster_ranks.size(), run.lap, true),
					ladder[max_depth])
			n.meta[GOAL_KEY] = boss_goal if is_target else 0
			n.meta.erase(BOOSTER_KEY)
		elif booster_ranks.has(n.depth):
			n.meta[ROLE_KEY] = ROLE_BOOSTER
			n.meta[BOOSTER_KEY] = TypeBoosterBasic.new()
			n.meta.erase(GOAL_KEY)
		else:
			n.meta[ROLE_KEY] = ROLE_GAME
			n.meta[GOAL_KEY] = ladder[_progress(n, max_depth, run)]
			n.meta.erase(BOOSTER_KEY)

## Steps from the lap origin: forward lap = depth, reversed lap = max_depth - depth.
static func _progress(n: WorldGraphNode, max_depth: int, run: RunState) -> int:
	return (max_depth - n.depth) if run.is_reversed() else n.depth

## §15b ladder: goal per progress step, monotone-clamped so the ladder never descends.
static func _goal_ladder(max_depth: int, booster_ranks: Dictionary, run: RunState) -> Array[int]:
	var ladder : Array[int] = []
	var running := 0
	for p : int in range(max_depth + 1):
		var b := _boosters_before(p, max_depth, booster_ranks, run)
		running = maxi(running, RunManager.goal_for(b, run.lap, false))
		ladder.append(running)
	return ladder

## Booster ranks crossed strictly before reaching progress p, in lap direction.
static func _boosters_before(p: int, max_depth: int, booster_ranks: Dictionary, run: RunState) -> int:
	var count := 0
	for rank : int in booster_ranks.keys():
		var rank_progress := (max_depth - rank) if run.is_reversed() else rank
		if rank_progress < p:
			count += 1
	return count

## Seeded pick of one booster rank per window of BOOSTER_RANK_WINDOW mid-ranks
## (1 .. max_depth-1). Dictionary used as a set: rank -> true.
static func _booster_ranks(world_seed: int, max_depth: int) -> Dictionary:
	var ranks : Dictionary[int, bool] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "roles"])
	var rank := 1
	while rank <= max_depth - 1:
		var window_end := mini(rank + BOOSTER_RANK_WINDOW - 1, max_depth - 1)
		ranks[rng.randi_range(rank, window_end)] = true
		rank = window_end + 1
	return ranks
