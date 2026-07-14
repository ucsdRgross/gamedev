extends SolatroTest
# res://Tests/UI/test_ui_props.gd
# ==============================================================================
# UI PROPS (SUIT_PROPS_PLAN Phases 4-5): the VIEW side of the prop pipeline —
# PlayArea slot geometry, PropLayer's begin_prop_tick/tick_done contract (spawn,
# travel, teleport blink, despawn, card reactions), the StatusLayer + tooltip
# surfaces, the keyboard/controller focus inspector, and one full Submit through
# a real GameView (the actual game_view.begin_prop_tick seam) under a watchdog.
#
# CATEGORY MAP: mostly BEHAVIOR — what the player sees (props appear, travel,
# blink, vanish; cards jump; statuses/tooltips show; a submit never hangs).
# check_impl pins: kind -> visual class mapping, slot-center math, the
# PropData -> visual bookkeeping map.
#
# Ordering: owns CardEnvironment.CURRENT / Main.save_info / the animation-speed
# setting while it runs, so it waits for every sibling suite EXCEPT the E2E suite
# (which itself waits for ALL siblings, this one included) — this suite runs
# second-to-last, E2E last. Waiting on E2E here would deadlock both.
# Safety: real run.tres AND settings.tres are moved aside and restored (settings
# writes to disk on every change, and this suite speeds up base_delay).
# ==============================================================================

const PLAY_AREA_SCENE := preload("res://UI/play_area.tscn")
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")

## Wall-clock cap for any single awaited animation/coroutine (base_delay is shrunk to
## FAST_DELAY for the whole suite, so real completions are far quicker than this).
const WATCHDOG_SECS := 10.0
const FAST_DELAY := 0.05

const REAL_SETTINGS_PATH := "user://settings.tres"
const REAL_SETTINGS_BAK := "user://settings.tres.testbak"

func suite_name() -> String:
	return "UI PROPS"

func _ready() -> void:
	if get_parent():
		for sibling in get_parent().get_children():
			var suite := sibling as SolatroTest
			if suite and suite != self and suite.suite_name() != "E2E RUN" and not suite.finished:
				await suite.suite_finished
	print("============ UI PROPS TEST PASS ============")
	_backup_settings()
	var prev_delay := SettingsManager.settings.base_delay
	SettingsManager.settings.base_delay = FAST_DELAY
	implementation_section("SLOT GEOMETRY")
	await test_slot_geometry()
	behavior_section("PROP VISUAL LIFECYCLE")
	await test_prop_visual_lifecycle()
	await test_slow_props_move_continuously()
	await test_teleport_blinks()
	behavior_section("PROP GEOMETRY ENVELOPE (per-frame raw-position sampling)")
	await test_row_prop_never_leaves_its_row()
	await test_each_kind_moves_as_expected()
	await test_ballistic_despawn_poofs_in_place()
	await test_batch_props_stagger()
	await test_reactions_drive_card_pose()
	behavior_section("STATUS + CARD TEXT SURFACES")
	await test_status_and_description_surface()
	await test_focus_inspector_all_input_modes()
	behavior_section("FULL VIEW SUBMIT (REAL GAMEVIEW SEAM)")
	await test_game_view_submit_with_props()
	await test_all_kinds_live_in_game_view()
	SettingsManager.settings.base_delay = prev_delay
	_restore_settings()
	finish()

# ==============================================================================
# SETTINGS ISOLATION — SettingsManager writes settings.tres on EVERY change, so the
# suite's speed knob must never clobber the player's file (same pattern as
# backup_real_save for run.tres).
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

# ==============================================================================
# FIXTURE — a bare Game (one upper zone of one-card columns, exactly like
# test_prop_engine.make_grid) plus a real play_area.tscn instance built from it.
# The PropLayer is driven directly here (data one tick ahead, mirroring run_props);
# the GameView scenario at the bottom exercises the real seam.
# ==============================================================================
## `empty_cols` columns get a header but NO cards — row paths still cross them (the live
## boards that exposed the empty-column geometry bugs always had empty edge columns).
func make_board_game(cols: int, empty_cols: Array[int] = []) -> Game:
	var g := Game.new()
	var s := GameData.new()
	var types : Array[CardData] = []
	var columns : Array[ArrayCardData] = []
	for col in cols:
		var h := TestFactories.m_card(1, TestFactories.uc()); h.stage = CardData.Stage.ZONE
		types.append(h)
		if col in empty_cols:
			columns.append(TestFactories.col([] as Array[CardData]))
			continue
		var card := TestFactories.m_card(col + 2, TestFactories.uc())
		card.stage = CardData.Stage.PLAY
		columns.append(TestFactories.col([card] as Array[CardData]))
	s.upper_zone_type = types
	s.upper_zone = columns
	g.state = s
	g._begin_act()   # reset compression so get_delay() is the plain base delay
	CardEnvironment.CURRENT = g
	return g

func make_play_area() -> PlayArea:
	var pa : PlayArea = PLAY_AREA_SCENE.instantiate()
	add_child(pa)
	pa.size = Vector2(1152, 648)
	return pa

## Wait until every board CardVisual is in-tree and ready, then until the slot GEOMETRY holds
## still for a few consecutive frames — split containers, score labels, and the smooth-scroll
## content settle over several frames after a build, and a moving board fakes direction
## changes in the raw-position movement tests.
func settle(pa: PlayArea) -> void:
	var waited := 0.0
	while not pa.visuals_ready() and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var last := pa.slot_center_global(slot(0))
	var stable := 0
	while stable < 3 and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var now := pa.slot_center_global(slot(0))
		stable = stable + 1 if now.is_equal_approx(last) else 0
		last = now

func slot(col: int) -> Vector3i:
	return Vector3i(0, col, 0)

func cleanup(g: Game, pa: PlayArea) -> void:
	pa.queue_free()
	CardEnvironment.CURRENT = null
	g.free()
	await get_tree().process_frame

