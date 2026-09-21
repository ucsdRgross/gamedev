extends TestSuite
# res://Tests/Wall/test_wall_focus.gd

# WALL FOCUS: FocusStack -- the Back/Forward history for the picture wall, ids only -- plus the
# overlay's Back/Forward enablement, which is stack semantics wearing UI, and the wiring tests
# that prove a REAL Main's live stack survives an unlock, a resize and a quit.

# Rows that need popups are out of scope for this suite.

# Every row here is BEHAVIOR: a player-visible navigation contract, not an internal storage detail.

# FocusStack's API is exactly visit/back/forward/can_back/can_forward -- there is no depth or
# contents accessor, on purpose. A test that needs the stack's SHAPE walks it through that API:
# it knows what it last visited, and repeated back() reads everything below, in order, until &"".

const WALL_OVERLAY_SCENE := preload("res://UI/Wall/wall_overlay.tscn")
const MAIN_SCENE := preload("res://Levels/main.tscn")

func suite_name() -> String:
	return "WALL FOCUS"

func _ready() -> void:
	TestLog.line("============ WALL FOCUS TEST PASS ============")
	backup_real_settings()
# Navigation timing checks must not depend on the player's tuning.
	use_own_settings()
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
	behavior_section("BACK'S BUTTON AGREES WITH BACK'S KEY IN WALL VIEW (GAP-020=a)")
	test_back_button_is_enabled_in_wall_view_whenever_the_key_works()
	behavior_section("THE OVERLAY NEVER TAKES KEYBOARD FOCUS")
	test_overlay_buttons_cannot_take_focus()
	behavior_section("WALL STATE DOES NOT SURVIVE A QUIT (S30, F13)")
	test_wall_state_does_not_survive_a_quit()
	behavior_section("UNLOCK MID-SESSION (S38, F12)")
	await test_unlock_reaction_leaves_the_real_focus_stack_valid()
	behavior_section("LOST-RUN BEHAVIOUR (S32, L12, Q157)")
	test_lost_run_leaves_map_and_game_pictures_unchanged()
	behavior_section("FOCUS/TRANSITION SIGNALS (A4, PICTURE_WALL.md, NAMES.md)")
	await test_focus_and_transition_signals_fire_during_real_navigation()
	behavior_section("RESIZE REACHES THE WALL (M1, PICTURE_WALL.md, S17, T11 wiring)")
	await test_a_real_resize_reaches_the_wall()
	behavior_section("KEYBOARD BACK RETRACES (M2, PICTURE_WALL.md, Q65=a, I5)")
	await test_escape_goes_to_wall_view_while_back_retraces_the_stack()
	behavior_section("THE wall_* ACTIONS REACH MAIN (M3, PICTURE_WALL.md, I6, I7)")
	await test_the_wall_actions_drive_a_real_navigate_back_forward_wall_cycle()
	behavior_section("A PUBLISHED ENTRY'S VISUAL IS OWNED BY WHAT SHOWS IT (M7, PICTURE_WALL.md)")
	await test_a_published_info_entry_is_owned_by_whatever_shows_it()
	behavior_section("ONE MOVE AT A TIME (C5, PICTURE_WALL.md, Q56=b, §1.6)")
	await test_a_second_destination_mid_move_is_ignored()
	behavior_section("INPUT IS INERT MID-MOVE, AND UNLOCKS EARLY (C5/S16, I12/Q96=a, C13/Q58)")
	await test_input_is_inert_during_a_move_and_unlocks_before_the_tween_ends()
	behavior_section("A FRAME IS A WALL-VIEW AFFORDANCE, NEVER SEEN WHILE FOCUSED")
	await test_no_picture_draws_a_frame_while_one_is_focused()
	await test_a_focused_picture_covers_the_window_at_every_aspect()
	restore_real_settings()
	finish()

# Visit a, b, c -> back() retraces to b, the picture visited just before c.
func test_back_retraces_visit_order() -> void:
	var fs := FocusStack.new()
	fs.visit(&"a")
	fs.visit(&"b")
	fs.visit(&"c")
	var result := fs.back()
	check(result == &"b", "back() after visiting a, b, c returns b", str(result))

# Visiting an id already in the stack MOVES it to the top instead of appending a second entry. The
# resulting stack is read back out through the fixed API, since no inspection method exists.
func test_revisit_moves_to_top() -> void:
	var fs := FocusStack.new()
	fs.visit(&"a")
	fs.visit(&"b")
	fs.visit(&"c")
# b is already in the stack -> moves, does not duplicate.
	fs.visit(&"b")
	var order := _walk_stack(fs, &"b")
	var expected : Array[StringName] = [&"a", &"c", &"b"]
	check(order == expected, "stack reads a, c, b bottom to top after the revisit", str(order))
	check(order.size() == 3, "depth is 3 -- the revisit moved, it did not append",
			str(order.size()))

