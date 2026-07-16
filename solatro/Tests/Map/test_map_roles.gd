extends TestSuite
# res://Tests/Map/test_map_roles.gd
# ==============================================================================
# MAP NODE ROLES — deterministic seed-derived assignment over a synthetic graph.
# Builds WorldGraphOverlay.populate() input by hand (no world generation needed),
# so roles/goals are testable without the GPU pipeline.
#
# CATEGORY MAP: all BEHAVIOR — where bosses/rest stops/boosters land, the booster
# pacing guarantee, per-lap scaling, and same-seed determinism are map design rules.
# ==============================================================================

func suite_name() -> String:
	return "MAP ROLES"

func _ready() -> void:
	TestLog.line("============ MAP NODE ROLES TEST PASS ============")
	behavior_section("SEED-DERIVED NODE ROLES & GOALS")
	var real_run: RunState = RunManager.run
	test_anchor_roles_and_goals()
	test_booster_window_guarantee()
	test_determinism()
	test_lap_reversal_and_scaling()
	RunManager.run = real_run
	finish()

## A straight-line graph: one node per depth 0..max_depth, edge i -> i+1.
func _line_export(max_depth: int) -> Dictionary:
	var nodes: Array = []
	for i in max_depth + 1:
		var outs: Array = []
		if i < max_depth:
			outs.append({"to": i + 1, "ferry": false,
					"points": PackedVector2Array([Vector2(i * 10, 0), Vector2(i * 10 + 10, 0)])})
		nodes.append({"id": i, "pos": Vector2(i * 10, 0), "depth": i,
				"landmass": 0, "height": 0.5, "biome": -1, "out": outs})
	return {"start": 0, "end": max_depth, "max_depth": max_depth, "biomes": [], "nodes": nodes}

func _populated_overlay(export: Dictionary) -> WorldGraphOverlay:
	var overlay := WorldGraphOverlay.new()
	add_child(overlay)
	overlay.populate(export, Vector2(200, 200))
	return overlay

func _run_with(lap: int, seed_val: int = 12345) -> RunState:
	var run := RunState.new()
	run.world_seed = seed_val
	run.lap = lap
	RunManager.run = run
	return run

func test_anchor_roles_and_goals() -> void:
	var run := _run_with(0)
	var overlay := _populated_overlay(_line_export(4))
	MapNodeRoles.assign(overlay, run.world_seed, run)
	var start := overlay.start_node()
	var end := overlay.end_node()
	check((start.meta[MapNodeRoles.ROLE_KEY] == MapNodeRoles.ROLE_ANCHOR 
			and end.meta[MapNodeRoles.ROLE_KEY] == MapNodeRoles.ROLE_ANCHOR) as bool,
			"start and end are anchors")
	check((start.meta[MapNodeRoles.GOAL_KEY] as int) == 0, "lap-origin anchor is a free rest stop")
	check((end.meta[MapNodeRoles.GOAL_KEY] as int) > 0, "lap-target anchor is the boss show")
	for n: WorldGraphNode in overlay.nodes():
		var role :String= (n.meta[MapNodeRoles.ROLE_KEY])
		if role == MapNodeRoles.ROLE_GAME:
			check((n.meta[MapNodeRoles.GOAL_KEY] as int) >= RunManagerClass.BASE_GOAL,
					"game node %d carries a goal" % n.id)
		elif role == MapNodeRoles.ROLE_BOOSTER:
			check(n.meta[MapNodeRoles.BOOSTER_KEY] is BoosterTemplate,
					"booster node %d carries a pack" % n.id)
	overlay.free()

func test_booster_window_guarantee() -> void:
	var run := _run_with(0)
	var max_depth := 10
	var overlay := _populated_overlay(_line_export(max_depth))
	MapNodeRoles.assign(overlay, run.world_seed, run)
	# Reconstruct which mid-ranks became booster ranks.
	var booster_ranks := {}
	for n: WorldGraphNode in overlay.nodes():
		if (n.meta[MapNodeRoles.ROLE_KEY]) == MapNodeRoles.ROLE_BOOSTER:
			booster_ranks[n.depth] = true
	var rank := 1
	while rank <= max_depth - 1:
		var window_end := mini(rank + MapNodeRoles.BOOSTER_RANK_WINDOW - 1, max_depth - 1)
		var in_window := 0
		for r in range(rank, window_end + 1):
			if booster_ranks.has(r):
				in_window += 1
		check(in_window == 1, "exactly one booster rank in window %d..%d" % [rank, window_end])
		rank = window_end + 1
	overlay.free()

func test_determinism() -> void:
	var run := _run_with(0)
	var a := _populated_overlay(_line_export(9))
	var b := _populated_overlay(_line_export(9))
	MapNodeRoles.assign(a, run.world_seed, run)
	MapNodeRoles.assign(b, run.world_seed, run)
	var same := true
	for n: WorldGraphNode in a.nodes():
		if (n.meta[MapNodeRoles.ROLE_KEY]) != ((b.node(n.id) as WorldGraphNode).meta[MapNodeRoles.ROLE_KEY]):
			same = false
	check(same, "same seed -> identical roles (safe to re-derive after save/load)")
	a.free()
	b.free()

func test_lap_reversal_and_scaling() -> void:
	var run := _run_with(0)
	var overlay := _populated_overlay(_line_export(4))
	MapNodeRoles.assign(overlay, run.world_seed, run)
	var lap0_goal :int= ((overlay.node(2) as WorldGraphNode).meta.get(MapNodeRoles.GOAL_KEY, 0))
	run.lap = 1
	MapNodeRoles.assign(overlay, run.world_seed, run)
	check((overlay.start_node().meta[MapNodeRoles.GOAL_KEY] as int) > 0,
			"on a reversed lap the START node becomes the boss")
	check((overlay.end_node().meta[MapNodeRoles.GOAL_KEY] as int) == 0,
			"on a reversed lap the END node becomes the rest stop")
	var lap1_goal :int= ((overlay.node(2) as WorldGraphNode).meta.get(MapNodeRoles.GOAL_KEY, 0))
	if lap1_goal > 0 and lap0_goal > 0:
		check(lap1_goal > lap0_goal, "goals scale up per lap", "%d -> %d" % [lap0_goal, lap1_goal])
	overlay.free()