## Live PropVisual children only (the layer also hosts the focus inspector panel).
func prop_visual_count(pl: PropLayer) -> int:
	var n := 0
	for child in pl.get_children():
		if child is PropVisual and not child.is_queued_for_deletion():
			n += 1
	return n

## Kind name from the visual's class (kind: 0 hoop 1 knife 2 ball 3 fire 4 firework).
func _kind_name_of(vis: PropVisual) -> String:
	if vis is KnifeVisual: return "knife"
	if vis is BallVisual: return "ball"
	if vis is FireVisual: return "fire"
	if vis is FireworkVisual: return "firework"
	return "hoop"

## Concurrent card-pose watcher (fire WITHOUT await): flips the flags when ANY board card is
## seen raised (JUMP reaction) or rotating (SPIN reaction) while `flag` is still false.
func _watch_card_poses(pa: PlayArea, flag: Array[bool], saw_raised: Array[bool],
		saw_spin: Array[bool]) -> void:
	var waited := 0.0
	while not flag[0] and waited < 3.0 * WATCHDOG_SECS:
		for vis : CardVisual in pa.data_card.values():
			if not is_instance_valid(vis) or not vis.offset: continue
			if vis.offset.position.y < -1.0: saw_raised[0] = true
			if absf(vis.offset.rotation) > 0.1: saw_spin[0] = true
		await get_tree().process_frame
		waited += get_process_delta_time()

## True when every board card visual is at rest: offset home, no spin left, floating restored.
## `detail` (size-1 array) receives the first offender's pose for the failure message.
func _cards_at_rest(pa: PlayArea, detail: Array[String]) -> bool:
	for vis : CardVisual in pa.data_card.values():
		if not is_instance_valid(vis) or not vis.offset: continue
		if absf(vis.offset.position.y) > 1.0 or absf(vis.offset.rotation) > 0.05 \
				or not vis.floating:
			detail[0] = "offset y %.1f rot %.2f floating %s" \
					% [vis.offset.position.y, vis.offset.rotation, vis.floating]
			return false
	return true

## Poll until every card is at rest (or the watchdog expires); returns the final state.
func _await_cards_at_rest(pa: PlayArea, detail: Array[String]) -> bool:
	var rest := _cards_at_rest(pa, detail)
	var waited := 0.0
	while not rest and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
		rest = _cards_at_rest(pa, detail)
	return rest

## Start one visual tick and await its tick_done under a watchdog — a sync bug fails
## the check instead of hanging the whole test run. Returns whether it completed.
func run_tick(pl: PropLayer, live: Array, spawned: Array, movers: Array,
		relocated: Array) -> bool:
	var sig := pl.begin_prop_tick(live, spawned, movers, relocated)
	var fired : Array[bool] = [false]
	var handler := func() -> void: fired[0] = true
	sig.connect(handler)
	var waited := 0.0
	while not fired[0] and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	sig.disconnect(handler)
	return fired[0]

## Drive a route prop through spawn -> sweep -> despawn EXACTLY like run_props' MOVE stage,
## one awaited visual tick per data tick; flips flag[0] true once the whole flight (incl. its
## final despawn tick) completed. Call WITHOUT await to run it concurrently with a sampler.
func _drive_route_flight(pl: PropLayer, p: PropData, flag: Array[bool]) -> void:
	var ok := await run_tick(pl, [p], [p], [], [])
	while ok and not p.done:
		p.countdown -= 1
		if p.countdown > 0:
			ok = await run_tick(pl, [p], [], [], [])
		elif p.route.is_empty():
			p.done = true
			ok = await run_tick(pl, [p], [], [], [])
		else:
			p.at = p.route.pop_front()
			p.countdown = p.ticks_per_slot
			ok = await run_tick(pl, [p], [], [p], [])
	flag[0] = ok

## Per-frame RAW position sampler: captures the prop visual's GLOBAL position EVERY frame from
## the moment it appears until the node frees — staging, sweep, AND the despawn exit, in ONE
## continuous loop with no per-tick gaps (a per-tick poll missed frames between ticks and let
## diagonal drift through: owner report 2026-07-12). This is the raw visual output the
## envelope/direction checks read. `poll`, when valid, runs each sampled frame with the visual.
## `origin`, when valid, is subtracted from every sample: measuring relative to a live board
## point cancels WHOLE-BOARD motion (smooth-scroll settle, relayout shifts move every global
## together) so direction counts read the prop's motion relative to the board — exactly what
## the player perceives — instead of flagging the board's own wobble as turns.
func _sample_flight(pl: PropLayer, p: PropData, samples: Array[Vector2],
		poll: Callable, origin: Callable = Callable()) -> void:
	var vis : PropVisual = null
	var waited := 0.0
	while vis == null and waited < WATCHDOG_SECS:
		vis = pl._visuals.get(p)
		if vis == null:
			await get_tree().process_frame
			waited += get_process_delta_time()
	while is_instance_valid(vis) and not vis.is_queued_for_deletion() \
			and waited < 3.0 * WATCHDOG_SECS:
		var base : Vector2 = origin.call() if origin.is_valid() else Vector2.ZERO
		samples.append(vis.global_position - base)
		if poll.is_valid(): poll.call(vis)
		await get_tree().process_frame
		waited += get_process_delta_time()

## Direction flips along one axis (0 = x, 1 = y) derived from RAW sampled positions — tests
## the visual OUTPUT, not the interpolator's internals. Sub-pixel deltas are jitter, not
## motion (deadzone). Prints every flip with its position so a failure names where it turned.
func _direction_changes(samples: Array[Vector2], axis: int, label: String) -> int:
	var flips := 0
	var prev_sign := 0
	for i in range(1, samples.size()):
		var d := samples[i][axis] - samples[i - 1][axis]
		if absf(d) < 0.5: continue
		var s := 1 if d > 0.0 else -1
		if prev_sign != 0 and s != prev_sign:
			flips += 1
			print("[%s] axis-%s direction change #%d at %s (%+d -> %+d)"
					% [label, "x" if axis == 0 else "y", flips, samples[i], prev_sign, s])
		prev_sign = s
	return flips