# Depth never exceeds the number of DISTINCT pictures visited, however many times any one is
# revisited: a structural consequence of "revisit moves" -- an id can never occupy two slots.

# That makes the invariant order-independent, so one shuffled pass covering every id several times
# is a full check of it, not a sample.
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

# back() then forward() returns to the picture that was just left.
func test_forward_returns_the_picture_just_left() -> void:
	var fs := FocusStack.new()
	fs.visit(&"a")
	fs.visit(&"b")
	fs.back()
	var result := fs.forward()
	check(result == &"b", "forward() after back() returns the picture just left", str(result))

# A new visit clears whatever was available to redo, exactly as a browser does.
func test_new_visit_clears_forward() -> void:
	var fs := FocusStack.new()
	fs.visit(&"a")
	fs.visit(&"b")
	fs.back()
	check(fs.can_forward(), "can_forward() is true immediately after a back()")
	fs.visit(&"c")
	check(not fs.can_forward(), "a new visit clears the forward list")

# back() on a stack nothing has ever been visited on returns &"". The CALLER's contract, not
# FocusStack's, is to treat that as "go to wall view" -- FocusStack itself never represents wall
# view as an entry at all.
func test_back_on_empty_stack() -> void:
	var fs := FocusStack.new()
	check(not fs.can_back(), "can_back() is false on a fresh stack")
	var result := fs.back()
	check(result == &"", "back() on an empty stack returns &\"\"", str(result))

# Wall view is never a stack entry. "Enter wall view" is deliberately NOT a call on FocusStack --
# the caller just stops calling visit() while it is shown, so a later back() skips straight over
# where wall view would have been.
func test_wall_view_is_never_an_entry() -> void:
	var fs := FocusStack.new()
	fs.visit(&"a")
# ... wall view is shown here, by the caller, off FocusStack entirely ...
	fs.visit(&"b")
	var result := fs.back()
	check(result == &"a", "back() after wall view lands on a, not on a wall-view entry",
			str(result))

# Back VISIBLY disables itself -- `Button.disabled`, not merely a press that silently does nothing
# -- with an empty stack, and re-enables once there is something to go back to, proving refresh()
# actually recomputes rather than being stuck.
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

# Forward is visibly disabled with nothing ahead (fresh visit, no back() taken yet), and re-enables
# once a back() leaves something to redo.
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

# Reads a FocusStack's contents, bottom (oldest) to top (current), through the fixed API alone.
# `known_top` is whatever the caller last passed to visit(): back() only ever reports the entry
# BELOW the current one, so the top has to be supplied rather than discovered.

# Consuming: every entry this reads ends up in the stack's forward list.
func _walk_stack(fs: FocusStack, known_top: StringName) -> Array[StringName]:
	var order : Array[StringName] = [known_top]
	var step := fs.back()
	while step != &"":
		order.append(step)
		step = fs.back()
	order.reverse()
	return order

# ------------------------------------------------------------------ F13 (S30)

# Wall state does NOT survive a quit -- every launch opens on the start-menu picture, and nothing
# about "which picture you were on" is ever written to disk.

# ⚠ "Assert it did NOT happen" trap: a relaunch that never wrote anything would ALSO pass a check
# that only looks for absence. All three halves below are asserted so each can actually go red.

# 1. THE WRITE PATH RAN -- session one visits real pictures and `can_back()` genuinely flips true,
# so this exercises a stack with real history, not an empty one that trivially "resets".

# 2. A second, INDEPENDENT `Wall.cold_launch_focus_stack()` starts at start_menu with nothing to go
# back to, and further mutating session one afterward still never reaches it.

# 3. NO field on `PlayerProfile` or `PlayerSettings` even NAMES a current-picture concept -- a
# structural scan of both resources' exported property lists, not a guess about what was not added.
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

# Further mutation of session one...
	session_one.visit(&"start_menu")
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

# An unlock mid-session leaves the FocusStack VALID. This row is a claim about PRODUCTION WIRING,
# not about `FocusStack`'s arithmetic, which the isolated tests above already cover.

# ⚠ A disconnected `FocusStack.new()` that `Wall.apply_layout()` never touches cannot go red for a
# wiring bug that corrupts the REAL stack -- only for a bug in `FocusStack` itself.

# So the FULL REAL CHAIN runs end to end on a REAL `Main`: `ProfileManager.unlock(&"book")` (saves
# immediately, emits `picture_unlocked`) -> `Main._ready()`'s own connection -> the real
# `_repack_wall()` -> the real, live `_focus_stack`. Nothing is called directly as a substitute.

# `book` is `unlocked_by_default = false` in `Wall.initial_layout()` (ASSUMPTIONS.md), so it is a
# picture genuinely never built before this test unlocks it -- which also exercises "no reveal
# ceremony: the picture is simply there next time".

# `ProfileManager` is a real, shared autoload, parked and swapped exactly as `test_wall_profile.gd`
# does, so unlocking `book` here for real cannot leak into, or be polluted by, whichever profile
# state a concurrently-running suite or the real player has.

