extends TestSuite
# res://Tests/Engine/test_prop_engine.gd
# ==============================================================================
# PROP ENGINE (SUIT_PROPS_PLAN Phase 1 §1.7): the headless tick simulation —
# PropData / PropModifier / PropSpawner + Game.run_props, the 3-phase pass, dodge /
# redirect / teleport, spawner schedules + live cap, the runaway cap, determinism,
# and the add_line_score scoring seam. view == null throughout (bare Game.new(),
# CardEnvironment.CURRENT set by hand, exactly like test_game_headless).
#
# CATEGORY MAP: all BEHAVIOR — the simulation's rules (traversal order, pass protocol,
# dodge/redirect semantics, delivery under a live cap, deterministic replay) are the
# contract Phase 3 suit effects are built on. The gutter-accumulation seam is check_impl.
# ==============================================================================

func suite_name() -> String:
	return "PROP ENGINE"

func _ready() -> void:
	TestLog.line("============ PROP ENGINE TEST PASS ============")
	behavior_section("TRAVERSAL + BALLISTIC")
	await test_row_traversal()
	await test_ballistic_single_slot()
	behavior_section("3-PHASE PASS PROTOCOL")
	await test_three_phase_targeted()
	await test_dodge()
	await test_redirect()
	await test_teleport()
	behavior_section("SPAWNER SCHEDULES + LIVE CAP")
	await test_batch_vs_sequential()
	await test_max_live_cap_delivers_all()
	await test_spawner_card_removal()
	await test_concurrent_props()
	behavior_section("ROBUSTNESS + DETERMINISM")
	await test_empty_route_runaway_terminates()
	await test_determinism()
	implementation_section("SCORING SEAM")
	test_add_line_score_seam()
	finish()

# ==============================================================================
# FIXTURE — a single upper zone of `cols` one-card columns, so row z=0 spans every
# column and slot (0, col, 0) holds a card. Bare Game, no view, no rules skills
# (run_props is driven directly).
# ==============================================================================
func make_grid(cols: int) -> Game:
	var g := Game.new()
	var s := GameData.new()
	var types : Array[CardData] = []
	var columns : Array[ArrayCardData] = []
	for col in cols:
		var h := TestFactories.m_card(1, TestFactories.uc()); h.stage = CardData.Stage.ZONE
		types.append(h)
		var card := TestFactories.m_card(col + 2, TestFactories.uc())
		card.stage = CardData.Stage.PLAY
		columns.append(TestFactories.col([card] as Array[CardData]))
	s.upper_zone_type = types
	s.upper_zone = columns
	g.state = s
	g._begin_act()   # reset the runaway counter so note_processing accounts from zero
	CardEnvironment.CURRENT = g
	return g

func slot(col: int) -> Vector3i:
	return Vector3i(0, col, 0)

func card_at(g: Game, col: int) -> CardData:
	return g.state.upper_zone[col].datas[0]

## A prop travelling the given route with the given mods (default speed 1).
func make_prop(route: Array[Vector3i], mods: Array[PropModifier], tps := 1) -> PropData:
	var p := PropData.new()
	p.route = route
	p.mods = mods
	p.ticks_per_slot = tps
	return p

## One spawner emitting `count` props via `factory` (a func(emit_index) -> PropData).
func spawner(origin: Vector3i, factory: Callable, count := 1, batch := 1, interval := 1,
		max_live := 32) -> Array[PropSpawner]:
	var sp := PropSpawner.new()
	sp.origin = origin
	sp.remaining = count
	sp.batch_size = batch
	sp.interval = interval
	sp.max_live = max_live
	sp.factory = factory
	return [sp] as Array[PropSpawner]

## A spawner that emits one pre-built prop (source-removal / runaway helpers).
func spawner_of(origin: Vector3i, p: PropData) -> Array[PropSpawner]:
	var sp := PropSpawner.new()
	sp.origin = origin
	sp.remaining = 1
	sp.factory = func(_i: int) -> PropData: return p
	return [sp] as Array[PropSpawner]

