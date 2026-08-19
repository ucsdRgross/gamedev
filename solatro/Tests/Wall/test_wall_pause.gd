extends TestSuite
# res://Tests/Wall/test_wall_pause.gd
# ==============================================================================
# WALL PAUSE (S12): the engine's own pause system wired to the wall -- Wall/%Camera2D ALWAYS,
# every picture and screen root PAUSABLE by default, exactly one screen root ALWAYS while focused,
# Pacing vs a bare create_timer under the pause.
# PLAN.md §1.6; TEST_PLAN.md §4, U1-U7.
#
# ⚠ RUNS DEAD LAST, ALONE, AFTER LEAK CANARY -- see the SUITE ORDERING chain in test_base.gd. This
# suite constructs a REAL Wall, whose _ready() sets get_tree().paused = true GLOBALLY AND
# PERMANENTLY (§1.6, QR6=a). U1 requires this test to NOT undo that afterward (ASSUMPTIONS.md) --
# unlike test_wall_render.gd's fixture, which unpauses immediately as a concurrency workaround
# because IT runs alongside ~34 other suites that need normal frame processing to finish. That
# workaround would make U1 pass vacuously (proving only that paused briefly became true, never that
# it STAYS true), so this suite instead waits for literally everyone else to finish first
# (await_siblings_except([])) and is the one suite every other waiter now excludes by name.
#
# U2 now covers all three ALWAYS nodes -- WallOverlay (S35) landed after this suite was first
# written (which asserted only Wall and %Camera2D, reporting the omission per the coordinator's
# instruction at the time); extended here now that %Overlay exists in wall.tscn.
# ==============================================================================

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
const MAIN_SCENE := preload("res://Levels/main.tscn")

func suite_name() -> String:
	return "WALL PAUSE"

var _wall : Wall = null
var _pictures : Array[WallPicture] = []

func _ready() -> void:
	await await_siblings_except([])
	TestLog.line("============ WALL PAUSE TEST PASS ============")
	behavior_section("PAUSE WIRING")
	_build_wall()
	await test_tree_paused_and_stays_paused()
	test_shell_stays_always()
	test_exactly_one_screen_live()
	test_wall_view_leaves_zero_live()
	test_info_mode_does_not_pause_focused_screen()
	behavior_section("PACING VS A BARE TIMER UNDER PAUSE")
	await test_pacing_wait_freezes_with_its_own_screen()
	await test_bare_create_timer_ticks_while_paused()
	behavior_section("A REAL MOVE COMPLETES UNDER THE REAL PAUSE (U8, C5)")
	await test_real_wall_moves_complete_under_the_paused_tree()
	finish()

# ------------------------------------------------------------------ fixture

## A throwaway PackedScene wrapping a bare Node, standing in for a real screen -- U3/U4/U7 only
## need something instantiable whose process_mode they can read (ASSUMPTIONS.md).
func _dummy_scene() -> PackedScene:
	var root := Node.new()
	root.name = "DummyScreen"
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

## One authored picture entry at the given angle, always carrying a _dummy_scene() so its packed
## WallPicture has a real "screen root" to flip process_mode on.
func _entry(id: StringName, slot_deg: int) -> PictureEntry:
	var e := PictureEntry.new()
	e.id = id
	e.slot = slot_deg
	e.scene = _dummy_scene()
	return e

## A small, programmatic three-picture layout -- never res://Assets/Wall/layout_default.tres (the
## layout tool's own output, S34, out of scope here), same convention as test_wall_render.gd.
func _make_layout() -> WallLayout:
	var l := WallLayout.new()
	l.gap_px = 24.0
	l.ellipse_aspect_min = 1.2
	l.ellipse_aspect_max = 2.6
	l.home_id = &"a"
	var pics : Array[PictureEntry] = [
		_entry(&"a", 0), _entry(&"b", 120), _entry(&"c", 240),
	]
	l.pictures = pics
	return l

