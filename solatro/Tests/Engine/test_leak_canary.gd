extends TestSuite
# res://Tests/Engine/test_leak_canary.gd
# ==============================================================================
# MEMORY-LEAK CANARY (owner-approved 2026-07-17, AUDIT_PROPOSALS_HANDOFF.md
# NEXT STEPS 3): CardData<->modifier backrefs are RefCounted CYCLES that Godot
# never collects — any card built and dropped without unlink_card_backrefs leaks
# until exit. This suite pins the containment discipline: build + tear down a
# full headless Game N times and assert Performance.OBJECT_COUNT returns to
# baseline. If a future card/modifier slot (or teardown path) breaks the cycle
# discipline, the growth check fails here instead of silently inflating the
# ~18k residual exit-leak figure.
#
# ⚠️ Runs LAST and ALONE: OBJECT_COUNT is engine-global, so any concurrent suite
# would make the numbers meaningless. See the SUITE ORDERING chain in
# test_base.gd — every earlier waiter excludes "LEAK CANARY".
# ==============================================================================

# CATEGORY MAP: all IMPLEMENTATION — object counts pin HOW memory behaves, not a
# player-visible rule.
#
# SECTION 2 (owner-endorsed 2026-07-17, PRODUCTION_LEAK_CANARY_HANDOFF.md): the
# PRODUCTION SESSION CANARY simulates a real play session end-to-end per cycle —
# DeckPicker/DeckViewer open+close, run start, map traversal + hover panel + booster
# pack, a real show WITH a GameView (Nexts, grab/place, discard, Submit with real
# scoring/props, undo across the Submit), quit-mid-show -> resume, the win path
# (exit_show -> return_to_map) AND the loss path, then clear_save — and asserts
# OBJECT_COUNT returns to a post-warm-up baseline. Test-only leaks are out of scope
# (owner ruling); this section proves the PRODUCTION drop sites unlink their card
# cycles (Game.undo, return_to_map, exit_show loss, RunManager.clear_save,
# DeckPicker._exit_tree, MapHoverPanel previews).

func suite_name() -> String:
	return "LEAK CANARY"

const CYCLES := 10
## Session cycles are a whole double-show each — keep the count small.
const SESSION_CYCLES := 3
const WATCHDOG_SECS := 10.0

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const HOVER_PANEL_SCENE := preload("res://UI/map_hover_panel.tscn")

const REAL_SETTINGS_PATH := "user://settings.tres"
const REAL_SETTINGS_BAK := "user://settings.tres.testbak3"

func _ready() -> void:
	await await_siblings_except([])
	TestLog.line("============ LEAK CANARY TEST PASS ============")
	implementation_section("REFCOUNT-CYCLE CANARY")

	# 0. Prove the canary CAN catch the known pattern: build a fixture and drop it
	# WITHOUT unlinking. The cycle keeps every CardData+modifier alive, so the
	# global object count must NOT return to its prior level. (This deliberately
	# leaks one small fixture for the rest of the process — done before the
	# baseline snapshot so it can't pollute the growth check below.)
	await _settle()
	var before_leak := _object_count()
	var leaked := _make_game()
	CardEnvironment.CURRENT = null
	leaked.free()  # frees the Game NODE; state's card cycles survive — that's the leak
	leaked = null
	await _settle()
	check_impl(_object_count() > before_leak,
			"canary detects a deliberate drop-without-unlink leak",
			"before %d, after %d" % [before_leak, _object_count()])

	# 1. Warm-up cycle: first build touches lazy one-time allocations (deck
	# caches, static registries) that must not count against the loop.
	_clean_cycle()
	await _settle()
	var baseline := _object_count()

	# 2. N clean build/teardown cycles must return to the warm baseline.
	for i in range(CYCLES):
		_clean_cycle()
	await _settle()
	var after := _object_count()
	check_impl(after <= baseline,
			"OBJECT_COUNT returns to baseline after %d clean Game build/free cycles" % CYCLES,
			"baseline %d, after %d (growth %d)" % [baseline, after, after - baseline])
	if after > baseline:
		# Orphan NODES only (RefCounted cycles won't show here, but stray nodes will).
		print_orphan_nodes()

	implementation_section("PRODUCTION SESSION CANARY")
	# Isolation: the cycles write run.tres + settings.tres and swap the run singletons —
	# park the real ones and restore after (same discipline as VISUAL LAYERS / E2E).
	backup_real_save()
	_backup_settings()
	var real_run : RunState = RunManager.run
	var real_save_info : RunState = Main.save_info
	var prev_delay : float = SettingsManager.settings.base_delay
	SettingsManager.settings.base_delay = TestLog.speed_base_delay

	# Warm-up session: first cycle touches lazy one-time allocations (scene caches, shader
	# state, translation table, static registries) that must not count against the loop.
	await _session_cycle()
	await _drain()
	var session_baseline := _object_count()

	for i : int in range(SESSION_CYCLES):
		await _session_cycle()
	await _drain()
	var session_after := _object_count()
	check_impl(session_after <= session_baseline,
			"OBJECT_COUNT returns to baseline after %d full simulated play sessions" % SESSION_CYCLES,
			"baseline %d, after %d (growth %d)"
			% [session_baseline, session_after, session_after - session_baseline])
	if session_after > session_baseline:
		print_orphan_nodes()

	SettingsManager.settings.base_delay = prev_delay
	_restore_settings()
	restore_real_save()
	RunManager.run = real_run
	Main.save_info = real_save_info
	finish()