func done(g: Game) -> void:
	# Teardown discipline (see test_leak_canary.gd): break the CardData<->modifier cycles.
	g.state.unlink_modifier_backrefs()
	CardEnvironment.CURRENT = null
	g.free()

# ==============================================================================
# PROBES
# ==============================================================================

## Shared, mutable event log so several probes over several cards write to one place.
class Log extends RefCounted:
	var spawns := 0
	var finishes := 0
	var live := 0
	var max_live := 0
	var passed_cols : Array[int] = []   # column of each on_pass_card, in fire order

## Prop-side probe: records spawn/pass/finish + live-count high-water. reaction_for -> JUMP.
class ProbeMod extends PropModifier:
	var log : Log
	func on_spawned(_prop: PropData, _g: Game) -> void:
		log.spawns += 1
		log.live += 1
		log.max_live = maxi(log.max_live, log.live)
	func on_pass_card(_prop: PropData, g: Game, card: CardData) -> void:
		log.passed_cols.append(g.find_data_vec3(card).y)
	func on_finish(_prop: PropData, _g: Game) -> void:
		log.finishes += 1
		log.live -= 1
	func reaction_for(_prop: PropData, _card: CardData) -> int:
		return PropData.Reaction.JUMP

## Card-side probe (a stamp): records the 3-phase pass hooks it hears.
class ProbeStamp extends CardModifierStamp:
	var log : Array[String] = []
	func get_str() -> String: return "ProbeStamp"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_prop_passing(_prop: PropData) -> void: log.append("passing")
	func on_prop_passed(_prop: PropData) -> void: log.append("passed")

## Card-side probe that dodges in phase 1.
class DodgeStamp extends CardModifierStamp:
	var saw_passed_negated := false
	func get_str() -> String: return "DodgeStamp"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_prop_passing(prop: PropData) -> void: prop.negate_pass()
	func on_prop_passed(prop: PropData) -> void: saw_passed_negated = prop.pass_negated

## Card-side probe that redirects the prop onto a fixed new route in phase 1 (once).
class RedirectStamp extends CardModifierStamp:
	var new_route : Array[Vector3i] = []
	var fired := false
	func get_str() -> String: return "RedirectStamp"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_prop_passing(prop: PropData) -> void:
		if fired: return
		fired = true
		prop.set_route(new_route)

## Prop-side mod that re-enters its own current slot forever (empty-route runaway analogue).
class RunawayMod extends PropModifier:
	func on_pass_card(prop: PropData, _g: Game, _card: CardData) -> void:
		prop.route.append(prop.at)

## Prop-side mod that teleports to (0,3,0) with an empty tail on spawn.
class TeleportOnSpawn extends PropModifier:
	func on_spawned(prop: PropData, _g: Game) -> void:
		prop.teleport(Vector3i(0, 3, 0), [] as Array[Vector3i])

# ==============================================================================
# TESTS
# ==============================================================================

func test_row_traversal() -> void:
	var g := make_grid(4)
	var log := Log.new()
	var pm := ProbeMod.new(); pm.log = log
	var route := g.row_slot_path(slot(0), true)
	var factory := func(_i: int) -> PropData:
		return make_prop(route, [pm] as Array[PropModifier])
	await g.run_props(spawner(slot(0), factory))
	check(log.passed_cols == [0, 1, 2, 3],
			"a prop enters every row slot once, in order", str(log.passed_cols))
	check(log.finishes == 1, "on_finish fires exactly once when the route is exhausted")
	done(g)

func test_ballistic_single_slot() -> void:
	var g := make_grid(3)
	var log := Log.new()
	var pm := ProbeMod.new(); pm.log = log
	var factory := func(_i: int) -> PropData:
		return make_prop([slot(2)] as Array[Vector3i], [pm] as Array[PropModifier])
	await g.run_props(spawner(slot(2), factory))
	check(log.passed_cols == [2], "a ballistic prop passes exactly its one target", str(log.passed_cols))
	check(log.finishes == 1, "and finishes once")
	done(g)

