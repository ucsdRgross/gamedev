extends TestSuite
# res://Tests/Wall/test_wall_focus.gd
# ==============================================================================
# WALL FOCUS (S5): FocusStack -- the Back/Forward history for the picture wall, ids only.
# PLAN.md §1.4; TEST_PLAN.md §2, F1-F7. Plus §6b's overlay group (S35): F8, F9 -- they live here,
# not in a new suite, because they are stack semantics (FocusStack.can_back/can_forward) wearing UI
# (WallOverlay.refresh). Plus F13 (S30): wall state does not survive a quit, and F12 (S38): an
# unlock reaction leaves a REAL Main's REAL, live stack valid. NOT F10/F11: those need popups
# (S35's own scope note elsewhere already covers F10/F11's other halves), still out of scope here.
#
# CATEGORY MAP: every row here is BEHAVIOR -- a player-visible navigation contract (Q63-Q66), not
# an internal storage detail.
#
# FocusStack's API is exactly visit/back/forward/can_back/can_forward (§1.4) -- there is no depth
# or contents accessor, on purpose. Every test that needs to read the stack's SHAPE (not just one
# call's return value) walks it through that fixed API alone: the test already knows what it last
# visited (it just called visit() with it), and repeated back() calls read everything below that,
# in order, until &"" -- see _walk_stack.
# ==============================================================================

const WALL_OVERLAY_SCENE := preload("res://UI/Wall/wall_overlay.tscn")
const MAIN_SCENE := preload("res://Levels/main.tscn")

func suite_name() -> String:
	return "WALL FOCUS"

func _ready() -> void:
	TestLog.line("============ WALL FOCUS TEST PASS ============")
	behavior_section("BACK / FORWARD RETRACE VISIT ORDER")
	test_back_retraces_visit_order()
	test_revisit_moves_to_top()
	test_depth_bounded_by_distinct_ids()
	test_forward_returns_the_picture_just_left()
	test_new_visit_clears_forward()
	test_back_on_empty_stack()
	test_wall_view_is_never_an_entry()
	behavior_section("OVERLAY (S35): BACK/FORWARD VISIBLY DISABLE")
	test_back_visibly_disabled_at_bottom_of_stack()
	test_forward_visibly_disabled_with_nothing_ahead()
	behavior_section("WALL STATE DOES NOT SURVIVE A QUIT (S30, F13)")
	test_wall_state_does_not_survive_a_quit()
	behavior_section("UNLOCK MID-SESSION (S38, F12)")
	await test_unlock_reaction_leaves_the_real_focus_stack_valid()
	behavior_section("LOST-RUN BEHAVIOUR (S32, L12, Q157)")
	test_lost_run_leaves_map_and_game_pictures_unchanged()
	behavior_section("INFO CARD MOUNTED ON THE WALL (A1, CODE_REVIEW.md)")
	test_info_card_is_mounted_on_the_wall()
	behavior_section("INFO TOGGLE WIRING (A2, CODE_REVIEW.md)")
	await test_info_toggle_sets_flag_and_moves_camera_and_resets_card()
	behavior_section("FOCUS/TRANSITION SIGNALS (A4, CODE_REVIEW.md, NAMES.md)")
	await test_focus_and_transition_signals_fire_during_real_navigation()
	behavior_section("INFO MODE DOES NOT SURVIVE A QUIT (C3, ADVERSARIAL_REVIEW.md, J1)")
	test_info_mode_does_not_survive_a_relaunch()
	behavior_section("RESIZE REACHES THE WALL (M1, ADVERSARIAL_REVIEW.md, S17, T11 wiring)")
	await test_a_real_resize_reaches_the_wall()
	finish()

## F1 (Q63=a): visit a, b, c -> back() retraces to b, the picture visited just before c.
func test_back_retraces_visit_order() -> void:
	var fs := FocusStack.new()
	fs.visit(&"a")
	fs.visit(&"b")
	fs.visit(&"c")
	var result := fs.back()
	check(result == &"b", "back() after visiting a, b, c returns b", str(result))