## Prop-side probe whose only behavior is the JUMP view hint.
class JumpHintMod extends PropModifier:
	func reaction_for(_prop: PropData, _card: CardData) -> int:
		return PropData.Reaction.JUMP

# ==============================================================================
# TESTS
# ==============================================================================

func test_slot_geometry() -> void:
	var g := make_board_game(2)
	var pa := make_play_area()
	await settle(pa)
	var control := pa.control_for_coord(slot(0))
	check_impl(control != null, "an occupied slot coord maps to a board control")
	if control:
		var center := control.global_position + control.size * 0.5
		check_impl(pa.slot_center_global(slot(0)).is_equal_approx(center),
				"slot_center_global returns the control's rect center")
	# Slots past the built rows have no control: the fallback extrapolates down the column.
	var deep_a := pa.slot_center_global(Vector3i(0, 0, 4))
	var deep_b := pa.slot_center_global(Vector3i(0, 0, 5))
	check_impl(deep_b.y > deep_a.y and is_equal_approx(deep_a.x, deep_b.x),
			"empty-slot fallback walks straight down the column",
			"%s -> %s" % [deep_a, deep_b])
	await cleanup(g, pa)
	# A COMPLETELY EMPTY column: its header is that column's LAST control, so the
	# "last control is full card height" rule inflates it — the fallback must anchor to
	# the header TOP or every row bends a full card downward at empty columns (the live
	# diagonal-knife/invisible-hoop staging bug, owner report 2026-07-13).
	g = make_board_game(3, [1] as Array[int])
	pa = make_play_area()
	await settle(pa)
	var occupied_y := pa.slot_center_global(slot(0)).y
	var empty_y := pa.slot_center_global(slot(1)).y
	check_impl(is_equal_approx(occupied_y, empty_y),
			"an empty column's row-0 slot sits ON the row line of its occupied neighbors",
			"occupied y %.1f vs empty-column y %.1f" % [occupied_y, empty_y])
	await cleanup(g, pa)

func test_prop_visual_lifecycle() -> void:
	var g := make_board_game(3)
	var pa := make_play_area()
	await settle(pa)
	var pl := pa.prop_layer
	var p := PropData.new()
	p.kind = 0
	p.route = [slot(0), slot(1), slot(2)] as Array[Vector3i]
	# tick 0: spawn — the visual pops at the route head
	var ok := await run_tick(pl, [p], [p], [], [])
	check(ok, "the spawn tick's animation completes and tick_done fires")
	check(prop_visual_count(pl) == 1, "a spawned prop gets exactly one visual",
			str(prop_visual_count(pl)))
	var is_hoop := false
	for child in pl.get_children():
		if child is HoopVisual: is_hoop = true
	check_impl(is_hoop, "kind 0 maps to the hoop visual")
	# ticks 1..3: walk the route exactly like run_props (data one step ahead of the view)
	while not p.route.is_empty():
		p.at = p.route.pop_front()
		ok = await run_tick(pl, [p], [], [p], [])
		check(ok, "a mover tick completes (slot %s)" % str(p.at))
	var vis : PropVisual = pl._visuals.get(p)
	if vis:
		var want := pl.to_local(pa.slot_center_global(p.at))
		check((vis.position - want).length() < 1.0,
				"the visual lands on its slot's center", "%s vs %s" % [vis.position, want])
	# final tick: route exhausted -> done -> the visual exits into the void and frees itself
	p.done = true
	ok = await run_tick(pl, [p], [], [], [])
	check(ok, "the despawn tick completes")
	var waited := 0.0
	while prop_visual_count(pl) > 0 and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(prop_visual_count(pl) == 0,
			"a finished prop's visual frees itself — none stranded after the run")
	check_impl(pl._visuals.is_empty(), "the PropData -> visual map is emptied (no leak)")
	await cleanup(g, pa)

## Knives/hoops run ticks_per_slot = 2: the visual must spread each slot crossing over BOTH
## ticks (arriving as the residency ends), not sprint it in one tick and freeze for the next —
## the freeze read as props "pausing and stopping" in playtests.
func test_slow_props_move_continuously() -> void:
	# Slow the tick WAY down for this test: at FAST_DELAY a single frame can overshoot the
	# whole leg (delta/span > 1), which would false-fail the mid-flight assertion.
	var fast := SettingsManager.settings.base_delay
	SettingsManager.settings.base_delay = 0.4
	var g := make_board_game(3)
	var pa := make_play_area()
	await settle(pa)
	var pl := pa.prop_layer
	var p := PropData.new()
	p.kind = 1
	p.ticks_per_slot = 2
	p.route = [slot(0), slot(1), slot(2)] as Array[Vector3i]
	var ok := await run_tick(pl, [p], [p], [], [])
	check(ok, "spawn tick completes")
	p.at = p.route.pop_front()   # enter slot 0
	ok = await run_tick(pl, [p], [], [p], [])
	check(ok, "entry tick into slot 0 completes")
	# Assert mid-flight on a FULL-length leg (slot 0 -> slot 1); the staged->entry leg can be
	# arbitrarily short, so it can't distinguish sprint from smooth.
	p.at = p.route.pop_front()   # enter slot 1
	ok = await run_tick(pl, [p], [], [p], [])
	check(ok, "a 2-ticks-per-slot mover's entry tick completes at its half-way share")
	var vis : PropVisual = pl._visuals.get(p)
	var target := pl.to_local(pa.slot_center_global(p.at))
	check(vis != null and (vis.position - target).length() > 1.0,
			"the slow prop is still mid-flight after its entry tick (no one-tick sprint)")
	# the in-between tick (no new slot) carries it the rest of the way — never frozen
	ok = await run_tick(pl, [p], [], [], [])
	check(ok, "the mid-slot tick completes")
	check(vis != null and (vis.position - target).length() < 1.0,
			"the prop arrives exactly as its slot residency ends (smooth, no pause)")
	SettingsManager.settings.base_delay = fast
	await cleanup(g, pa)