# `ProfileManager.unlock()` and `Main._repack_wall()` are both fully synchronous, so park ->
# unlock -> repack -> restore runs as one uninterrupted block with no window to interleave.
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
# Wall._ready() (inside Main._ready(), just run by add_child above) sets get_tree().paused = true
# GLOBALLY -- undone immediately: ~38 OTHER suites run concurrently, and a global pause with
# nothing to clear it hangs the whole run.
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

# An unlock re-pack changes every unfocused picture's wall-view FOOTPRINT, so its render target
# must follow, exactly as `_on_window_resized()` does. Without it an unlock leaves every
# already-built picture rendering at the resolution its PREVIOUS footprint asked for.

# The focused picture is excluded: it renders at full design size and focus() owns that.
	var checked_any := false
	for id : StringName in main._pictures:
		var wp : WallPicture = main._pictures[id]
		if wp.is_focused: continue
		checked_any = true
		var want := main._footprint(main._rects[id])
		var floor_px : int = SettingsManager.settings.wall_view_min_texture_px
		var want_px := Vector2i(maxi(int(want.x), floor_px), maxi(int(want.y), floor_px))
		check(wp.viewport.size == want_px,
				"%s's render target followed the unlock re-pack's new footprint" % id,
				"viewport=%s want=%s" % [wp.viewport.size, want_px])
	check(checked_any,
			"sanity: at least one unfocused picture was actually checked -- an all-focused wall "
			+ "would make the loop above assert nothing")

# Back must retrace the SAME three real ids in the SAME order as before the unlock, COMPLETELY
# UNAFFECTED by every picture's rect being freshly rebuilt underneath it and a brand-new picture
# appearing, because _repack_wall() never touches _focus_stack -- it only READS it.
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

# A lost run leaves BOTH the map picture's screen and the game picture's screen UNCHANGED --
# neither rebuilt, freed, nor detached. It stays on the wall and shows its own empty state.

# `Main._on_run_lost()` is the exact method a real GameView's `run_lost` signal fires, called
# DIRECTLY here so the real method runs against a real Main without needing a full, playable show
# to reach it.

# A bare `Node` stands in for the game-over screen `attach_screen()` would hold, never a mock of
# GameView's own behaviour: `_on_run_lost()` never reads anything ABOUT the screen, only whether
# it exists.

# `backup_real_save(suite_tag())`/`restore_real_save(suite_tag())` park the real
# `user://run_save/run.tres` for the call's duration, because `_on_run_lost()` calls
# `RunManager.clear_save()`, which deletes that file.

# The park is tight around ONE synchronous call, so no concurrently-running sibling suite's own
# disk-save work can interleave inside the exposure window.

# ⚠ "The map is replaced only when a new run starts" is NOT exercised here: `_on_new_run()` ends in
# `await _go_to_wall_view()`, which would hold the park open across a real camera animation, and
# that park is global rather than per-suite. That half rests on code review (ASSUMPTIONS.md).
func test_lost_run_leaves_map_and_game_pictures_unchanged() -> void:
	backup_real_save(suite_tag())
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	get_tree().paused = false

	var game_wp : WallPicture = main._pictures[&"game"]
	var lose_screen_stand_in := Node.new()
	lose_screen_stand_in.name = "LoseScreenStandIn"
# Simulates a real GameView's game-over state.
	game_wp.attach_screen(lose_screen_stand_in)
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

	restore_real_save(suite_tag())
	main.queue_free()

# ------------------------------------------------------------------ A4 (PICTURE_WALL.md, NAMES.md)

# Three of `Wall`'s registered signals -- `focus_changed`, `transition_started`,
# `transition_landed` -- were named in the registry but never declared or emitted anywhere.

# Real navigation through a REAL `Main` (start_menu -> map, a genuine picture-to-picture
# `WallTransition`, the only case the transition signals apply to, since wall view is never a
# picture id) must fire all three, in the right order, with the right ids.
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

# ------------------------------------------------------------------ M1 (PICTURE_WALL.md, S17)

# The resize path was built and had NO caller: nothing connected `size_changed`, so
# `WallTransition.retarget()` had zero callers and a resize left the whole wall packed for the old
# aspect. This is the WIRING half; the pure geometry half lives in `TestWallTransition`.

# It goes red the moment `Main._ready()`'s
# `get_viewport().size_changed.connect(_on_window_resized)` is removed.

# A REAL `Main` inside its OWN `SubViewport`, because `main._window_size` is read straight off
# `get_viewport()` -- a SubViewport is the only window a test can actually resize without
# disturbing the ~38 suites sharing the real one.

# ⚠ ONE `Main`, held for as few frames as possible, and the mid-flight half runs at a deliberately
# tiny `wall_transition_delay`. A live `Main` puts a real `Map` in the tree, so
# `CardEnvironment.CURRENT` is non-null for as long as it lives, where another suite can see it.