## F2 (Q64): visiting an id already in the stack MOVES it to the top instead of appending a
## second entry. Read the resulting stack back out through the fixed API, since no inspection
## method exists.
func test_revisit_moves_to_top() -> void:
	var fs := FocusStack.new()
	fs.visit(&"a")
	fs.visit(&"b")
	fs.visit(&"c")
	fs.visit(&"b")   # b is already in the stack -> moves, does not duplicate
	var order := _walk_stack(fs, &"b")
	var expected : Array[StringName] = [&"a", &"c", &"b"]
	check(order == expected, "stack reads a, c, b bottom to top after the revisit", str(order))
	check(order.size() == 3, "depth is 3 -- the revisit moved, it did not append",
			str(order.size()))

## F3 (Q64): depth never exceeds the number of DISTINCT pictures visited, however many times any
## one of them is revisited. This is a structural consequence of "revisit moves" (F2): an id can
## never occupy two slots, so re-visiting an already-seen id cannot grow the stack. That makes the
## invariant order-independent, so one shuffled pass covering every id several times is a full
## check of it, not a sample.
func test_depth_bounded_by_distinct_ids() -> void:
	var fs := FocusStack.new()
	var ids : Array[StringName] = [&"p1", &"p2", &"p3", &"p4", &"p5", &"p6"]
	var shuffled : Array[StringName] = [
		&"p3", &"p1", &"p5", &"p2", &"p1", &"p6", &"p4", &"p2", &"p3", &"p6",
		&"p5", &"p1", &"p4", &"p3", &"p2", &"p6", &"p5", &"p4", &"p1", &"p3",
	]
	check(shuffled.size() == 20, "fixture is the specified 20 visits", str(shuffled.size()))
	for id : StringName in shuffled:
		check(ids.has(id), "fixture only visits the 6 registered ids", str(id))
	for id : StringName in shuffled:
		fs.visit(id)
	var order := _walk_stack(fs, shuffled[-1])
	check(order.size() <= 6, "depth never exceeds the 6 distinct pictures visited",
			str(order.size()))

## F4 (Q64): back() then forward() returns to the picture that was just left.
func test_forward_returns_the_picture_just_left() -> void:
	var fs := FocusStack.new()
	fs.visit(&"a")
	fs.visit(&"b")
	fs.back()
	var result := fs.forward()
	check(result == &"b", "forward() after back() returns the picture just left", str(result))

## F5 (Q64): a new visit clears whatever was available to redo, exactly as a browser does.
func test_new_visit_clears_forward() -> void:
	var fs := FocusStack.new()
	fs.visit(&"a")
	fs.visit(&"b")
	fs.back()
	check(fs.can_forward(), "can_forward() is true immediately after a back()")
	fs.visit(&"c")
	check(not fs.can_forward(), "a new visit clears the forward list")

## F6 (Q65=a): back() on a stack nothing has ever been visited on returns &"". The CALLER's
## contract (not FocusStack's) is to treat that as "go to wall view" -- see F7 for why FocusStack
## itself never represents wall view as an entry at all.
func test_back_on_empty_stack() -> void:
	var fs := FocusStack.new()
	check(not fs.can_back(), "can_back() is false on a fresh stack")
	var result := fs.back()
	check(result == &"", "back() on an empty stack returns &\"\"", str(result))

## F7 (Q66=b): wall view is never a stack entry. "Enter wall view" is deliberately NOT a call on
## FocusStack anywhere in this test -- the caller just stops calling visit() while it is shown, and
## the stack is unaffected, so a later back() skips straight over where wall view would have been.
func test_wall_view_is_never_an_entry() -> void:
	var fs := FocusStack.new()
	fs.visit(&"a")
	# ... wall view is shown here, by the caller, off FocusStack entirely ...
	fs.visit(&"b")
	var result := fs.back()
	check(result == &"a", "back() after wall view lands on a, not on a wall-view entry",
			str(result))

## F8 (Q65=c): Back VISIBLY disables itself -- `Button.disabled`, not merely a press that silently
## does nothing -- with an empty stack (nothing behind the current picture), and re-enables once
## there is something to go back to, proving refresh() actually recomputes rather than being stuck.
func test_back_visibly_disabled_at_bottom_of_stack() -> void:
	var overlay : WallOverlay = WALL_OVERLAY_SCENE.instantiate()
	add_child(overlay)
	var back_button : Button = overlay.get_node(^"%BackButton")
	var fs := FocusStack.new()
	overlay.refresh(fs)
	check(back_button.disabled, "Back reports disabled (not merely inert) with an empty stack")
	fs.visit(&"a")
	fs.visit(&"b")
	overlay.refresh(fs)
	check(not back_button.disabled, "Back re-enables once there is something behind the current one")
	overlay.queue_free()