func test_teleport_blinks() -> void:
	var g := make_board_game(3)
	var pa := make_play_area()
	await settle(pa)
	var pl := pa.prop_layer
	var p := PropData.new()
	p.kind = 2
	p.route = [slot(0)] as Array[Vector3i]
	var ok := await run_tick(pl, [p], [p], [], [])
	check(ok, "spawn tick before the teleport completes")
	# a hook teleported the prop: the view must BLINK it to the destination, never lerp
	p.at = slot(2)
	p.route = [] as Array[Vector3i]
	pl.begin_prop_tick([p], [], [], [[p, slot(0), slot(2)] as Array])
	var vis : PropVisual = pl._visuals.get(p)
	var want := pl.to_local(pa.slot_center_global(slot(2)))
	check(vis != null and (vis.position - want).length() < 1.0,
			"a teleported prop's visual snaps to the destination instantly (blink, not lerp)")
	var waited := 0.0
	while pl.tick_pending() and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(not pl.tick_pending(), "the teleport tick still completes")
	await cleanup(g, pa)

func test_reactions_drive_card_pose() -> void:
	var g := make_board_game(2)
	var pa := make_play_area()
	await settle(pa)
	var pl := pa.prop_layer
	var card := g.state.upper_zone[0].datas[0]
	var vis : CardVisual = pa.data_card.get(card)
	check(vis != null, "precondition: the board card has a visual")
	var p := PropData.new()
	p.kind = 0
	p.mods = [JumpHintMod.new()] as Array[PropModifier]
	p.at = slot(0)
	p.route = [slot(1)] as Array[Vector3i]
	var ok := await run_tick(pl, [p], [], [p], [])
	check(ok, "the reaction tick completes")
	# anim_jump tweens the card's offset up; poll for the raised pose
	var raised := false
	var waited := 0.0
	while not raised and waited < WATCHDOG_SECS:
		if vis and vis.offset and vis.offset.position.y < -1.0: raised = true
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(raised, "a JUMP-hinting prop over a card makes the card jump")
	# let the first jump's scale pulse finish (raised pose holds, scale settles back to 1)
	var settled := false
	waited = 0.0
	while not settled and waited < WATCHDOG_SECS:
		if vis and vis.offset and vis.offset.scale.x < 1.01 and vis.offset.position.y < -1.0:
			settled = true
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(settled, "the jump pose holds (raised, pulse finished) while the prop sits on the card")
	# a SECOND prop arriving on the already-held card must RE-trigger the pose (scale pulse
	# per arrival) — a train reacts once per prop, not once per occupancy streak (owner
	# report 2026-07-13: cards "don't reliably spin" as knife trains crossed them).
	var p2 := PropData.new()
	p2.kind = 0
	p2.mods = [JumpHintMod.new()] as Array[PropModifier]
	p2.at = slot(0)
	p2.route = [slot(1)] as Array[Vector3i]
	ok = await run_tick(pl, [p, p2], [], [p2], [])
	check(ok, "the second-arrival tick completes")
	var pulsed := false
	waited = 0.0
	while not pulsed and waited < WATCHDOG_SECS:
		if vis and vis.offset and vis.offset.scale.x > 1.05: pulsed = true
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(pulsed, "a second prop arriving on a held card re-triggers its reaction (per-prop pulse)")
	# both props move on -> the card returns to rest
	p.at = slot(1)
	p2.at = slot(1)
	ok = await run_tick(pl, [p, p2], [], [p, p2], [])
	check(ok, "the follow-up tick completes")
	var rested := false
	waited = 0.0
	while not rested and waited < WATCHDOG_SECS:
		if vis and vis.offset and vis.offset.position.y > -1.0: rested = true
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(rested, "the card resets to rest once no prop is over it")
	await cleanup(g, pa)