# Held across a full-length transition, that window was wide enough for `TestOutline` to build a
# PREVIEW `CardVisual` inside it and take `CardVisual._ready()`'s no-anchor branch, failing a
# DIFFERENT suite with a Nil `global_position` ([[tests-that-prove-nothing]] trap 8).
func test_a_real_resize_reaches_the_wall() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var main : Main = MAIN_SCENE.instantiate()
	viewport.add_child(main)
# Undoes Wall._ready()'s GLOBAL pause, for the reason the unlock test above records.
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
# The player-visible claim, asserted directly rather than by re-deriving focused_scale()
# -- at rest the focused picture COVERS the window on both axes, so its frame stays off-screen.
	var covered := focused_rect.size * camera.zoom.x
	check(covered.x >= wide_window.x and covered.y >= wide_window.y,
			"Q27: the focused picture still OVERFILLS the resized window on both axes, so its own "
			+ "frame is still off-screen at rest",
			"covers %s of window %s" % [str(covered), str(wide_window)])

# ---- mid-flight: a resize arriving during a transition RETARGETS it and lets it continue -- never
# restarts it, never snaps the camera out from under it. `_focus_picture()` is deliberately NOT
# awaited: it runs synchronously up to its own first `await`, by which point the transition is live.

# `wall_transition_delay` is the wall's OWN multiplier and no other suite reads the global copy, so
# shrinking it here bounds the whole mid-flight half to a couple of frames.

# Every PlayerSettings setter writes user://settings.tres, so the real file is parked first.
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
# _focus_picture finishes its own body after that emit.
	await get_tree().process_frame
	SettingsManager.settings.wall_transition_delay = real_transition_delay
	check(main._current_focus == &"map",
			"it still landed on the ORIGINAL destination -- the geometry changed, the target did not",
			str(main._current_focus))

	main.queue_free()
	viewport.queue_free()

# ------------------------------------------------------------------ M2 (PICTURE_WALL.md)

#THE END-TO-END WIRING PROOF: it fails if `Main._ready()`'s `wall.back_requested.connect(
#_on_back_pressed)` or its `wall_view_entered` twin is removed.

#Two REAL navigations first, so there is genuine history for Back to retrace INTO -- a stack with
#nothing behind it bottoms out at wall view legitimately (the empty-stack fall-through), which is
#what would make the retrace claim indistinguishable from the Escape one.

#⚠ One `Main`, held for as few frames as possible, at a tiny `wall_transition_delay` -- see
#`test_a_real_resize_reaches_the_wall()` above for why that matters.

# `wall_back` retraces the stack one step; Escape zooms out to wall view from any depth.
func test_escape_goes_to_wall_view_while_back_retraces_the_stack() -> void:
	var real_transition_delay : float = SettingsManager.settings.wall_transition_delay
	SettingsManager.settings.wall_transition_delay = 0.001
#Every navigation now also waits for the sidebar to slide out and back in, and the bounded waits
#below are a frame budget, not a clock -- so that duration is stubbed alongside the travel's.
	var real_slide : float = SettingsManager.settings.container_slide_duration
	SettingsManager.settings.container_slide_duration = 0.001

	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
#Undoes Wall._ready()'s GLOBAL pause, for the reason the unlock test above records.
	get_tree().paused = false
#Cold launch already visited start_menu. Two real navigations on top of it.
	await main._focus_picture(&"map")
	await main._focus_picture(&"deck")
	check(main._current_focus == &"deck",
			"sanity: two real navigations landed, so Back has somewhere to retrace TO",
			str(main._current_focus))
	check(main._focus_stack.can_back(), "sanity: the real stack reports history behind deck")

	var back := InputEventAction.new()
	back.action = &"wall_back"
	back.pressed = true
	main.wall._unhandled_input(back)
#A BOUNDED wait, never `await focus_changed`: the emit runs `_on_back_pressed()` synchronously up
#to its own first await, so a signal await here would deadlock outright if that handler ever stopped
#suspending. 30 frames is far more than the 0.001 s clock above needs.
	for _i : int in range(30):
		if main._current_focus == &"map": break
		await get_tree().process_frame

	check(main._current_focus == &"map",
			"Q65=a: Back retraced ONE step, to the picture visited before deck",
			str(main._current_focus))

	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	main.wall._unhandled_input(escape)
	for _i : int in range(30):
		if main._current_focus == &"": break
		await get_tree().process_frame

	check(main._current_focus == &"",
			"the owner's ruling: Escape zooms out to WALL VIEW instead, from whatever depth",
			str(main._current_focus))

	main.queue_free()
	SettingsManager.settings.wall_transition_delay = real_transition_delay
	SettingsManager.settings.container_slide_duration = real_slide

# ------------------------------------------------------------------ M3 (PICTURE_WALL.md)