## U1 (D1, QR6=a): constructing a real Wall pauses the tree globally and PERMANENTLY -- unlike
## every other suite that builds a Wall, this one deliberately never clears it afterward. Safe only
## because this suite runs dead last and alone (see header).
func _build_wall() -> void:
	_wall = WALL_SCENE.instantiate()
	add_child(_wall)
	var layout := _make_layout()
	var unlocked : Array[StringName] = [&"a", &"b", &"c"]
	var rects := WallPacker.pack(layout, unlocked, 1.6)
	var by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in layout.pictures: by_id[e.id] = e
	var viewports : Node = _wall.get_node(^"%Viewports")
	var pictures_root : Node = _wall.get_node(^"%Pictures")
	for rect : PictureRect in rects:
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		wp.build(rect, by_id[rect.id], viewports)
		_pictures.append(wp)

## Leaves exactly `target` focused (screen root ALWAYS) and unfocuses every other picture --
## simulating the arbitration wall_picture.gd's own docstring says is the caller's job (S12+'s real
## caller, not yet built, will do the same).
func _focus_only(target: WallPicture) -> void:
	for wp : WallPicture in _pictures:
		if wp == target: wp.focus()
		else: wp.unfocus(Vector2(200, 120))

## How many of _pictures currently have an ALWAYS screen root -- U3/U4's own invariant, read out.
func _always_screen_count() -> int:
	var n := 0
	for wp : WallPicture in _pictures:
		if wp.screen_root and wp.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS:
			n += 1
	return n

# ------------------------------------------------------------------ U1-U4, U7

## U1 (D1, QR6=a): the tree is paused right after construction, and STAYS paused across at least
## one frame boundary with nothing in this test undoing it.
func test_tree_paused_and_stays_paused() -> void:
	check(get_tree().paused, "the tree is paused immediately after constructing a real Wall")
	await get_tree().process_frame
	check(get_tree().paused, "the tree is STILL paused one frame later -- nothing cleared it")

## U2 (D2): Wall, %Camera2D and WallOverlay (mounted at %Overlay, S35) are all PROCESS_MODE_ALWAYS.
func test_shell_stays_always() -> void:
	check(_wall.process_mode == Node.PROCESS_MODE_ALWAYS, "Wall is PROCESS_MODE_ALWAYS")
	var camera : Node = _wall.get_node(^"%Camera2D")
	check(camera.process_mode == Node.PROCESS_MODE_ALWAYS, "%Camera2D is PROCESS_MODE_ALWAYS")
	var overlay : Node = _wall.get_node(^"%Overlay")
	check(overlay.process_mode == Node.PROCESS_MODE_ALWAYS, "%Overlay (WallOverlay) is PROCESS_MODE_ALWAYS")

## U3 (D4, Q74=a): focus each of 3 pictures in turn -> exactly one screen root is ALWAYS each time.
func test_exactly_one_screen_live() -> void:
	for target : WallPicture in _pictures:
		_focus_only(target)
		check(_always_screen_count() == 1,
				"exactly one screen root is ALWAYS while %s is focused" % target.name,
				str(_always_screen_count()))

## U4 (D8, Q74=a): wall view -- every picture unfocused -- leaves zero screen roots ALWAYS.
func test_wall_view_leaves_zero_live() -> void:
	for wp : WallPicture in _pictures:
		wp.unfocus(Vector2(200, 120))
	check(_always_screen_count() == 0, "wall view leaves zero screen roots ALWAYS",
			str(_always_screen_count()))

## U7 (D9, Q138=a): info mode does not pause the focused screen. Info mode itself is S26-S29, out
## of scope here, so there is no real "enter info mode" call to make -- this pins the invariant at
## the level that exists now: the pause rule keys off focus()/unfocus() alone (the wall's
## TRANSITION machinery, not yet built, is the only intended caller), never off zoom. A regression
## guard for the day info mode's zoom-only code path lands: it must not call unfocus().
func test_info_mode_does_not_pause_focused_screen() -> void:
	var target := _pictures[0]
	_focus_only(target)
	check(target.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS,
			"the focused screen's root is still ALWAYS with nothing info-mode-shaped touching it")

# ------------------------------------------------------------------ U5, U6