## Sample the RAW global position EVERY frame of a row prop's whole flight — staging, sweep,
## despawn tween, one continuous sampler with no per-tick gaps — and hold it to the LIVE row
## envelope. Mid-flight a focus grab resizes the layout exactly like a player hovering a card;
## a leg locked to stale pixels then walks a diagonal off its row (owner report 2026-07-12) —
## the prop must ride the shifted row instead. The sweep must also never reverse direction
## (derived from the raw samples, printed with positions).
func test_row_prop_never_leaves_its_row() -> void:
	# Slow the tick so each leg spans many sampled frames (FAST_DELAY gives ~1 frame per leg).
	var fast := SettingsManager.settings.base_delay
	SettingsManager.settings.base_delay = 0.3
	# Column 0 — the ENTRY column — is EMPTY: the exact live shape (props enter at an empty
	# edge column) whose inflated-header fallback staged knives diagonally off the board.
	var g := make_board_game(4, [0] as Array[int])
	var pa := make_play_area()
	await settle(pa)
	var pl := pa.prop_layer
	var p := PropData.new()
	p.kind = 1
	p.ticks_per_slot = 2
	p.route = g.row_slot_path(slot(0), true)
	p.countdown = p.ticks_per_slot   # what run_props' spawn stage sets for a batch's first prop
	var x_min := pa.slot_center_global(slot(0)).x
	var x_max := pa.slot_center_global(Vector3i(0, 3, 0)).x
	var pitch := (x_max - x_min) / 3.0
	var band := CardVisual.card_size_play.y * 0.5
	var stray : Array[String] = []
	var samples : Array[Vector2] = []
	var poked : Array[bool] = [false]
	var label_poked : Array[bool] = [false]
	var poll := func(vis: PropVisual) -> void:
		var gp := vis.global_position
		var row_y := pa.slot_center_global(slot(0)).y   # LIVE: the relayout pokes move the row
		if absf(gp.y - row_y) > band and stray.is_empty():
			stray.append("y strayed to %s (live row y %.0f)" % [gp, row_y])
		elif (gp.x < x_min - 2.0 * pitch or gp.x > x_max + 2.0 * pitch) and stray.is_empty():
			stray.append("x overshot to %s (span %.0f..%.0f)" % [gp, x_min, x_max])
		if not poked[0] and samples.size() >= 25:
			poked[0] = true
			var control := pa.control_for_coord(Vector3i(0, 1, 0))
			if control: control.grab_focus()   # relayout poke 1: focus resizes headers/rows
		if not label_poked[0] and samples.size() >= 45:
			label_poked[0] = true
			# Relayout poke 2 — THE real mid-run trigger: a banked line score widens its
			# BigNumberLabel and shifts the whole board (live submits do this every pass).
			g.resize_score_zone(g.state.scores_row_upper, 1)
			g.state.scores_row_upper[0].plus_equals(987654321)
			pa.update_score_controls()
	var flight_ok : Array[bool] = [false]
	_drive_route_flight(pl, p, flight_ok)   # concurrent: the sampler below owns the frames
	await _sample_flight(pl, p, samples, poll,
			func() -> Vector2: return pa.slot_center_global(slot(0)))
	check(flight_ok[0], "every tick of the row flight completes")
	check(samples.size() > 10, "the sampler captured the flight every frame",
			str(samples.size()))
	check(poked[0], "the mid-flight relayout poke fired (focus resize while travelling)")
	check(label_poked[0], "the mid-flight score-label poke fired (board shift while travelling)")
	check(stray.is_empty(),
			"a row prop holds its LIVE row for the ENTIRE flight (staging, sweep, relayout, despawn)",
			"; ".join(stray))
	check(_direction_changes(samples, 0, "knife row sweep") == 0,
			"the row sweep never reverses direction (raw positions, whole flight)")
	SettingsManager.settings.base_delay = fast
	await cleanup(g, pa)

## ONE shared movement contract, verified per kind from RAW frame-sampled positions (never the
## interpolator's internals): row kinds (hoop, knife) sweep their row straight in one direction
## and never reverse; ballistic kinds (ball, fire) fly monotonically toward their target with
## exactly one vertical turn (the arc's peak) and end AT the target. All four ride the same
## travel_curve — only arc_height differs — so a kind diverging here means someone forked the
## movement code. Direction changes print with their positions.
func test_each_kind_moves_as_expected() -> void:
	var fast := SettingsManager.settings.base_delay
	SettingsManager.settings.base_delay = 0.3   # many sampled frames per leg (see row test)
	# --- row travelers: hoop (kind 0) and knife (kind 1) share the straight sweep ---
	for kind : int in [0, 1]:
		var label : String = "hoop" if kind == 0 else "knife"
		var g := make_board_game(4)
		var pa := make_play_area()
		await settle(pa)
		var pl := pa.prop_layer
		var p := PropData.new()
		p.kind = kind
		p.ticks_per_slot = 2
		# Hoop sweeps RIGHT-TO-LEFT (entity_side_for_row sends real hoops and knives in from
		# opposite edges), knife left-to-right — both directions of the shared sweep covered.
		p.route = g.row_slot_path(slot(0), kind == 1)
		p.countdown = p.ticks_per_slot
		var band := CardVisual.card_size_play.y * 0.5
		var samples : Array[Vector2] = []
		var flight_ok : Array[bool] = [false]
		_drive_route_flight(pl, p, flight_ok)
		# samples are relative to the LIVE row anchor, so y deviation is directly |rel.y|
		await _sample_flight(pl, p, samples, Callable(),
				func() -> Vector2: return pa.slot_center_global(slot(0)))
		check(flight_ok[0], "%s flight completes" % label)
		var max_dev := 0.0
		for gp : Vector2 in samples:
			max_dev = maxf(max_dev, absf(gp.y))
		check(max_dev <= band, "%s holds its row's y for the whole flight" % label,
				"max deviation %.1f (band %.1f)" % [max_dev, band])
		check(_direction_changes(samples, 0, label) == 0,
				"%s sweeps its row in ONE direction (raw positions)" % label)
		await cleanup(g, pa)
	# --- ballistic: ball (kind 2) and fire (kind 3) share the arc ---
	for kind : int in [2, 3]:
		var label : String = "ball" if kind == 2 else "fire"
		var g := make_board_game(3)
		var pa := make_play_area()
		await settle(pa)
		var pl := pa.prop_layer
		var p := PropData.new()
		p.kind = kind
		p.source = g.state.upper_zone[0].datas[0]   # spawns at its card, arcs to the target
		p.route = [slot(2)] as Array[Vector3i]
		p.countdown = p.ticks_per_slot
		var samples : Array[Vector2] = []
		var flight_ok : Array[bool] = [false]
		_drive_route_flight(pl, p, flight_ok)
		await _sample_flight(pl, p, samples, Callable(),
				func() -> Vector2: return pa.slot_center_global(slot(0)))
		check(flight_ok[0], "%s flight completes" % label)
		check(_direction_changes(samples, 0, label) == 0,
				"%s flies toward its target without reversing x (raw positions)" % label)
		var y_flips := _direction_changes(samples, 1, label)
		if y_flips != 1:   # dump the raw flight so a failure names the whole path, not one point
			print("[%s] FULL SAMPLE DUMP (%d frames, board-relative): %s"
					% [label, samples.size(), samples])
		check(y_flips == 1,
				"%s arcs: exactly one vertical turn at the peak (raw positions)" % label)
		var target_rel := pa.slot_center_global(slot(2)) - pa.slot_center_global(slot(0))
		var landing : Vector2 = samples[samples.size() - 1] if not samples.is_empty() else Vector2.INF
		check((landing - target_rel).length() < CardVisual.card_size_play.x * 0.5,
				"%s ends its flight AT its target (poof in place)" % label, str(landing))
		await cleanup(g, pa)
	SettingsManager.settings.base_delay = fast