# The four `wall_*` actions had no reader anywhere. `TestWallInput` proves each one now reaches a
# signal; this proves the signals reach `Main` and actually MOVE the player, run as one journey on
# one real `Main` rather than four disconnected assertions.

# Goes red if any of `Main._ready()`'s `back_requested` / `forward_requested` /
# `info_toggle_requested` / `wall_view_entered` connections is removed.

# ⚠ One `Main`, tiny `wall_transition_delay`, bounded frame waits -- see
# `test_a_real_resize_reaches_the_wall()` above for why all three matter here.
func test_the_wall_actions_drive_a_real_navigate_back_forward_wall_cycle() -> void:
	var real_transition_delay : float = SettingsManager.settings.wall_transition_delay
	SettingsManager.settings.wall_transition_delay = 0.001
#Every navigation now also waits for the sidebar to slide out and back in, and the bounded waits
#below are a frame budget, not a clock -- so that duration is stubbed alongside the travel's.
	var real_slide : float = SettingsManager.settings.container_slide_duration
	SettingsManager.settings.container_slide_duration = 0.001

	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
# Undoes Wall._ready()'s GLOBAL pause, for the reason the unlock test above records.
	get_tree().paused = false

	await main._focus_picture(&"map")
	check(main._current_focus == &"map",
			"sanity: one real navigation landed, so Back has somewhere to go", str(main._current_focus))

	await _feed_wall_action(main, &"wall_back", func() -> bool: return main._current_focus == &"start_menu")
	check(main._current_focus == &"start_menu",
			"wall_back (L1/LB) retraced to start_menu -- the controller had no Back at all",
			str(main._current_focus))

	await _feed_wall_action(main, &"wall_forward", func() -> bool: return main._current_focus == &"map")
	check(main._current_focus == &"map",
			"wall_forward (R1/RB) went forward again, to the picture just left -- the controller "
			+ "had no Forward at all", str(main._current_focus))

	await _feed_wall_action(main, &"wall_overview", func() -> bool: return main._current_focus == &"")
	check(main._current_focus == &"",
			"wall_overview (Tab / Select-View) left the picture for wall view -- Tab had no reader",
			str(main._current_focus))

	main.queue_free()
	SettingsManager.settings.wall_transition_delay = real_transition_delay
	SettingsManager.settings.container_slide_duration = real_slide

# Feeds one action through the REAL `Wall._unhandled_input()` and waits, BOUNDED, for `settled` to
# report the move finished. Never `await` on a signal: the emit runs Main's handler synchronously
# up to its own first await, so a signal await here would deadlock if a handler stopped suspending.

# 60 frames is far more than the 0.001 s clock above needs.
func _feed_wall_action(main: Main, action: StringName, settled: Callable) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	main.wall._unhandled_input(event)
	for _i : int in range(60):
		if settled.call(): return
		await get_tree().process_frame

# ------------------------------------------------------------------ C5 (PICTURE_WALL.md)

# `Main._focus_picture()` news a `WallTransition` PER CALL, so `request()`'s own `is_active` guard
# could never see the other one: two clicks in wall view ran two tweens on one `Camera2D`, both
# landed, and both called `focus()`, leaving TWO `PROCESS_MODE_ALWAYS` screen roots.

# "Exactly one focused picture" is the invariant this gate exists to protect, and its input rule is
# that a new destination is ignored until the in-flight move finishes.

# Both paths that drive the shared camera are pressed mid-move, because `_go_to_wall_view()` racing
# an enter fights it for position and zoom exactly as two enters did.

# ⚠ Every earlier attempt held a real `Main` across a transition, and a real `Main` puts a real
# `Map` in the tree, which is a `CardEnvironment`. While `CardEnvironment.CURRENT` was set, another
# suite's preview `CardVisual` died on a Nil `global_position` (trap 8); that crash is now guarded.

# The strongest assertion here is the ALWAYS count, not `_current_focus`: the manual red-proof
# reported `focused=[&"deck", &"game"]`, TWO focused pictures at once, which a single-id check
# would have missed entirely.
func test_a_second_destination_mid_move_is_ignored() -> void:
	var real_transition_delay : float = SettingsManager.settings.wall_transition_delay
	SettingsManager.settings.wall_transition_delay = 0.001
#Every navigation now also waits for the sidebar to slide out and back in, and the bounded waits
#below are a frame budget, not a clock -- so that duration is stubbed alongside the travel's.
	var real_slide : float = SettingsManager.settings.container_slide_duration
	SettingsManager.settings.container_slide_duration = 0.001

	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
# Undoes Wall._ready()'s GLOBAL pause, for the reason the unlock test above records.
	get_tree().paused = false

# One REAL move, deliberately not awaited: it runs to its own first await, by which point the
# transition is live -- the only window in which a second request can race it.
	main._focus_picture(&"map")
	check(main._active_transition != null and main._active_transition.is_active,
			"sanity: a real transition is in flight, so there is a move to interrupt")

# A second click on a different picture.
	main._focus_picture(&"deck")
