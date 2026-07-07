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

## Write role/goal/booster meta onto every node of the populated overlay.
static func assign(overlay: WorldGraphOverlay, world_seed: int, run: RunState) -> void:
	var max_depth :int= overlay.graph_data.get("max_depth", 0)
	var booster_ranks := _booster_ranks(world_seed, max_depth)
	for n: WorldGraphNode in overlay.nodes():
		if n.is_start or n.is_end:
			n.meta[ROLE_KEY] = ROLE_ANCHOR
			# Only the lap TARGET anchor is a boss show; the origin anchor is a rest stop.
			var is_target := n.is_start if run.is_reversed() else n.is_end
			n.meta[GOAL_KEY] = RunManager.goal_for(_progress(n, max_depth, run), run.lap, true) if is_target else 0
			n.meta.erase(BOOSTER_KEY)
		elif booster_ranks.has(n.depth):
			n.meta[ROLE_KEY] = ROLE_BOOSTER
			n.meta[BOOSTER_KEY] = TypeBoosterBasic.new()
			n.meta.erase(GOAL_KEY)
		else:
			n.meta[ROLE_KEY] = ROLE_GAME
			n.meta[GOAL_KEY] = RunManager.goal_for(_progress(n, max_depth, run), run.lap, false)
			n.meta.erase(BOOSTER_KEY)

## Steps from the lap origin: forward lap = depth, reversed lap = max_depth - depth.
static func _progress(n: WorldGraphNode, max_depth: int, run: RunState) -> int:
	return (max_depth - n.depth) if run.is_reversed() else n.depth

## Seeded pick of one booster rank per window of BOOSTER_RANK_WINDOW mid-ranks
## (1 .. max_depth-1). Dictionary used as a set: rank -> true.
static func _booster_ranks(world_seed: int, max_depth: int) -> Dictionary:
	var ranks := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "roles"])
	var rank := 1
	while rank <= max_depth - 1:
		var window_end := mini(rank + BOOSTER_RANK_WINDOW - 1, max_depth - 1)
		ranks[rng.randi_range(rank, window_end)] = true
		rank = window_end + 1
	return ranks