## F9: Forward is visibly disabled with nothing ahead (fresh visit, no back() taken yet), and
## re-enables once a back() leaves something to redo.
func test_forward_visibly_disabled_with_nothing_ahead() -> void:
	var overlay : WallOverlay = WALL_OVERLAY_SCENE.instantiate()
	add_child(overlay)
	var forward_button : Button = overlay.get_node(^"%ForwardButton")
	var fs := FocusStack.new()
	fs.visit(&"a")
	overlay.refresh(fs)
	check(forward_button.disabled, "Forward reports disabled (not merely inert) with nothing ahead")
	fs.visit(&"b")
	fs.back()
	overlay.refresh(fs)
	check(not forward_button.disabled, "Forward re-enables once a back() leaves something to redo")
	overlay.queue_free()

## Reads a FocusStack's contents, bottom (oldest) to top (current), through the fixed API alone.
## `known_top` is whatever the caller last passed to visit() -- back() only ever reports the entry
## BELOW the current one, never the current itself, so the top has to be supplied rather than
## discovered. Repeated back() then walks everything beneath it down to the bottom, in order,
## until &"". Consuming: every entry this reads ends up in the stack's forward list.
func _walk_stack(fs: FocusStack, known_top: StringName) -> Array[StringName]:
	var order : Array[StringName] = [known_top]
	var step := fs.back()
	while step != &"":
		order.append(step)
		step = fs.back()
	order.reverse()
	return order

# ------------------------------------------------------------------ F13 (S30)

## F13 (K6, Q145=b, Q149=a): wall state does NOT survive a quit -- every launch opens on the
## start-menu picture, and nothing about "which picture you were on" is ever written to disk.
##
## ⚠ "Assert it did NOT happen" trap (HANDOFF traps section): a relaunch that never wrote
## anything would ALSO pass a check that only looks for absence. Both halves asserted, each
## checked so it would actually go red if broken:
##   1. THE WRITE PATH RAN -- session one visits real pictures and `can_back()` genuinely flips
##      true, proving this test exercises a stack with real history, not an empty one that
##      trivially "resets" by having nothing to lose in the first place.
##   2. A second, INDEPENDENT `Wall.cold_launch_focus_stack()` call starts at start_menu with
##      nothing to go back to, and further mutating session one afterward still never reaches
##      it -- genuinely independent objects, not two references to the same stack.
##   3. NO field on `PlayerProfile` or `PlayerSettings` even NAMES a current-picture/focus
##      concept -- a structural scan of both resources' own exported property lists, not a guess
##      about what "wasn't added."
func test_wall_state_does_not_survive_a_quit() -> void:
	var session_one := Wall.cold_launch_focus_stack()
	check(not session_one.can_back(),
			"a fresh cold-launch stack starts with nothing to go back to (just start_menu)")
	session_one.visit(&"map")
	session_one.visit(&"deck")
	check(session_one.can_back(),
			"the write path actually ran -- session one now has real history to lose")

	var session_two := Wall.cold_launch_focus_stack()
	check(not session_two.can_back(),
			"a second, independent cold launch starts fresh at start_menu -- "
			+ "session one's history did not survive")
	check(session_two.back() == &"",
			"and there is nothing to go back to -- start_menu is the only entry")

	session_one.visit(&"start_menu")   # further mutation of session one...
	check(not session_two.can_back(),
			"...still never reaches session two -- genuinely independent objects, not aliased")

	var offending_fields : Array[String] = []
	for resource : Resource in [PlayerProfile.new(), PlayerSettings.new()]:
		for prop : Dictionary in resource.get_property_list():
			var usage : int = prop["usage"]
			if not (usage & PROPERTY_USAGE_STORAGE): continue
			var prop_name : String = (prop["name"] as String).to_lower()
			if "focus" in prop_name or "current_picture" in prop_name or "wall_current" in prop_name:
				offending_fields.append("%s.%s" % [resource.get_class(), prop["name"]])
	check(offending_fields.is_empty(),
			"no PERSISTED field on PlayerProfile/PlayerSettings names a current-picture/focus "
			+ "concept", "offending=%s" % [offending_fields])

