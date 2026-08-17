extends TestSuite
# res://Tests/Wall/test_wall_focus.gd
# ==============================================================================
# WALL FOCUS (S5): FocusStack -- the Back/Forward history for the picture wall, ids only.
# PLAN.md §1.4; TEST_PLAN.md §2, F1-F7. Plus §6b's overlay group (S35): F8, F9 -- they live here,
# not in a new suite, because they are stack semantics (FocusStack.can_back/can_forward) wearing UI
# (WallOverlay.refresh). Plus F13 (S30): wall state does not survive a quit. NOT F10-F12: those
# need popups and unlock (S38/S39), still out of scope.
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
const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")

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
	test_unlock_mid_session_leaves_the_stack_valid()
	finish()

## ⚠ Same isolated-SubViewport reasoning `TestWallInput._build_wall()` documents: `Wall._ready()`
## calls `get_viewport().set_input_as_handled()` from `_unhandled_input()`, which would mark the
## SHARED root viewport (every other concurrently-running suite's own real input) if `wall` lived
## there directly. This suite's own F12 test never dispatches input, but the fixture is copied
## verbatim rather than re-derived, so the same guarantee holds if this file ever grows a test that
## does.
func _build_focus_test_wall() -> Wall:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var wall : Wall = WALL_SCENE.instantiate()
	viewport.add_child(wall)
	get_tree().paused = false
	return wall

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

## F12 (K4, Q156=a): an unlock mid-session leaves the FocusStack valid. Visits three pictures
## (a, b, c), then re-packs exactly as `Main._repack_wall()` does in production once a fourth ("d")
## unlocks: `WallPacker.pack()` over the WIDER unlocked set, a fresh `WallPicture.build()` for the
## picture that never existed before (K2: "no reveal ceremony"), and `Wall.apply_layout()` to
## reposition the three that already did -- `animate=false` (K4's own scenario: "if they are
## inside a picture, the wall re-packs silently"). Every picture's position AND size changes
## (GAP-010's unconditional rebalancing spreads four pictures differently than three) and a brand
## new node gets built, and NONE of it should be visible to the stack: Back must still retrace the
## exact same three ids in the exact same order, because it was never handed a rect or a node
## reference to begin with (§1.4) -- only ids, which the re-pack never touches.
func test_unlock_mid_session_leaves_the_stack_valid() -> void:
	var fs := FocusStack.new()
	fs.visit(&"a")
	fs.visit(&"b")
	fs.visit(&"c")

	var layout := WallLayout.new()
	layout.home_id = &"a"
	var entries : Array[PictureEntry] = []
	for id : StringName in [&"a", &"b", &"c", &"d"]:
		var e := PictureEntry.new()
		e.id = id
		entries.append(e)
	layout.pictures = entries
	var by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in entries: by_id[e.id] = e

	var wall := _build_focus_test_wall()
	var pictures_root : Node = wall.get_node(^"%Pictures")
	var viewports : Node = wall.get_node(^"%Viewports")
	var built : Array[WallPicture] = []
	# "d" starts locked -- only a, b, c are packed at first, matching the three pictures already
	# visited above.
	var rects_before := WallPacker.pack(layout, [&"a", &"b", &"c"], 1.6)
	for rect : PictureRect in rects_before:
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		wp.build(rect, by_id[rect.id], viewports)
		built.append(wp)
	check(built.size() == 3,
			"sanity: all three already-visited pictures were packed before the unlock",
			str(built.size()))

	# "d" unlocks mid-session -- re-pack with all four ids now unlocked.
	var rects_after := WallPacker.pack(layout, [&"a", &"b", &"c", &"d"], 1.6)
	var rects_by_id : Dictionary[StringName, PictureRect] = {}
	for rect : PictureRect in rects_after: rects_by_id[rect.id] = rect
	var d_wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	pictures_root.add_child(d_wp)
	d_wp.build(rects_by_id[&"d"], by_id[&"d"], viewports)
	built.append(d_wp)
	wall.apply_layout(rects_by_id, false)

	check(built.size() == 4, "the newly-unlocked fourth picture was built", str(built.size()))
	for wp : WallPicture in built:
		check(wp.rect.centre.is_equal_approx(rects_by_id[wp.rect.id].centre),
				"%s ended the re-pack at its freshly packed position" % wp.rect.id,
				"got=%s want=%s" % [wp.rect.centre, rects_by_id[wp.rect.id].centre])

	# Back retraces c -> b -> a -> "" -- the SAME order as before the unlock, completely unaffected
	# by every picture's own position/size changing and a brand new node appearing.
	check(fs.back() == &"b", "Back still lands on b, exactly as it would have before the unlock")
	check(fs.back() == &"a", "...then a...")
	check(fs.back() == &"", "...then nothing left, same as any other exhausted stack")

	for wp : WallPicture in built:
		if is_instance_valid(wp): wp.teardown()
	if wall and is_instance_valid(wall): wall.get_parent().queue_free()