## Ballistic props (ball/fire) must POOF at their target — continuing along the card->target
## diagonal on despawn sent them flying off the board in seemingly random directions.
func test_ballistic_despawn_poofs_in_place() -> void:
	var g := make_board_game(3)
	var pa := make_play_area()
	await settle(pa)
	var pl := pa.prop_layer
	var p := PropData.new()
	p.kind = 2
	p.source = g.state.upper_zone[0].datas[0]   # spawns at its card, arcs to the target
	p.route = [slot(2)] as Array[Vector3i]
	var ok := await run_tick(pl, [p], [p], [], [])
	check(ok, "ballistic spawn tick completes")
	p.at = p.route.pop_front()
	ok = await run_tick(pl, [p], [], [p], [])
	check(ok, "ballistic flight tick completes")
	p.done = true
	ok = await run_tick(pl, [p], [], [], [])
	check(ok, "ballistic despawn tick completes")
	var target := pa.slot_center_global(slot(2))
	var strayed := ""
	var waited := 0.0
	while waited < WATCHDOG_SECS:
		var alive := false
		for child in pl.get_children():
			if child is PropVisual and not child.is_queued_for_deletion():
				alive = true
				var gp := (child as PropVisual).global_position
				if (gp - target).length() > CardVisual.card_size_play.x * 0.5 and strayed.is_empty():
					strayed = "%s vs target %s" % [gp, target]
		if not alive: break
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(strayed.is_empty(),
			"a ballistic prop poofs AT its target (no random exit direction)", strayed)
	await cleanup(g, pa)

## A batch's props take DIFFERENT PropFormation offsets (the plotted card-space points under
## the PropLayer), so a burst spreads into a staggered volley instead of a single-file line
## (owner request 2026-07-12). Point 0 is ZERO by convention — lone props fly the exact line.
func test_batch_props_stagger() -> void:
	var g := make_board_game(3)
	var pa := make_play_area()
	await settle(pa)
	var pl := pa.prop_layer
	check_impl(pl.formation != null, "the prop layer found its PropFormation child")
	var route := g.row_slot_path(slot(0), true)
	var a := PropData.new()
	a.kind = 1
	a.ticks_per_slot = 2
	a.route = route.duplicate()
	a.countdown = a.ticks_per_slot
	var b := PropData.new()
	b.kind = 1
	b.ticks_per_slot = 2
	b.route = route.duplicate()
	b.countdown = b.ticks_per_slot + 1   # run_props stages the i-th of a batch one tick back
	var ok := await run_tick(pl, [a, b], [a, b], [], [])
	check(ok, "the batch spawn tick completes")
	var va : PropVisual = pl._visuals.get(a)
	var vb : PropVisual = pl._visuals.get(b)
	check(va != null and vb != null and absf(va.position.y - vb.position.y) > 2.0,
			"batch mates spread off the single-file line (staggered volley)",
			"%s vs %s" % [va.position if va else Vector2.INF, vb.position if vb else Vector2.INF])
	await cleanup(g, pa)

func test_status_and_description_surface() -> void:
	var g := make_board_game(2)
	var pa := make_play_area()
	await settle(pa)
	var card := g.state.upper_zone[0].datas[0]
	card.add_status(CardModifierStatus.stacked(StatusJuggling, 2))
	var vis : CardVisual = pa.data_card.get(card)
	check(vis != null and vis.status_layer.visible,
			"a front-facing card with a status shows its status layer")
	check_impl(vis != null and vis.status_layer.data == card,
			"the status layer draws from the card's own data")
	# describe_card is THE text every inspector surface shows (focus panel, viewers)
	var text := ControlCard.describe_card(card)
	check(text.contains(StatusJuggling.new().get_str()) and text.contains("×2"),
			"the card description lists the status with its stack count", text)
	check(text.contains(card.suit.get_str()), "the card description names the suit", text)
	await cleanup(g, pa)

func test_focus_inspector_all_input_modes() -> void:
	var g := make_board_game(2)
	var pa := make_play_area()
	await settle(pa)
	var card := g.state.upper_zone[0].datas[0]
	var control : Control = pa.data_ui.get(card)
	control.grab_focus()   # keyboard/controller path
	check(pa._focus_info != null and pa._focus_info.visible,
			"keyboard/controller focus pops the card inspector panel")
	check(pa._focus_info_label.text == ControlCard.describe_card(card),
			"the inspector shows the focused card's full description")
	# descriptions must NEVER interact with input: pure-display panel, no tooltip Window
	check(pa._focus_info.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and pa._focus_info.focus_mode == Control.FOCUS_NONE,
			"the inspector ignores the mouse and can never take focus (no click blocking)")
	check(pa._focus_info.get_parent() == pa.prop_layer,
			"the inspector stays a permanent child of the prop layer (scroll content) — never of a card control")
	# the per-frame pin places it beside the anchor control (right of it, or flipped left)
	await get_tree().process_frame
	var panel_x := pa._focus_info.global_position.x
	var right_x : float = control.global_position.x + control.size.x + pa.FOCUS_INFO_GAP
	var left_x : float = control.global_position.x - pa._focus_info.size.x - pa.FOCUS_INFO_GAP
	check(is_equal_approx(panel_x, right_x) or is_equal_approx(panel_x, left_x),
			"the inspector is pinned beside its anchor control every frame",
			"panel x %.1f vs %.1f / %.1f" % [panel_x, right_x, left_x])
	check(control.tooltip_text.is_empty(),
			"board controls carry NO native tooltip (its popup window blocked clicks)")
	# the mouse path shows the same panel (hover grabs focus), and hides on hover exit
	pa.moused_hovered_control = control
	pa.on_control_focus_entered(control)
	check(pa._focus_info.visible, "mouse-hover focus pops the same inspector")
	pa.moused_hovered_control = null
	pa.hide_focus_info()   # what the control's mouse_exited handler does
	check(not pa._focus_info.visible, "leaving the hover hides it")
	pa.on_control_focus_entered(control)
	check(pa._focus_info.visible, "re-focusing pops it again")
	pa.ungrab_cards()   # the ui_cancel path
	check(not pa._focus_info.visible, "ui_cancel/ungrab dismisses the inspector")
	await cleanup(g, pa)