func _object_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))

## Two idle frames so queued deletions/refcount releases settle before counting.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

## One full lifecycle with the documented teardown discipline: unlink every
## card's modifier backrefs (breaking the RefCounted cycles), then free the Game.
func _clean_cycle() -> void:
	var g := _make_game()
	g.state.unlink_modifier_backrefs()
	CardEnvironment.CURRENT = null
	g.free()

# ==============================================================================
# PRODUCTION SESSION CANARY (section 2 — see the header): one full simulated play
# session per cycle, through the real production objects and drop sites.
# ==============================================================================

## Bounded post-cycle drain before a count: every action above was awaited to completion,
## so this only catches the last self-freeing popup/tween queue_free tails; the settle
## frames then flush queued deletions. Identical before the baseline and the final count,
## so any steady-state floor cancels out.
func _drain() -> void:
	await get_tree().create_timer(0.25).timeout
	await _settle()

func _session_cycle() -> void:
	# --- 1. Menus: DeckPicker open (builds every starter deck list), inspect one in a
	# DeckViewer, close it, then Pick. No deck_picked listener on purpose: the run below
	# starts from the FROZEN TestDecks so per-cycle allocations stay replay-stable, while
	# the picker still exercises its full build + drop path (incl. the rules list).
	var picker := DeckPicker.add_to_scene(self)
	await _settle()
	var first_deck : Array[CardData] = picker._deck.get_deck_list()[0]["cards"]
	var deck_viewer := DeckViewer.show_deck(picker, first_deck)
	await _settle()
	deck_viewer._close()
	await _settle()
	picker._on_pick(first_deck)
	await _settle()

	# --- 2. Run start (production path: new_run deep-duplicates; the sources drop here).
	var cards := TestDecks.seeded_deck()
	var rules := TestDecks.standard_rules()
	var run := RunManager.new_run(cards, rules)
	unlink_cards(cards)
	unlink_cards(rules)
	Main.save_info = run

	# --- 3. Map: enter (synthetic line graph, no world generation — the MAP TRAVERSAL rig
	# pattern), traverse two nodes, hover-panel a booster node, open + confirm its pack.
	var controller := _build_map_rig(run)
	var overlay : WorldGraphOverlay = controller.map.overlay()
	await controller.move_to(overlay.node(1))
	await controller.move_to(overlay.node(2))
	var booster_node : WorldGraphNode = null
	for n : WorldGraphNode in overlay.nodes():
		if n.meta.get(MapNodeRoles.ROLE_KEY, "") as String == MapNodeRoles.ROLE_BOOSTER:
			booster_node = n
			break
	check_impl(booster_node != null, "the synthetic map assigns at least one booster node")
	if booster_node:
		var panel : MapHoverPanel = HOVER_PANEL_SCENE.instantiate()
		add_child(panel)
		await panel.show_for_node(booster_node, run, controller.lap_target(), Vector2(100, 100))
		await _settle()
		panel.hide_panel()
		panel.queue_free()
		await _settle()
		# Booster pack: take-all ChoiceViewer; confirmed cards join the run deck (mirrors
		# Map._open_booster / _on_booster_confirmed).
		var booster : BoosterTemplate = booster_node.meta[MapNodeRoles.BOOSTER_KEY]
		var viewer : ChoiceViewer = await booster.on_map_picked(self)
		viewer.confirmed.connect(func(taken: Array[CardData]) -> void:
			for card : CardData in taken:
				Main.save_info.card_datas.append(card)
			RunManager.mark_deck_dirty()
			RunManager.save_run())
		await _settle()
		viewer._on_confirm_pressed()
		await _settle()
	controller.queue_free()
	await _settle()

	# --- 4. A real show WITH a GameView: Nexts, grab/place, discard, a Submit with real
	# scoring (props spawn + finish inside the awaited resolution), UNDO across the Submit
	# (proves the quiescent Game.undo() unlink), redo, quit-mid-show -> resume, win.
	run.pending_goal = 1
	run.pending_node_id = 2
	seed(424242)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await _settle()
	var g := view.game
	await g.next()
	await g.next()
	# grab/place through the real command seam (mirrors GameView._on_data_selected)
	var src := _topmost_lower(g, 0)
	var dst := _topmost_lower(g, 1)
	if src and dst and src != dst:
		var stack : Array[CardData] = await g.try_grab(src)
		if stack:
			view.play_area.grab_cards(stack)
			await g.try_place(stack, dst)
			view.play_area.ungrab_cards()
	# draw happened inside the Nexts; discard one board card through the real path
	var to_discard := _topmost_lower(g, 0)
	if to_discard:
		await g.discard_data(to_discard)
	await g.submit()
	g.undo()
	await _settle()
	await g.submit()

	# Quit-mid-show -> resume. The unlinks below are the app-exit stand-in (a real quit
	# ends the process, where the leak is moot) — same discipline as E2E's quit step.
	RunManager._shutdown_saver()
	RunManager.save_run()
	var doomed_state : GameData = g.state
	view.queue_free()
	await get_tree().process_frame
	doomed_state.unlink_modifier_backrefs()
	unlink_cards(run.card_datas)
	unlink_cards(run.rule_datas)
	CardEnvironment.CURRENT = null
	var loaded := RunManager.load_run()
	Main.save_info = loaded
	var view2 : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view2)
	await _settle()
	var g2 := view2.game
	var waited := 0.0
	while g2.processing and waited < WATCHDOG_SECS:  # resume holds the lock until visuals sync
		await get_tree().process_frame
		waited += get_process_delta_time()
	check_impl(not g2.processing, "the resumed show hands the board back to the player")

	var won : Array[bool] = []
	g2.show_resolved.connect(func(w: bool, _score: int, _goal: int) -> void: won.append(w))
	while g2.submits_used < Game.MAX_SUBMITS:
		await g2.submit()
	check_impl(won.size() == 1 and won[0], "the seeded show resolves as a win", str(won))
	g2.exit_show()   # win path: return_to_map banks the deck + unlinks rules/headers
	await _settle()
	view2.queue_free()
	await _settle()
	CardEnvironment.CURRENT = null

	# --- 5. The loss path: an unreachable goal, three empty submits, exit_show ends the
	# run (the loss branch unlinks the whole doomed board).
	loaded.pending_goal = 1000000000
	loaded.pending_node_id = 1
	seed(31337)
	var view3 : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view3)
	await _settle()
	var g3 := view3.game
	await g3.submit()
	await g3.submit()
	await g3.submit()
	g3.exit_show()
	await _settle()
	view3.queue_free()
	await _settle()
	CardEnvironment.CURRENT = null

	# --- 6. Run over: drop the save + run doc (clear_save unlinks it in production).
	RunManager._shutdown_saver()
	RunManager.clear_save()
	Main.save_info = RunState.new()