# ...and the OTHER camera-driving path, for good measure.
	main._go_to_wall_view()
	check(main._transition_dest_id == &"map",
			"Q56=b: the in-flight transition still targets its ORIGINAL destination -- the second "
			+ "request was ignored, not queued and not retargeted", str(main._transition_dest_id))

	for _i : int in range(60):
		if main._current_focus == &"map": break
		await get_tree().process_frame
	check(main._current_focus == &"map",
			"it lands on the picture the FIRST request asked for", str(main._current_focus))

	var focused : Array[StringName] = []
	var always : Array[StringName] = []
	for id : StringName in main._pictures:
		var wp : WallPicture = main._pictures[id]
		if wp.is_focused: focused.append(id)
		if wp.screen_root and wp.screen_root.process_mode == Node.PROCESS_MODE_ALWAYS:
			always.append(id)
	check(focused.size() == 1,
			"§1.6: EXACTLY ONE picture is focused after the race -- two concurrent transitions used "
			+ "to leave two", str(focused))
	check(always.size() <= 1,
			"...and at most one live screen root is PROCESS_MODE_ALWAYS, which is the invariant "
			+ "the Phase-3 gate exists to protect", str(always))

	main.queue_free()
	SettingsManager.settings.wall_transition_delay = real_transition_delay
	SettingsManager.settings.container_slide_duration = real_slide

# ------------------------------------------------------------------ C5's other half (S16, C13)

# `input_unlocked` -- the signal the early unlock exists for -- had no consumer, and "during a
# transition input is inert" had no implementation either. The two are one defect: with nothing
# making input inert, there was nothing for an early unlock to unlock.

# The contract that killed: allow input once the picture is unpaused, which should be right before
# the end of the transition, not at the end.

# The load-bearing assertion is the THIRD one. "Locked, then unlocked afterwards" would also be
# satisfied by a lock that simply cleared on landing; only "it was still active when the unlock
# fired" distinguishes an early unlock from an ordinary one.
func test_input_is_inert_during_a_move_and_unlocks_before_the_tween_ends() -> void:
	var real_transition_delay : float = SettingsManager.settings.wall_transition_delay
	SettingsManager.settings.wall_transition_delay = 0.001
#Every navigation now also waits for the sidebar to slide out and back in, and the bounded waits
#below are a frame budget, not a clock -- so that duration is stubbed alongside the travel's.
	var real_slide : float = SettingsManager.settings.container_slide_duration
	SettingsManager.settings.container_slide_duration = 0.001

	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
# Undoes Wall._ready()'s GLOBAL pause, for the reason the unlock test above records.
	get_tree().paused = false
	check(not main.wall.input_locked, "sanity: the wall answers input at rest")

	main._focus_picture(&"map")
	var transition : WallTransition = main._active_transition
	check(transition != null and transition.is_active, "sanity: a real transition is in flight")
	check(main.wall.input_locked,
			"I12/Q96=a: input goes INERT the moment a move starts -- nothing made it inert before")

# Boxed -- GDScript lambdas capture locals BY VALUE.
	var unlocked_mid_flight : Array[bool] = [false]
	var unlock_fired : Array[bool] = [false]
# ⚠ The lambda must NOT capture `transition`. The connection is stored ON the transition, so a
# captured reference back to it is a RefCounted CYCLE that never frees -- it took this suite from
# 4 leaked ObjectDB instances at exit to 17 ([[tests-that-prove-nothing]] trap 4).

# Read back off `main` instead: `Main` is a Node, so the reference runs transition -> Callable ->
# Main and never returns.
	transition.input_unlocked.connect(func() -> void:
			unlock_fired[0] = true
			unlocked_mid_flight[0] = main._active_transition != null 					and main._active_transition.is_active)

# A wall-level action fed while locked must reach nothing at all.
	var reached : Array[bool] = [false]
	main.wall.wall_view_entered.connect(func() -> void: reached[0] = true)
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	main.wall._unhandled_input(escape)
	check(not reached[0], "...and a wall action pressed while locked reaches nothing")

	for _i : int in range(60):
		if main._current_focus == &"map": break
		await get_tree().process_frame

	check(unlock_fired[0],
			"the transition's own input_unlocked actually fired -- an unlock nobody emits would "
			+ "make the next check vacuous")
	check(unlocked_mid_flight[0],
			"C13/Q58: it fired while the transition was STILL ACTIVE, i.e. before the tween ended "
			+ "-- which is the whole reason S16 exists")
	check(not main.wall.input_locked, "and the wall answers input again once the move has landed")

	main.queue_free()
	SettingsManager.settings.wall_transition_delay = real_transition_delay
	SettingsManager.settings.container_slide_duration = real_slide

# ------------------------------------------------------------------ overlay focus

# The WALL owns arrow selection and `ui_accept`, read in its own `_unhandled_input`. A `Control`
# that holds GUI focus consumes `ui_up/down/left/right` and `ui_accept` BEFORE `_unhandled_input`
# ever runs.