## U5 (D6, Q75=b): Pacing.wait freezes with ITS OWN SCREEN, which is the contract D6 asked for --
## NOT with the tree. Both halves are asserted, because either alone is satisfied by a broken
## implementation: a timer that never fires passes the frozen half, and a bare `create_timer` passes
## the live half.
##
## ⚠ This test used to assert "Pacing.wait does not fire while paused" and called that correct. It
## was measuring a `SceneTreeTimer`, which has NO node binding: `process_always = false` keys on the
## TREE's pause flag, and §1.6 holds that on for the whole session -- so the helper never fired in
## ANY screen and `game.gd`'s scoring cascade stalled mid-reveal forever, with this check green.
## "Does not fire while the tree is paused" is indistinguishable from "does not fire" when the tree
## is ALWAYS paused; only a per-screen fixture can tell them apart, which is what this is now.
##
## ⚠ Two vacuity traps live in this shape, both from ASSUMPTIONS.md's pause-model-spike entry:
## `await some_timer` without `.timeout` resolves IMMEDIATELY, and a GDScript lambda captures an
## outer local BY VALUE so `func(): fired = true` writes a throwaway copy. `.timeout` is explicit
## and every flag is a one-element typed Array below.
func test_pacing_wait_freezes_with_its_own_screen() -> void:
	_focus_only(_pictures[0])
	var live : Node = _pictures[0].screen_root
	var frozen : Node = _pictures[1].screen_root
	check(live.process_mode == Node.PROCESS_MODE_ALWAYS
			and frozen.process_mode == Node.PROCESS_MODE_PAUSABLE,
			"sanity: the fixture really is one live screen and one frozen one")

	var live_fired : Array[bool] = [false]
	var frozen_fired : Array[bool] = [false]
	Pacing.wait(live, 0.1).timeout.connect(func() -> void: live_fired[0] = true)
	Pacing.wait(frozen, 0.1).timeout.connect(func() -> void: frozen_fired[0] = true)
	await get_tree().create_timer(0.5, true).timeout   # escape hatch -- bare timer, ticks regardless
	check(live_fired[0],
			"Pacing.wait FIRES inside the live screen even though the tree is paused -- the whole "
			+ "show depends on this and it did not happen with a SceneTreeTimer")
	check(not frozen_fired[0], "...and does NOT fire inside a frozen screen (D6's own half)")

## U6 (D6): the trap this whole design defends against, kept green ON PURPOSE -- a BARE
## create_timer ticks straight through the pause (process_always defaults true), exactly why every
## game-code call site was swept onto Pacing in S6. If this ever goes red, a future Godot changed
## process_always's default and Pacing can be retired (TEST_PLAN.md §4's own note on this row).
## Same boxed-Array closure fix as U5 above -- see its comment.
func test_bare_create_timer_ticks_while_paused() -> void:
	var fired : Array[bool] = [false]
	get_tree().create_timer(0.1).timeout.connect(func() -> void: fired[0] = true)
	await get_tree().create_timer(0.5, true).timeout
	check(fired[0], "a bare create_timer(0.1) DID fire within 0.5s while paused")

# ------------------------------------------------------------------ U8