# ------------------------------------------------------------------ F12 (S38)

## F12 (K4, Q156=a): an unlock mid-session leaves the FocusStack VALID -- TEST_PLAN's own row is a
## claim about PRODUCTION WIRING, not about `FocusStack`'s arithmetic (F1-F7 already cover that in
## isolation). An earlier version of this test built a disconnected `FocusStack.new()` that
## `Wall.apply_layout()` never touched at all -- so its "Back still lands on b" checks could not
## have gone red for a wiring bug that corrupted the REAL stack, only for a bug in `FocusStack`
## itself, which F1-F7 already prove separately. Same shape as the `await`-vs-`.timeout` and
## lambda-capture traps this run's own HANDOFF names: a test that cannot fail for the thing its own
## row claims to prove.
##
## Rebuilt to exercise the FULL REAL CHAIN end to end, on a REAL `Main`: a real
## `ProfileManager.unlock(&"book")` call (saves immediately, emits `picture_unlocked`) ->
## `Main._ready()`'s own `ProfileManager.picture_unlocked.connect(_repack_wall)` -> the real
## `_repack_wall()` -> the real, live `_focus_stack`. Nothing here is called directly as a
## substitute for the signal anymore (register-settings-book correction, coordinator): `book` is
## `unlocked_by_default = false` in `Wall.initial_layout()` (ASSUMPTIONS.md), so it is a picture
## genuinely never built before this test unlocks it -- the real "starts locked, becomes unlocked"
## id the four-picture layout could not provide, letting this test finally exercise K2's OTHER
## half too ("no reveal ceremony -- the picture is simply there next time").
##
## `ProfileManager` is a real, shared autoload -- parked/swapped exactly as `test_wall_profile.gd`'s
## own R-tests do (same file, same idiom), so unlocking `book` here for real cannot leak into, or
## be polluted by, whichever profile state a concurrently-running suite or the real player has.
## `ProfileManager.unlock()` and `Main._repack_wall()` are both fully synchronous (no `await`
## anywhere in either body), so the whole park -> unlock -> repack -> restore sequence runs as one
## uninterrupted block with no window for another suite's own profile work to interleave.
func test_unlock_reaction_leaves_the_real_focus_stack_valid() -> void:
	var real_path := ProfileManagerClass.SAVE_PATH
	var parked_path := real_path + ".test_wall_focus_f12.testbak"
	var had_real_file := FileAccess.file_exists(real_path)
	if had_real_file:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(real_path),
				ProjectSettings.globalize_path(parked_path))
	var real_profile := ProfileManager.profile
	ProfileManager.profile = PlayerProfile.new()

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var main : Main = MAIN_SCENE.instantiate()
	viewport.add_child(main)
	# Wall._ready() (inside Main._ready(), just run by add_child above) sets get_tree().paused =
	# true GLOBALLY -- undone immediately, same established reason every other Wall-building test
	# in this suite/TestWallRender/TestWallPause already documents: ~38 OTHER suites run
	# concurrently and a global pause with nothing to clear it hangs the whole run.
	get_tree().paused = false

	# Cold launch already visited start_menu (Wall.cold_launch_focus_stack(), Main._ready()). Two
	# more REAL navigations, through the REAL Main._focus_picture() path (a real WallTransition,
	# same as a player pressing into a picture), give Back three real ids to retrace.
	await main._focus_picture(&"map")
	await main._focus_picture(&"deck")
	check(main._focus_stack.can_back(),
			"sanity: the real navigation above actually built real history to lose")
	check(not main._pictures.has(&"book"),
			"sanity: book starts LOCKED (unlocked_by_default = false) and was never built -- "
			+ "K2's own 'no reveal ceremony' half needs a picture genuinely absent before the unlock")

	# Captured BEFORE the unlock so the geometry assertion below can tell a REAL re-pack (a fresh
	# PictureRect object from a fresh WallPacker.pack() call) apart from a no-op.
	var rect_before : PictureRect = main._pictures[&"start_menu"].rect

	# THE REAL UNLOCK -- fires the REAL signal, which Main._ready() already wired straight to the
	# REAL _repack_wall(). Nothing here re-derives or shortcuts any link in that chain.
	ProfileManager.unlock(&"book")

	check(main._pictures.has(&"book"),
			"K2: the newly-unlocked picture is simply there, built with no reveal ceremony")
	check(main._pictures[&"start_menu"].rect != rect_before,
			"sanity: the re-pack actually ran -- start_menu's rect is a fresh object, not the "
			+ "pre-unlock one (a vacuous re-pack would make this check meaningless)")

	# Back must retrace the SAME three real ids in the SAME order as before the unlock --
	# COMPLETELY UNAFFECTED by every picture's rect being freshly rebuilt underneath it and a
	# brand-new picture appearing, because _repack_wall() never touches _focus_stack (it only
	# READS it, via overlay.refresh()).
	check(main._focus_stack.back() == &"map",
			"Back still lands on map after a REAL unlock through the REAL wiring")
	check(main._focus_stack.back() == &"start_menu", "...then start_menu...")
	check(main._focus_stack.back() == &"",
			"...then nothing left, same as any other exhausted stack")

	main.queue_free()
	viewport.queue_free()
	ProfileManager.profile = real_profile
	if FileAccess.file_exists(real_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(real_path))
	if had_real_file:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(parked_path),
				ProjectSettings.globalize_path(real_path))