# So with Godot's default `FOCUS_ALL` on these Buttons, clicking any one of them with the mouse
# silently killed wall-view arrow selection and Enter-to-enter for the rest of the session.

# The overlay's controls are mouse/touch affordances and every one also has its own `wall_*`
# InputMap action for the keyboard, so none of them needs focus.

# Asserted BEHAVIOURALLY -- grab_focus() is called and must not take -- rather than by reading the
# property back, which would only re-state the scene file at itself.
func test_overlay_buttons_cannot_take_focus() -> void:
	var overlay : WallOverlay = WALL_OVERLAY_SCENE.instantiate()
	add_child(overlay)
	var names : Array[StringName] = [&"%BackButton", &"%ForwardButton", &"%WallButton"]
	check(names.size() == 3, "sanity: all three overlay controls are covered", str(names.size()))
	for path : StringName in names:
		var button : Button = overlay.get_node(NodePath(path))
# `disabled` alone would refuse focus, so clear it first: this must hold for a button the
# player can actually click, which is the only way the defect was reachable.
		button.disabled = false
		button.grab_focus()
		check(not button.has_focus(),
				"%s cannot take keyboard focus, so it cannot swallow the wall's arrows" % path)
	overlay.queue_free()

# ------------------------------------------------------------------ GAP-020 = (a)

# In wall view Back returns to the picture just left, so the BUTTON must be enabled exactly when
# the KEY does something.

# ⚠ `can_back()` asks "is there something BELOW the current picture" and needs two entries. That is
# the right question only while a picture is focused: in wall view the stack's top IS the
# destination, so one entry is enough.

# The commonest first-minute journey produces exactly one -- cold launch visits start_menu, Escape
# goes to wall view -- and the button was greyed out there while Escape and joypad Back both
# worked, against `Main._ready()`'s promise that the key and the button cannot diverge.
func test_back_button_is_enabled_in_wall_view_whenever_the_key_works() -> void:
	var overlay : WallOverlay = WALL_OVERLAY_SCENE.instantiate()
	add_child(overlay)
	var back_button : Button = overlay.get_node(^"%BackButton")
	var fs := FocusStack.new()
# Exactly the cold-launch stack.
	fs.visit(&"start_menu")

	check(not fs.can_back(),
			"sanity: one entry, so the FOCUSED-picture predicate says Back is unavailable")
	check(fs.current() == &"start_menu",
			"sanity: ...while the stack still sits on the picture wall view was entered from",
			str(fs.current()))

	overlay.refresh(fs, 4, false)
	check(back_button.disabled,
			"focused on that picture, Back is disabled -- there is nothing behind it")
	overlay.refresh(fs, 4, true)
	check(not back_button.disabled,
			"in WALL VIEW the same stack enables Back, because the key would return to start_menu")

# And an empty stack disables it in wall view too -- "enabled in wall view" must not be
# unconditional, or this test would pass for a button that is simply always on.
	var empty := FocusStack.new()
	overlay.refresh(empty, 4, true)
	check(back_button.disabled,
			"...but an EMPTY stack still disables it in wall view -- there is nothing to go back to")
	overlay.queue_free()

# ------------------------------------------------------------------ dropped-entry leak

# `entry.visual` is a NODE that was never added to any tree, so whoever the wall hands it to owns
# it: the container's description panel, which mounts it. It may not be left orphaned in ObjectDB
# for the session.
func test_a_published_info_entry_is_owned_by_whatever_shows_it() -> void:
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
# Concurrency workaround, same as every other Main fixture here.
	get_tree().paused = false

	var visual := Node2D.new()
	var entry := InfoEntry.new()
	entry.title = "Published"
	entry.body = "The container is what shows this."
	entry.visual = visual
	check(is_instance_valid(visual), "sanity: the visual exists before the hover")

	main._on_screen_info_hovered(entry)
	await get_tree().process_frame
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	check(is_instance_valid(visual) and visual.get_parent() == panel.get_node(^"%VisualSlot"),
			"the container's description panel takes the entry's visual")
	main.queue_free()

# ------------------------------------------------------------------ frames while focused

# A frame belongs to the wall, not to a picture the player is inside. It goes out the moment a
# zoom-in lands and comes back as a leave to wall view starts -- before the camera has moved, so
# the wall is whole by the time any of it can be seen.
func test_no_picture_draws_a_frame_while_one_is_focused() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152, 648)
	add_child(viewport)
	var main : Main = MAIN_SCENE.instantiate()
	viewport.add_child(main)
	get_tree().paused = false
	var camera : Camera2D = main.wall.get_node(^"%Camera2D")

	check(main._current_focus == &"start_menu",
			"sanity: cold launch really is a LANDED focus, not wall view -- everything below is "
			+ "about a wall with a picture already on it")
	check(_frames_drawn(main) == 0,
			"cold launch lands focused, so the wall draws no frame at all",
			"%d of %d drawn" % [_frames_drawn(main), main._pictures.size()])

	await main._focus_picture(&"map")
	check(_frames_drawn(main) == 0,
			"a zoom-in that has landed leaves no frame drawn anywhere on the wall",
			"%d of %d drawn" % [_frames_drawn(main), main._pictures.size()])