## U8 (§1.6, PICTURE_WALL.md C5): the shipped pause model end to end -- a REAL `Main`, driven
## through the moves a player makes, with the tree LEFT PAUSED exactly as the game runs it.
##
## ⚠ THIS TEST MUST NEVER UNPAUSE, and that is the whole point of it. Every other Main-based suite
## writes `get_tree().paused = false` straight after `add_child()` as a concurrency workaround; the
## game never does. That one habit hid a TOTAL SOFT-LOCK for the whole run: `Main` has no
## `process_mode`, so it is PAUSABLE, and a Tween bound to a PAUSABLE node under a paused tree never
## advances -- so `_animate_camera()`'s `await tween.finished` never returned, `_move_in_flight` and
## `input_locked` stuck true, every handler dead-ended on its own guard, and only Alt+F4 got out.
## The suite stayed green throughout. This suite is the one place the assertion can live, because it
## already runs dead last and alone (see the header) and already leaves the tree paused.
##
## Each move is driven WITHOUT `await` and polled under a BOUNDED escape, so a move that never
## completes fails this check instead of hanging the whole run with no banner.
func test_real_wall_moves_complete_under_the_paused_tree() -> void:
	backup_real_settings()
	var snap := snapshot_settings("wall_")
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	# NO `get_tree().paused = false` here, deliberately -- see this function's doc comment.
	check(get_tree().paused, "sanity: the tree is paused, as the real game holds it all session")
	check(main._current_focus == &"start_menu", "sanity: cold launch focused start_menu",
			str(main._current_focus))


	# The first Wall press: focused picture -> wall view, the move that soft-locked the app.
	var wall_view_done := await _drive_move(func() -> void: await main._go_to_wall_view())
	check(wall_view_done,
			"the first Wall press COMPLETES under the paused tree (a tween bound to a PAUSABLE "
			+ "node would never advance and this move would never return)")
	check(not main._move_in_flight, "...and _move_in_flight cleared, so a second move is possible")
	check(not main.wall.input_locked, "...and input is answered again")
	check(main._current_focus == &"", "...and the wall is actually in wall view",
			str(main._current_focus))
	# C4/I7 (Q104=a): the number keys mean the Nth picture AS PLACED, and only `apply_layout()`
	# records that order. `_build_pictures()` builds each picture at its final rect directly, so
	# nothing recorded it and all nine keys were inert from cold launch until an unlock or a resize
	# happened to call `apply_layout()` for an unrelated reason. Asserted on a COLD `Main` -- in wall
	# view, where no focused screen can consume the action first, and with nothing having called
	# `apply_layout()` for any other reason yet.
	var jumped : Array[StringName] = [&""]   # boxed -- lambdas capture locals BY VALUE
	main.wall.picture_enter_requested.connect(func(id: StringName) -> void: jumped[0] = id)
	var placed_ids : Array[StringName] = []
	placed_ids.assign(main._pictures.keys())   # typed: keys() is untyped Variant under -Werror
	var jump := InputEventAction.new()
	jump.action = &"wall_jump_2"
	jump.pressed = true
	# ⚠ This starts a REAL navigation -- `picture_enter_requested` is wired straight to
	# `Main._focus_picture()`. Driven and awaited like any other move, or it leaves
	# `_move_in_flight` true and every later step in this test refuses on its own guard (measured:
	# it did, and took 9 checks down with it).
	var jump_done := await _drive_move(func() -> void:
			main.wall._unhandled_input(jump)
			while main._move_in_flight:
				await get_tree().process_frame)
	check(jumped[0] != &"",
			"wall_jump_2 reaches a real picture on a COLD launch, with no unlock or resize first",
			str(jumped[0]))
	check(jumped[0] == placed_ids[1],
			"...and it is the SECOND picture in placement order", str(jumped[0]))
	check(jump_done and main._current_focus == placed_ids[1],
			"...and the wall actually navigated there", str(main._current_focus))
	# Back to wall view, so the next step starts where it says it does.
	var back_to_wall := await _drive_move(func() -> void: await main._go_to_wall_view())
	# The STATE is the precondition the next step needs; whether this particular move had frames to
	# run is not (from wall view it is a legitimate no-op, which `_drive_move` reports as false).
	check(main._current_focus == &"", "sanity: back in wall view for the next step",
			"focus=%s move_ran=%s" % [main._current_focus, back_to_wall])

	# Wall view -> a picture: the same `_animate_camera()` path in the other direction.
	var enter_done := await _drive_move(func() -> void: await main._focus_picture(&"map"))
	check(enter_done, "entering a picture from wall view completes under the paused tree")
	check(not main._move_in_flight, "...and _move_in_flight cleared")
	check(main._current_focus == &"map", "...and the picture is focused", str(main._current_focus))

	# D6/Q75=b AT THE PRODUCT LEVEL: `map` is focused, so `map_scene` is the live screen and
	# `menu_scene` is frozen. This is `Pacing`'s real call-site condition -- game code waiting from
	# inside the screen the player is looking at, under the tree the game actually runs paused.
	var live_fired : Array[bool] = [false]
	var frozen_fired : Array[bool] = [false]
	Pacing.wait(main.map_scene, 0.1).timeout.connect(func() -> void: live_fired[0] = true)
	Pacing.wait(main.menu_scene, 0.1).timeout.connect(func() -> void: frozen_fired[0] = true)
	await get_tree().create_timer(0.5, true).timeout   # escape hatch -- bare timer, ticks regardless
	check(live_fired[0],
			"a real screen's Pacing.wait fires while that screen is the focused one")
	check(not frozen_fired[0], "...and an unfocused screen's does not")

	# The postage-stamp defect, at product level: leaving a picture shrinks its render target
	# (GAP-002), and the sprite that shows it draws `viewport.size * scale`. Every picture on the
	# wall must still draw exactly its own rect, focused or not.
	for id : StringName in main._pictures:
		var wp : WallPicture = main._pictures[id]
		var scr : Sprite2D = wp.get_node(^"%Screen")
		var drawn := scr.get_rect().size * scr.scale
		check(drawn.is_equal_approx(wp.rect.size),
				"%s draws exactly its rect after a real enter-and-leave" % id,
				"drawn=%s rect=%s viewport=%s" % [drawn, wp.rect.size, wp.viewport.size])

	# Picture -> picture: the `WallTransition` branch, whose own tween is already camera-bound.
	var hop_done := await _drive_move(func() -> void: await main._focus_picture(&"deck"))
	check(hop_done, "a picture-to-picture move completes under the paused tree")
	check(not main._move_in_flight, "...and _move_in_flight cleared")
	check(main._current_focus == &"deck", "...and the destination is focused",
			str(main._current_focus))

	# H3/Q27/S37 under REDUCED MOTION (K8/Q172=a). `sample_at()`'s reduced branch holds `_wide_zoom`
	# for every elapsed INCLUDING THE LAST, so before `_focus_picture()` settled the camera every
	# destination came to rest at wall zoom with its own frame showing -- the one state H3 forbids,
	# on every transition. T12 pins the zoom DURING the transition; this pins where it ENDS, and
	# neither half is visible from the other.
	SettingsManager.settings.wall_reduced_motion = true
	var reduced_done := await _drive_move(func() -> void: await main._focus_picture(&"map"))
	check(reduced_done, "a reduced-motion move completes under the paused tree")
	var camera : Camera2D = main.wall.get_node(^"%Camera2D")
	var expected := WallPicture.focused_scale(main._rects[&"map"].size, main._window_size,
			SettingsManager.settings.wall_overfill_margin)
	var wide := main.wall.wall_view_zoom(main._window_size)
	check(absf(camera.zoom.x - expected) < 0.001,
			"reduced motion RESTS at the destination's focused zoom, frame off-screen",
			"zoom=%.4f expected=%.4f" % [camera.zoom.x, expected])
	# Without this the check above could pass on a layout where the two happen to coincide.
	check(expected - wide > 0.1,
			"sanity: the focused zoom and the wall zoom are far apart in this fixture, so the "
			+ "check above can actually fail", "focused=%.4f wall=%.4f" % [expected, wide])

	main.queue_free()
	restore_settings_snapshot(snap)
	restore_real_settings()

## Starts `body` as a coroutine and polls for its return under a bounded wall-clock escape, so a
## move that never completes reports FALSE instead of hanging the run. `process_frame` is the one
## signal that still fires while the tree is paused, which is what makes the poll possible at all.
func _drive_move(body: Callable, budget_ms: int = 8000) -> bool:
	var done : Array[bool] = [false]   # boxed -- lambdas capture locals BY VALUE
	_drive(body, done)
	var started := Time.get_ticks_msec()
	var polls := 0
	while not done[0] and Time.get_ticks_msec() - started < budget_ms:
		await get_tree().process_frame
		polls += 1
	# Trap 5 ([[tests-that-prove-nothing]]): `polls == 0` means the coroutine returned before a
	# single frame passed, which no real move can do -- every one of them takes tens of frames. It
	# is what `if _move_in_flight: return` does when an EARLIER move is stuck, so without this a
	# soft-locked wall reports every LATER move as "completed instantly" and the check goes green
	# on the strength of the very defect it exists to catch. Measured: with the soft-lock restored,
	# moves 2 and 3 polled 0 frames and claimed success until this clause was added.
	return done[0] and polls > 0

func _drive(body: Callable, done: Array[bool]) -> void:
	await body.call()
	done[0] = true