# ------------------------------------------------------------------ S32 (L12, Q157)

## S32 (L12, Q157=a -- "stays on the wall, shows its own empty state... the map is replaced only
## when a new run starts"): a lost run leaves BOTH the map picture's screen and the game picture's
## screen UNCHANGED -- neither rebuilt, freed, nor detached. Previously this rested on code review
## alone (no test, no ASSUMPTIONS entry -- flagged in this run's own verification pass).
##
## `Main._on_run_lost()` is the exact method a real GameView's `run_lost` signal fires
## (`enter_game()`'s own `new_view.run_lost.connect(_on_run_lost)`); called DIRECTLY here, same
## reasoning F12 uses for `_repack_wall()` -- it runs the real method against a real Main without
## needing a full, playable `GameView`/`RunManager` show to reach it. A bare `Node` stands in for
## the game-over screen `attach_screen()` would hold (same fixture shape
## `test_build_reparents_a_live_screen_unchanged`/`test_screen_root_survives_repeated_focus_
## unfocus_cycles` in `test_wall_render.gd` already use for "a live screen", never a mock of
## GameView's own behaviour -- `_on_run_lost()`'s own logic never reads anything ABOUT the screen,
## only whether it exists).
##
## `backup_real_save()`/`restore_real_save()` (`test_base.gd`, the same pattern
## `test_run_manager.gd`/`test_leak_canary.gd` already use) park the real
## `user://run_save/run.tres` for the call's duration -- `_on_run_lost()` calls
## `RunManager.clear_save()`, which deletes that file. Paired tightly around ONE synchronous call
## with no `await` anywhere in `_on_run_lost()`'s own body, so no concurrently-running sibling
## suite's own disk-save work can interleave inside the exposure window.
##
## ⚠ Q157's OTHER half ("the map is replaced only when a new run starts") is not exercised here --
## `_on_new_run()` ends in `await _go_to_wall_view()`, which would hold this test's own exposure
## window open across a real camera animation while `backup_real_save()`'s park is still shared,
## global (not per-suite like the settings backup), and genuinely un-scoped against whichever OTHER
## suite might also be mid-save at that moment. That half remains evidenced by code review alone
## (ASSUMPTIONS.md): `_on_new_run()`'s own `game_wp.detach_screen()` line is the one place either
## picture is ever actually replaced.
func test_lost_run_leaves_map_and_game_pictures_unchanged() -> void:
	backup_real_save()
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	get_tree().paused = false

	var game_wp : WallPicture = main._pictures[&"game"]
	var lose_screen_stand_in := Node.new()
	lose_screen_stand_in.name = "LoseScreenStandIn"
	game_wp.attach_screen(lose_screen_stand_in)   # simulates a real GameView's game-over state
	var map_before : Map = main.map_scene

	main._on_run_lost()

	check(main.map_scene == map_before,
			"L12: the map picture's own screen is the SAME object after a lost run -- not rebuilt "
			+ "or replaced")
	check(game_wp.screen_root == lose_screen_stand_in,
			"L12: re-entering the game picture would show the SAME game-over screen -- "
			+ "_on_run_lost() never detaches it")
	check(is_instance_valid(lose_screen_stand_in),
			"...and it was never freed either")

	restore_real_save()
	main.queue_free()