# A picture-to-picture move is not a switch out to wall view, so the frames stay out for the whole
# travel -- the ONE reading of the rule this suite pins that the words do not spell out.
	var travel_samples := 0
	var travel_frames_drawn := 0
	main._focus_picture(&"deck")
	while main._move_in_flight:
		await get_tree().process_frame
		travel_samples += 1
		travel_frames_drawn += _frames_drawn(main)
	check(travel_samples > 0,
			"sanity: the picture-to-picture move really animated -- a move that never ran would "
			+ "make the check below vacuous",
			"%d frames" % travel_samples)
	check(travel_frames_drawn == 0,
			"no frame is drawn at any frame of a move BETWEEN two pictures",
			"%d frame-draws over %d frames" % [travel_frames_drawn, travel_samples])

# The leave: the frames must already be back before the camera has gone anywhere, or the first
# frames of the zoom-out show a wall with holes in it.
	var rest_pose := Vector3(camera.position.x, camera.position.y, camera.zoom.x)
	var moved_samples := 0
	var moved_without_frames := 0
	main._go_to_wall_view()
	while main._move_in_flight:
		await get_tree().process_frame
		if Vector3(camera.position.x, camera.position.y, camera.zoom.x) == rest_pose: continue
		moved_samples += 1
		if _frames_drawn(main) < main._pictures.size(): moved_without_frames += 1
	check(moved_samples > 0,
			"sanity: the camera really moved during the leave",
			"%d moved frames" % moved_samples)
	check(moved_without_frames == 0,
			"every frame of the zoom-out in which the camera had moved already had the whole "
			+ "wall's frames back",
			"%d of %d moved frames were short" % [moved_without_frames, moved_samples])
	check(_frames_drawn(main) == main._pictures.size(),
			"in wall view every picture draws its frame again",
			"%d of %d drawn" % [_frames_drawn(main), main._pictures.size()])

# The round trip back in, so nothing is left in a half-applied state by a leave and a re-enter.
	await main._focus_picture(&"map")
	check(_frames_drawn(main) == 0,
			"re-entering a picture from wall view takes the frames out again on landing",
			"%d of %d drawn" % [_frames_drawn(main), main._pictures.size()])
	main._go_to_wall_view()
	main._focus_picture(&"deck")
	while main._move_in_flight:
		await get_tree().process_frame
	check(_frames_drawn(main) == main._pictures.size(),
			"a focus requested mid-leave is ignored, and the leave still ends with every frame "
			+ "back -- never half of them",
			"%d of %d drawn" % [_frames_drawn(main), main._pictures.size()])

	main.queue_free()
	await get_tree().process_frame
	viewport.queue_free()

# A focused picture overfills its window on every axis, so no frame band can reach the window at
# rest whatever shape the window is. The frames being undrawn is the other half of the same answer.
func test_a_focused_picture_covers_the_window_at_every_aspect() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152, 648)
	add_child(viewport)
	var main : Main = MAIN_SCENE.instantiate()
	viewport.add_child(main)
	get_tree().paused = false
	await main._focus_picture(&"map")

	for size : Vector2i in [Vector2i(1152, 864), Vector2i(1512, 648), Vector2i(648, 900),
			Vector2i(1152, 648)]:
		viewport.size = size
		await get_tree().process_frame
		main._on_window_resized()
		await get_tree().process_frame
		var camera : Camera2D = main.wall.get_node(^"%Camera2D")
		var window := Vector2(size)
		var zoom := camera.zoom.x
		var rect : PictureRect = main._rects[&"map"]
		var drawn := Rect2((rect.centre - camera.position) * zoom + window / 2.0
				- rect.size * zoom / 2.0, rect.size * zoom)
		check(drawn.position.x <= 0.5 and drawn.position.y <= 0.5
				and drawn.end.x >= window.x - 0.5 and drawn.end.y >= window.y - 0.5,
				"at %dx%d the focused picture still covers the window edge to edge" % [size.x,
				size.y], "picture %s in window %s" % [drawn, window])
		check(_frames_drawn(main) == 0,
				"...and at %dx%d no frame is drawn either" % [size.x, size.y],
				"%d of %d drawn" % [_frames_drawn(main), main._pictures.size()])

	main.queue_free()
	await get_tree().process_frame
	viewport.queue_free()

## How many of `main`'s pictures are drawing their frame right now.
func _frames_drawn(main: Main) -> int:
	var drawn := 0
	for id : StringName in main._pictures:
		var frame : NinePatchRect = main._pictures[id].get_node(^"%Frame")
		if frame.visible: drawn += 1
	return drawn