## The topmost card of the first non-empty lower-zone column at or after `from_col`.
func _topmost_lower(g: Game, from_col: int) -> CardData:
	for i : int in range(from_col, g.state.lower_zone.size()):
		var col : ArrayCardData = g.state.lower_zone[i]
		if col.datas.size() > 0:
			return col.datas[-1]
	return null

## MAP TRAVERSAL's rig, production-shaped: WorldMapController + camera/token (unique-named
## for the @onready %lookups), a stub WorldMap2D that never generates, a synthetic line
## graph populated by hand, and roles assigned via the controller's own _on_graph_populated
## (which also parks the token on the lap origin). Expect one harmless "baked composite not
## found" warning from the stub map.
func _build_map_rig(run: RunState) -> WorldMapController:
	var controller := WorldMapController.new()
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	controller.add_child(cam)
	cam.owner = controller
	cam.unique_name_in_owner = true
	var token := MapPlayerToken.new()
	token.name = "Token"
	controller.add_child(token)
	token.owner = controller
	token.unique_name_in_owner = true
	add_child(controller)
	var map := WorldMap2D.new()
	map.generate_on_ready = false
	map.bake_directory = "user://__leak_canary_no_bake__"
	controller.add_child(map)
	controller.map = map
	controller.run = run
	map.overlay().populate(_line_export(4), Vector2(50, 10))
	controller._on_graph_populated()
	return controller