# ------------------------------------------------------------------ A1 (CODE_REVIEW.md)

## A1 (CODE_REVIEW.md): `InfoCard` was mounted only on the map -- `wall.tscn`/`wall.gd` referenced
## it ZERO times, so info mode on the wall displayed nothing even though J1-J6 passed against a
## standalone card built directly by that suite. Structural proof it is genuinely part of the wall
## scene now: read through the REAL `Wall` scene's own `%Overlay` node, by the exact path
## `Main._on_info_toggled()` uses below.
func test_info_card_is_mounted_on_the_wall() -> void:
	var wall : Wall = preload("res://UI/Wall/wall.tscn").instantiate()
	add_child(wall)
	get_tree().paused = false
	var info_card : Node = wall.get_node(^"%Overlay/InfoCard")
	check(info_card != null and info_card is InfoCard,
			"a real InfoCard instance is mounted inside the wall's own %Overlay",
			str(info_card))
	wall.queue_free()

# ------------------------------------------------------------------ A2 (CODE_REVIEW.md)

func _probe_info_entry() -> InfoEntry:
	var e := InfoEntry.new()
	e.title = "probe"
	e.body = "probe"
	return e

## A2 (CODE_REVIEW.md, J2/Q128, J6/Q131): the Info button previously had no consumer anywhere --
## pressing it changed nothing. Drives `Main._on_info_toggled()` DIRECTLY (the exact method
## `overlay.info_toggled` is wired to in `Main._ready()`) against a REAL `Main`, REAL focused
## picture, and asserts THREE separate consequences, none of which the old (nonexistent) wiring
## produced: (1) the shared `wall_info_mode` flag actually flips; (2) the camera actually MOVES to
## the info zoom -- a measurably different framing than the ordinary at-rest one, not merely "a
## tween ran"; (3) toggling back off resets `%InfoCard` (J6) and returns the camera to rest.
## `backup_real_settings()`/`restore_real_settings()` (`test_wall_render.gd`'s S39 gate test
## already established this exact pattern) park the real `user://settings.tres`, since
## `wall_info_mode` saves on every change.
func test_info_toggle_sets_flag_and_moves_camera_and_resets_card() -> void:
	backup_real_settings()
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	get_tree().paused = false

	var settings := SettingsManager.settings
	var prev_mode := settings.wall_info_mode
	var camera : Camera2D = main.wall.get_node(^"%Camera2D")
	var info_card : InfoCard = main.wall.get_node(^"%Overlay/InfoCard")
	var rest_position := camera.position
	var rest_zoom := camera.zoom

	await main._on_info_toggled(true)
	check(settings.wall_info_mode, "wall_info_mode is true after toggling Info on")
	check(not camera.position.is_equal_approx(rest_position)
			or not camera.zoom.is_equal_approx(rest_zoom),
			"the camera actually moved to the info zoom -- a different framing than at rest",
			"rest pos=%s zoom=%s -- info pos=%s zoom=%s"
					% [rest_position, rest_zoom, camera.position, camera.zoom])

	info_card.show_entry(_probe_info_entry())
	check(info_card.visible, "sanity: the card can be shown while info mode is on")

	await main._on_info_toggled(false)
	check(not settings.wall_info_mode, "wall_info_mode is false after toggling Info off")
	check(not info_card.visible,
			"leaving info mode resets %InfoCard to hidden (J6) -- proven able to fail: it was "
			+ "genuinely visible just above")
	check(camera.position.is_equal_approx(rest_position) and camera.zoom.is_equal_approx(rest_zoom),
			"the camera returns to the ordinary at-rest framing",
			"got pos=%s zoom=%s want pos=%s zoom=%s"
					% [camera.position, camera.zoom, rest_position, rest_zoom])

	settings.wall_info_mode = prev_mode
	restore_real_settings()
	main.queue_free()

# ------------------------------------------------------------------ A4 (CODE_REVIEW.md, NAMES.md)