# ==============================================================================
# FULL VIEW SUBMIT — a real GameView (real game_view.begin_prop_tick seam), real
# starter deck (every card suited -> scored melds spawn props), driven like E2E's
# win scenario but WITH the view attached. The submit runs under a watchdog: a
# prop-tick sync regression fails the check instead of hanging the suite.
# ==============================================================================
func test_game_view_submit_with_props() -> void:
	backup_real_save()
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	# FROZEN test deck, never Decks/deck.gd: this seeded run's observations (the 424242 deal
	# scores knife melds) replay against TestDecks.seeded_deck's exact composition.
	var run := RunManager.new_run(TestDecks.seeded_deck(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	seed(424242)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	var g := view.game
	check(g != null and g.view == view, "the view binds its Game (seam wired)")
	await g.next()
	await g.next()
	var pa := view.play_area
	pa.flush_rebuild()
	check(not pa.ui_data.is_empty(), "the deal built board controls")
	# grab_focus needs a FOCUSABLE control — zone headers of occupied columns are FOCUS_NONE,
	# and ui_data's first key is usually one of those.
	var focusable : Control = null
	for control : Control in pa.ui_data:
		if control.focus_mode == Control.FOCUS_ALL:
			focusable = control
			break
	check(focusable != null, "the dealt board has a focusable card control")
	if focusable: focusable.grab_focus()
	check(pa._focus_info != null and pa._focus_info.visible
			and not pa._focus_info_label.text.is_empty(),
			"focusing a dealt board card pops its inspector text in the real view")
	# fire the submit WITHOUT awaiting it, then poll EVERY FRAME: watchdog + prop high-water
	# mark + the live-seam guards (owner reports 2026-07-13): every hoop/knife must hold its
	# anchor row's y through the REAL submit — score labels re-lay the board every banked pass,
	# which is exactly where the live diagonal drift appeared — and every kind that spawns must
	# enter the visible viewport at least once (hoops reportedly never show in the real view).
	var finished : Array[bool] = [false]
	_submit_then_flag(g, finished)
	var spawned_kinds : Dictionary[String, bool] = {}
	var visible_kinds : Dictionary[String, bool] = {}
	var row_stray : Array[String] = []
	var max_props := await _watch_live_props(pa, finished, spawned_kinds, visible_kinds, row_stray)
	check(finished[0], "a view-attached submit completes (prop tick sync never hangs)")
	check(max_props > 0, "scored suit cards animated props through the PropLayer",
			"high-water %d" % max_props)
	check(row_stray.is_empty(),
			"hoops/knives hold their row's y through a REAL submit (live diagonal guard)",
			"; ".join(row_stray))
	for kind_name : String in spawned_kinds:
		check(visible_kinds.get(kind_name, false) as bool,
				"every spawned %s entered the visible viewport during the submit" % kind_name,
				"spawned but never on-screen")
	check(g.state.total_score > 0, "the submit paid out", str(g.state.total_score))
	var waited := 0.0
	while prop_visual_count(pa.prop_layer) > 0 and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(prop_visual_count(pa.prop_layer) == 0,
			"no prop visual is stranded after the act",
			str(prop_visual_count(pa.prop_layer)))
	# Meld jumps are DESIGNED to hold through the effects pass (score_line calls reset_meld
	# only after _run_score_effects) — but by the end of the submit every surviving card must
	# be back at rest: a stuck jump/spin here is the owner-reported animation-state bug.
	var rest_detail : Array[String] = [""]
	check(await _await_cards_at_rest(pa, rest_detail),
			"every card is at rest after the whole submit (no stuck meld jump or spin)",
			rest_detail[0])
	view.queue_free()   # frees its Game child too
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	# join any in-flight background save BEFORE clearing, then put reality back (E2E pattern)
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save()
	RunManager.run = prev_run
	Main.save_info = prev_save_info

func _submit_then_flag(g: Game, flag: Array[bool]) -> void:
	await g.submit()
	flag[0] = true

## Poll the live PropLayer every frame until `flag` flips (or the watchdog expires): record
## which kinds spawned / were ever visible inside the viewport, and collect row-hold strays —
## every hoop/knife must ride its anchor row's LIVE y through any mid-run relayout (score
## labels widening, focus resizes, rebuilds). Returns the prop-visual high-water mark.
func _watch_live_props(pa: PlayArea, flag: Array[bool],
		spawned_kinds: Dictionary[String, bool], visible_kinds: Dictionary[String, bool],
		row_stray: Array[String]) -> int:
	var max_props := 0
	var waited := 0.0
	while not flag[0] and waited < 3.0 * WATCHDOG_SECS:
		max_props = maxi(max_props, prop_visual_count(pa.prop_layer))
		var view_rect := pa.get_viewport_rect()
		for child in pa.prop_layer.get_children():
			var vis := child as PropVisual
			if not vis or vis.is_queued_for_deletion(): continue
			var kind_name := _kind_name_of(vis)
			spawned_kinds[kind_name] = true
			if view_rect.has_point(vis.global_position):
				visible_kinds[kind_name] = true
			# Row-hold guard: hoops/knives only (ballistic kinds arc off their row by design).
			if not (vis is HoopVisual or vis is KnifeVisual): continue
			if vis.anchor_coord == Vector3i.MIN: continue
			var anchor := pa.slot_center_global(vis.anchor_coord)
			if anchor == Vector2.ZERO: continue   # slot vanished mid-run; nothing to hold to
			if absf(vis.global_position.y - anchor.y) > CardVisual.card_size_play.y * 0.75 \
					and row_stray.size() < 5:
				row_stray.append("%s at %s vs row y %.0f (anchor %s, leg %s -> %s)"
						% [kind_name, vis.global_position, anchor.y, vis.anchor_coord,
						vis.from, vis.target])
		await get_tree().process_frame
		waited += get_process_delta_time()
	return max_props

# ==============================================================================
# FORCED ALL-KINDS LIVE RUN — the seeded submit above spawns only what its deal happens to
# score (the 424242 run spawns knives alone), so hoops/balls/fires never touched the REAL
# seam there and "hoops invisible in game view" slipped through. Craft a board where ONE
# effects pass fans all four kinds at once — including an EMPTY edge column, the live trigger
# for the diagonal staging bug — and run the REAL _run_score_effects through the REAL GameView.
# ==============================================================================
class ProbeSkill extends CardModifierSkill:
	func get_str() -> String: return "Talent"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0

func _suited(rank: int, suit: PipSuit) -> CardData:
	var c := CardData.new().with_rank(PipRankNumeral.new().with_value(rank)).with_suit(suit)
	c.stage = CardData.Stage.PLAY
	return c

func test_all_kinds_live_in_game_view() -> void:
	backup_real_save()
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	# The run only bootstraps a valid save — the board below is fully crafted, so the
	# minimal frozen deck suffices (never Decks/deck.gd; playtest decks change freely).
	var run := RunManager.new_run(TestDecks.minimal_deck(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	var g := view.game
	check(g != null and g.view == view, "the all-kinds view binds its Game (seam wired)")
	CardEnvironment.CURRENT = g
	# Crafted upper zone (row z=0 spans every column, incl. the EMPTY edge one):
	#   col0 EMPTY | col1 hoop3 | col2 knife2 | col3 talent | col4 plain
	#   col5 [talent, ball2]   (ball at z=1 mancala-targets the talent below it)
	#   col6 [plain,  fire2]   (fire at z=1 targets the plain below it)
	var hoop_c := _suited(3, PipSuitHoop.new())
	var knife_c := _suited(2, PipSuitKnife.new())
	var ball_c := _suited(2, PipSuitBall.new())
	var fire_c := _suited(2, PipSuitFire.new())
	var plan : Array = [
		[] as Array[CardData],
		[hoop_c] as Array[CardData],
		[knife_c] as Array[CardData],
		[_suited(5, PipSuitHoop.new()).with_skill(ProbeSkill.new())] as Array[CardData],
		[_suited(5, PipSuitHoop.new())] as Array[CardData],
		[_suited(5, PipSuitHoop.new()).with_skill(ProbeSkill.new()), ball_c] as Array[CardData],
		[_suited(5, PipSuitHoop.new()), fire_c] as Array[CardData],
	]
	var s := GameData.new()
	var types : Array[CardData] = []
	var cols : Array[ArrayCardData] = []
	for col_cards : Array[CardData] in plan:
		var h := CardData.new(); h.stage = CardData.Stage.ZONE
		types.append(h)
		cols.append(TestFactories.col(col_cards))
	s.upper_zone_type = types
	s.upper_zone = cols
	g.state = s          # state_bound rebinds the view to the crafted board
	g._begin_act()
	var pa := view.play_area
	pa.set_card_zones()
	await settle(pa)
	var result := Scoring.Result.new()
	result.meld = [hoop_c, knife_c, ball_c, fire_c] as Array[CardData]
	var finished : Array[bool] = [false]
	_effects_then_flag(g, result, finished)
	# Reaction poses on the REAL seam: the hoop JUMPs the row talents, the knives SPIN them
	# (PropScoreTalents/PropScoreProps reaction_for) — both must be visible on the cards.
	var saw_raised : Array[bool] = [false]
	var saw_spin : Array[bool] = [false]
	_watch_card_poses(pa, finished, saw_raised, saw_spin)
	var spawned_kinds : Dictionary[String, bool] = {}
	var visible_kinds : Dictionary[String, bool] = {}
	var row_stray : Array[String] = []
	var max_props := await _watch_live_props(pa, finished, spawned_kinds, visible_kinds, row_stray)
	check(finished[0], "the forced all-kinds effects pass completes")
	check(saw_raised[0], "a hoop JUMPed a talent during the live pass (card visibly raised)")
	check(saw_spin[0], "a knife SPUN a talent during the live pass (card visibly rotated)")
	check(max_props > 0, "the forced pass animated props", "high-water %d" % max_props)
	for expected : String in ["hoop", "knife", "ball", "fire"]:
		check(spawned_kinds.get(expected, false) as bool,
				"a %s spawned in the real view" % expected, "never spawned")
		check(visible_kinds.get(expected, false) as bool,
				"every spawned %s entered the visible viewport" % expected,
				"spawned but never on-screen")
	check(row_stray.is_empty(),
			"hoops/knives hold their row through the forced live run (empty edge column included)",
			"; ".join(row_stray))
	var waited := 0.0
	while prop_visual_count(pa.prop_layer) > 0 and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	# No pose may outlive the pass: reaction-jumped/spun cards all return to rest.
	var rest_detail : Array[String] = [""]
	check(await _await_cards_at_rest(pa, rest_detail),
			"every card returns to rest after the effects pass (no stuck jump/spin)",
			rest_detail[0])
	view.queue_free()   # frees its Game child too
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save()
	RunManager.run = prev_run
	Main.save_info = prev_save_info

func _effects_then_flag(g: Game, result: Scoring.Result, flag: Array[bool]) -> void:
	await g._run_score_effects(result)
	flag[0] = true