func test_three_phase_targeted() -> void:
	var g := make_grid(3)
	var ps0 := ProbeStamp.new()
	var ps2 := ProbeStamp.new()
	card_at(g, 0).with_stamp(ps0)   # passed
	card_at(g, 2).with_stamp(ps2)   # NOT on the route -> must stay silent
	var log := Log.new()
	var pm := ProbeMod.new(); pm.log = log
	var factory := func(_i: int) -> PropData:
		return make_prop([slot(0)] as Array[Vector3i], [pm] as Array[PropModifier])
	await g.run_props(spawner(slot(0), factory))
	check(ps0.log == ["passing", "passed"],
			"the passed card hears on_prop_passing then on_prop_passed, once each", str(ps0.log))
	check(log.passed_cols == [0], "the prop's own on_pass_card runs between the two phases")
	check(ps2.log.is_empty(), "a card off the route hears nothing (targeted, not broadcast)")
	done(g)

func test_dodge() -> void:
	var g := make_grid(2)
	var ds := DodgeStamp.new()
	card_at(g, 0).with_stamp(ds)
	var log := Log.new()
	var pm := ProbeMod.new(); pm.log = log
	var factory := func(_i: int) -> PropData:
		return make_prop([slot(0), slot(1)] as Array[Vector3i], [pm] as Array[PropModifier])
	await g.run_props(spawner(slot(0), factory))
	check(log.passed_cols == [1],
			"a dodged pass skips the prop's effect (phase 2); the next pass runs normally",
			str(log.passed_cols))
	check(ds.saw_passed_negated, "phase 3 still fires on a dodged pass, with pass_negated set")
	done(g)

func test_redirect() -> void:
	var g := make_grid(4)
	var rs := RedirectStamp.new()
	rs.new_route = [slot(2), slot(3)] as Array[Vector3i]   # slot0 reroutes onto 2 then 3
	card_at(g, 0).with_stamp(rs)
	var log := Log.new()
	var pm := ProbeMod.new(); pm.log = log
	var factory := func(_i: int) -> PropData:
		return make_prop([slot(0), slot(1)] as Array[Vector3i], [pm] as Array[PropModifier])
	await g.run_props(spawner(slot(0), factory))
	check(log.passed_cols == [0, 2, 3],
			"a phase-1 set_route sends the prop down the new tail (1 skipped, 2 & 3 hit)",
			str(log.passed_cols))
	done(g)

func test_teleport() -> void:
	var g := make_grid(4)
	var log := Log.new()
	var pm := ProbeMod.new(); pm.log = log
	var tp := TeleportOnSpawn.new()
	var factory := func(_i: int) -> PropData:
		return make_prop([slot(0)] as Array[Vector3i], [tp, pm] as Array[PropModifier])
	await g.run_props(spawner(slot(0), factory))
	check(log.passed_cols.is_empty(),
			"after teleport to an empty-tail slot the prop finishes without a normal pass",
			str(log.passed_cols))
	check(log.finishes == 1, "the teleported prop still finishes once")
	done(g)

func test_batch_vs_sequential() -> void:
	# batch: all emitted at tick 0. sequential: one per tick. Both deliver every prop.
	var g := make_grid(1)
	var log := Log.new()
	var factory := func(_i: int) -> PropData:
		var pm := ProbeMod.new(); pm.log = log
		return make_prop([slot(0)] as Array[Vector3i], [pm] as Array[PropModifier])
	await g.run_props(spawner(slot(0), factory, 5, 5, 1))
	check(log.spawns == 5 and log.finishes == 5, "batch spawner delivers all 5", str(log.spawns))
	var log2 := Log.new()
	var factory2 := func(_i: int) -> PropData:
		var pm := ProbeMod.new(); pm.log = log2
		return make_prop([slot(0)] as Array[Vector3i], [pm] as Array[PropModifier])
	await g.run_props(spawner(slot(0), factory2, 5, 1, 1))
	check(log2.spawns == 5 and log2.finishes == 5, "sequential spawner delivers all 5", str(log2.spawns))
	done(g)