## A4 (CODE_REVIEW.md, NAMES.md): three of NAMES.md's five `Wall` signals -- `focus_changed`,
## `transition_started`, `transition_landed` -- were named in the registry but never declared or
## emitted anywhere. Real navigation through a REAL `Main` (start_menu -> map, a genuine
## picture-to-picture `WallTransition`, the only case `transition_started`/`transition_landed`
## apply to per NAMES.md's own `(from_id, to_id)`/`(picture_id)` shapes -- wall view is never a
## picture id, Q66=b) must fire all three, in the right order, with the right ids.
func test_focus_and_transition_signals_fire_during_real_navigation() -> void:
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	get_tree().paused = false

	var focus_events : Array[StringName] = []
	var started_events : Array = []
	var landed_events : Array[StringName] = []
	main.wall.focus_changed.connect(func(id: StringName) -> void: focus_events.append(id))
	main.wall.transition_started.connect(
			func(from_id: StringName, to_id: StringName) -> void:
				started_events.append([from_id, to_id]))
	main.wall.transition_landed.connect(func(id: StringName) -> void: landed_events.append(id))

	await main._focus_picture(&"map")

	check(focus_events == ([&"map"] as Array[StringName]),
			"focus_changed fired once, for the real destination id", str(focus_events))
	var started_ok := false
	if started_events.size() == 1:
		var pair : Array = started_events[0]
		var from_id : StringName = pair[0]
		var to_id : StringName = pair[1]
		started_ok = from_id == &"start_menu" and to_id == &"map"
	check(started_ok,
			"transition_started fired once, with the real (from_id, to_id) pair",
			str(started_events))
	check(landed_events == ([&"map"] as Array[StringName]),
			"transition_landed fired once, for the real destination id", str(landed_events))

	main.queue_free()

# ------------------------------------------------------------------ C3 (ADVERSARIAL_REVIEW.md)

## C3 (ADVERSARIAL_REVIEW.md, J1, PLAN.md §4 anti-scope item 9): info mode must NOT survive a
## quit. `wall_info_mode` stays a REAL `PlayerSettings` field (`WallTransition.sample_at()`'s
## existing S18/J10 read keeps working unchanged, no signature/shape change there), which means
## LEAVING it true would persist to `user://settings.tres` on the very write that set it -- a real
## relaunch's `SettingsManager._init()` loads that file straight back, exactly like a real "info
## mode survived a quit" bug. Simulates that: sets the flag true (standing in for "a previous
## session's own save already has this"), then builds a REAL `Main` -- the exact object whose
## `_ready()` must now reset it -- and asserts it reads false immediately after `_ready()` runs.
## `backup_real_settings()`/`restore_real_settings()` park the real file, since this genuinely
## writes it (twice: the simulated "previous session" write, and Main's own reset write).
func test_info_mode_does_not_survive_a_relaunch() -> void:
	backup_real_settings()
	var settings := SettingsManager.settings
	settings.wall_info_mode = true   # stands in for a previous session's own persisted value

	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	get_tree().paused = false

	check(not settings.wall_info_mode,
			"a fresh Main resets wall_info_mode to false on startup, even if a previous session "
			+ "left it true -- info mode never survives a relaunch (C3)")

	main.queue_free()
	restore_real_settings()

# ------------------------------------------------------------------ M1 (ADVERSARIAL_REVIEW.md, S17)

