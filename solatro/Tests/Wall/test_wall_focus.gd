extends TestSuite
# res://Tests/Wall/test_wall_focus.gd
# ==============================================================================
# WALL FOCUS (S5): FocusStack -- the Back/Forward history for the picture wall, ids only.
# PLAN.md §1.4; TEST_PLAN.md §2, F1-F7. Plus §6b's overlay group (S35): F8, F9 -- they live here,
# not in a new suite, because they are stack semantics (FocusStack.can_back/can_forward) wearing UI
# (WallOverlay.refresh). NOT F10-F13: those need popups and unlock, Phase 7, out of scope.
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