func test_max_live_cap_delivers_all() -> void:
	var g := make_grid(1)
	var log := Log.new()
	# 6 props, cap 2 live, speed 2 so they linger and the cap actually bites.
	var factory := func(_i: int) -> PropData:
		var pm := ProbeMod.new(); pm.log = log
		return make_prop([slot(0)] as Array[Vector3i], [pm] as Array[PropModifier], 2)
	await g.run_props(spawner(slot(0), factory, 6, 6, 1, 2))
	check(log.spawns == 6 and log.finishes == 6, "all 6 props delivered under a live cap", str(log.spawns))
	check(log.max_live <= 2, "never more than max_live=2 props alive at once", str(log.max_live))
	done(g)

func test_spawner_card_removal() -> void:
	var g := make_grid(3)
	var log := Log.new()
	var pm := ProbeMod.new(); pm.log = log
	var route := g.row_slot_path(slot(0), true)
	var origin := card_at(g, 0)
	var p := make_prop(route, [pm] as Array[PropModifier])
	p.source = origin
	# discard the source card's slot BEFORE running: props keep their captured route
	g.state.upper_zone[0].datas.clear()   # slot 0 now empty; source is off-board
	g.state.revision += 1
	await g.run_props(spawner_of(slot(0), p))
	check(log.passed_cols == [1, 2],
			"props keep traversing after their source card leaves (slot 0 now empty)",
			str(log.passed_cols))
	check(log.finishes == 1, "and still finish")
	done(g)

func test_concurrent_props() -> void:
	var g := make_grid(2)
	var log := Log.new()
	var factory := func(_i: int) -> PropData:
		var pm := ProbeMod.new(); pm.log = log
		return make_prop([slot(1)] as Array[Vector3i], [pm] as Array[PropModifier])
	await g.run_props(spawner(slot(1), factory, 2, 2, 1))
	check(log.passed_cols == [1, 1], "both concurrent props over one card fire", str(log.passed_cols))
	done(g)

func test_empty_route_runaway_terminates() -> void:
	var g := make_grid(1)
	var rm := RunawayMod.new()
	var p := make_prop([slot(0)] as Array[Vector3i], [rm] as Array[PropModifier])
	await g.run_props(spawner_of(slot(0), p))
	check(true, "run_props returns on a self-perpetuating route (did not hang)")
	done(g)

func test_determinism() -> void:
	var logs : Array[Array] = []
	for run in 2:
		var g := make_grid(4)
		var log := Log.new()
		var pm := ProbeMod.new(); pm.log = log
		var route := g.row_slot_path(slot(0), true)
		var factory := func(_i: int) -> PropData:
			return make_prop(route, [pm] as Array[PropModifier])
		await g.run_props(spawner(slot(0), factory))
		logs.append(log.passed_cols)
		done(g)
	check(logs[0] == logs[1], "identical setups produce identical event logs", str(logs))

func test_add_line_score_seam() -> void:
	var g := make_grid(1)
	check(g.state.row_total == 0, "precondition: row_total 0")
	g.add_line_score(true, g.state.scores_row_upper, 0, 5)
	check(g.state.row_total == 5, "add_line_score banks into row_total headless")
	check(g.state.scores_row_upper.size() >= 1 and g.state.scores_row_upper[0] != null,
			"add_line_score accumulates the gutter BigNumber headless")
	g.add_line_score(false, g.state.scores_col, 0, 3)
	check(g.state.col_total == 3, "add_line_score banks into col_total for columns")
	check(g.row_gutter(Vector3i(0, 0, 0)) == g.state.scores_row_upper
			and g.row_gutter(Vector3i(1, 0, 0)) == g.state.scores_row_lower,
			"row_gutter maps x=0 -> upper, x=1 -> lower")
	done(g)