## M1 (ADVERSARIAL_REVIEW.md): S17's resize path was built and had NO caller -- nothing anywhere
## connected `size_changed`, so `WallTransition.retarget()` had zero callers and a resize left the
## whole wall packed for the old aspect. This is the WIRING half of T11 (the pure geometry half
## lives in `TestWallTransition`); it goes red the moment `Main._ready()`'s
## `get_viewport().size_changed.connect(_on_window_resized)` is removed.
##
## A REAL `Main` inside its OWN `SubViewport` (the F12 idiom above), because `main._window_size` is
## read straight off `get_viewport()` -- a SubViewport is the only window a test can actually resize
## without disturbing the ~38 suites sharing the real one.
##
## ⚠ ONE `Main`, held for as few frames as possible, and the mid-flight half runs at a
## deliberately tiny `wall_transition_delay`. A live `Main` puts a real `Map` in the tree, and `Map`
## is a `CardEnvironment`, so `CardEnvironment.CURRENT` is non-null for as long as it lives -- which
## a concurrently-running suite can see. Written first as two tests holding a `Main` across a
## full-length transition, that window was wide enough for `TestOutline` to build a PREVIEW
## `CardVisual` inside it and take `card_visual.gd:573`'s no-anchor branch, failing a DIFFERENT
## suite with a Nil `global_position` ([[tests-that-prove-nothing]] trap 8).
func test_a_real_resize_reaches_the_wall() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var main : Main = MAIN_SCENE.instantiate()
	viewport.add_child(main)
	# Wall._ready() paused the whole tree globally -- undone immediately, same reason F12 documents.
	get_tree().paused = false

	# ---- at rest: 1280x720 -> 2560x720 is a genuine ASPECT change (16:9 -> 32:9, both inside G13's
	# supported range), so a wall that failed to re-pack cannot accidentally still fit.
	check(main._current_focus == &"start_menu",
			"sanity: a cold launch opens focused on start_menu, so there IS a focused picture whose "
			+ "overfill a resize can break", str(main._current_focus))
	var rect_before : PictureRect = main._rects[&"start_menu"]

	var wide := Vector2i(2560, 720)
	viewport.size = wide
	var wide_window := Vector2(wide)

	check(main._window_size.is_equal_approx(wide_window),
			"the resize reached Main at all -- before M1 nothing was listening for it",
			str(main._window_size))
	check(main._rects[&"start_menu"] != rect_before,
			"G7/Q22=b: the wall RE-PACKED at the new aspect (a fresh PictureRect from a fresh "
			+ "WallPacker.pack(), not the pre-resize object)")

	var camera : Camera2D = main.wall.get_node(^"%Camera2D")
	var focused_rect : PictureRect = main._rects[&"start_menu"]
	check(camera.position.is_equal_approx(focused_rect.centre),
			"the camera re-centred on the focused picture's NEW centre",
			"%s vs %s" % [str(camera.position), str(focused_rect.centre)])
	# Q27/H3: the player-visible claim, asserted directly rather than by re-deriving focused_scale()
	# -- at rest the focused picture COVERS the window on both axes, so its frame stays off-screen.
	var covered := focused_rect.size * camera.zoom.x
	check(covered.x >= wide_window.x and covered.y >= wide_window.y,
			"Q27: the focused picture still OVERFILLS the resized window on both axes, so its own "
			+ "frame is still off-screen at rest",
			"covers %s of window %s" % [str(covered), str(wide_window)])

	# ---- mid-flight (Q26=a): a resize arriving during a transition RETARGETS it and lets it
	# continue -- never restarts it, never snaps the camera out from under it. `_focus_picture()` is
	# deliberately NOT awaited at the call: it runs synchronously up to its own first `await`, by
	# which point the transition is live, which is the only window in which this subject exists.
	# `wall_transition_delay` is the wall's OWN multiplier and no other suite reads the global copy
	# (every one builds its own PlayerSettings fixture), so shrinking it here bounds the whole
	# mid-flight half to a couple of frames.
	# Every PlayerSettings setter writes user://settings.tres, so the real file is parked first --
	# the same reason the C3 test above does it.
	backup_real_settings()
	var real_transition_delay : float = SettingsManager.settings.wall_transition_delay
	SettingsManager.settings.wall_transition_delay = 0.001
	main._focus_picture(&"map")
	check(main._active_transition != null and main._active_transition.is_active,
			"sanity: a real WallTransition is genuinely in flight, so there is something to retarget")

	var tall := Vector2i(1600, 900)
	viewport.size = tall
	check(main._active_transition != null and main._active_transition.is_active,
			"the resize RETARGETED the live transition -- it was neither cancelled nor restarted")
	var retargeted_window := main._active_transition._window_size if main._active_transition 			else Vector2.ZERO
	check(retargeted_window.is_equal_approx(Vector2(tall)),
			"the live transition now samples the NEW window: retarget()'s one and only call site",
			str(retargeted_window))

	await main.wall.transition_landed
	await get_tree().process_frame   # _focus_picture finishes its own body after that emit
	SettingsManager.settings.wall_transition_delay = real_transition_delay
	restore_real_settings()
	check(main._current_focus == &"map",
			"it still landed on the ORIGINAL destination -- the geometry changed, the target did not",
			str(main._current_focus))

	main.queue_free()
	viewport.queue_free()