## A straight-line graph, one node per depth 0..max_depth (MAP ROLES' shape — its booster
## window guarantee puts at least one booster on the mid ranks). Tiny distances keep the
## token travel tweens fast.
func _line_export(max_depth: int) -> Dictionary:
	var nodes : Array = []
	for i : int in max_depth + 1:
		var outs : Array = []
		if i < max_depth:
			outs.append({"to": i + 1, "ferry": false,
					"points": PackedVector2Array([Vector2(i * 10, 0), Vector2(i * 10 + 10, 0)])})
		nodes.append({"id": i, "pos": Vector2(i * 10, 0), "depth": i,
				"landmass": 0, "height": 0.5, "biome": -1, "out": outs})
	return {"start": 0, "end": max_depth, "max_depth": max_depth, "biomes": [], "nodes": nodes}

# ==============================================================================
# SETTINGS ISOLATION (SettingsManager writes settings.tres on every change)
# ==============================================================================
func _backup_settings() -> void:
	if FileAccess.file_exists(REAL_SETTINGS_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_PATH),
				ProjectSettings.globalize_path(REAL_SETTINGS_BAK))

func _restore_settings() -> void:
	if not FileAccess.file_exists(REAL_SETTINGS_BAK):
		return
	if FileAccess.file_exists(REAL_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_BAK),
			ProjectSettings.globalize_path(REAL_SETTINGS_PATH))

func _rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.active = true
	return c

## Same minimal-but-real headless fixture as test_game_headless.make_game():
## rules deck with the classic skills + two zones of typed 2-card columns —
## every modifier slot the unlink helpers cover is exercised.
func _make_game() -> Game:
	var g := Game.new()
	var s := GameData.new()
	s.rules_deck = [
		_rules_card(SkillGrabberOgLower.new()),
		_rules_card(SkillPlacerOgLower.new()),
		_rules_card(SkillScorerCascadeLower.new()),
		_rules_card(SkillEvalPokerBest.new()),
	] as Array[CardData]
	for zone_x in 2:
		var types: Array[CardData] = []
		var cols: Array[ArrayCardData] = []
		for c in 2:
			var h := TestFactories.m_card(1, TestFactories.uc()); h.stage = CardData.Stage.ZONE
			types.append(h)
			var card_lo := TestFactories.m_card(3, TestFactories.uc())
			var card_hi := TestFactories.m_card(4, TestFactories.uc())
			card_lo.stage = CardData.Stage.PLAY
			card_hi.stage = CardData.Stage.PLAY
			cols.append(TestFactories.col([card_lo, card_hi] as Array[CardData]))
		if zone_x == 0:
			s.upper_zone_type = types
			s.upper_zone = cols
		else:
			s.lower_zone_type = types
			s.lower_zone = cols
	g.state = s
	CardEnvironment.CURRENT = g
	return g
