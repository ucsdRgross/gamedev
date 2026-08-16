class_name Wall
extends Node2D
## The picture-wall shell root — owns the camera, the pictures and (from S35) the overlay
## (PLAN.md §1.6, NAMES.md). S9 skeleton only for construction/pause; S36 adds wall-view framing
## (G9), clamped pan (G10) and selection (F10-F12) over whatever pictures already exist under
## %Pictures -- population from a real WallLayout is still a later (Phase 7) step, same as every
## existing Wall-render test (TestWallRender, TestWallPause) already builds its own fixture
## pictures externally rather than through this class.

## Pauses the whole tree once, at construction, and NEVER clears it (§1.6, `QR6`=a) — the wall's
## own root and `%Camera2D` are `PROCESS_MODE_ALWAYS` so they keep running regardless, and each
## screen opts back in individually via its own process mode (S12).
func _ready() -> void:
	get_tree().paused = true

## NAMES.md's signal table -- only the ONE this run's steps actually emit is declared here
## (`focus_changed`/`transition_started`/`transition_landed` are a later integration step's job,
## same "don't build what nothing tests yet" boundary S14-S18/S36 already drew elsewhere).
## S21 (Q65=a): "Back at the bottom of the stack goes to wall view" -- fired the instant Back is
## accepted with nothing behind it (or with a focused screen releasing Back to the wall at all).
signal wall_view_entered

## S19/S21 (Q100=a): the wall reads input in `_unhandled_input` ONLY, so a focused screen's own
## Controls/`_unhandled_input` always get FIRST REFUSAL -- the same pattern
## `world_map_controller.gd:217` already uses. Routes to the focused picture via `WallInput.route()`
## first; if that picture's OWN viewport marks the event handled, the wall does nothing more (I3).
## Q103=a/Q115=a: arrow-key SELECTION only ever runs with NO picture focused (wall view) -- "the
## wall never listens while a screen is focused" (I14). `ui_cancel` (Back) and `wall_jump_N` are
## the only wall-level actions still meaningful either way.
func _unhandled_input(event: InputEvent) -> void:
	var focused := _focused_picture()
	if focused:
		WallInput.route(event, focused)
		if focused.viewport and focused.viewport.is_input_handled():
			return
	else:
		if event.is_action_pressed(&"ui_up"):
			move_selection(Vector2.UP)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"ui_down"):
			move_selection(Vector2.DOWN)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"ui_left"):
			move_selection(Vector2.LEFT)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"ui_right"):
			move_selection(Vector2.RIGHT)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		wall_view_entered.emit()
		return
	for n : int in range(1, 10):
		if event.is_action_pressed(StringName("wall_jump_%d" % n)):
			_jump_to_index(n - 1)
			get_viewport().set_input_as_handled()
			return

## The one picture currently `is_focused`, or null in wall view (at most one, by construction --
## `focus()`/`unfocus()` are the caller's own responsibility to keep exclusive, same contract
## `WallPicture.focus()`'s own doc comment already states).
func _focused_picture() -> WallPicture:
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp and wp.is_focused: return wp
	return null

## I7 (Q104=a): `wall_jump_N` enters the Nth picture in PLACEMENT order -- GAP-009 deleted "ring";
## the packer's own output order (slot-ascending, home first) is what's left to count by, so this
## reads `%Pictures`' own child order directly rather than re-deriving it. Silently does nothing
## past the last picture -- no "ring order" defines a jump target that does not exist.
func _jump_to_index(index: int) -> void:
	var children := %Pictures.get_children()
	if index < 0 or index >= children.size(): return
	var wp := children[index] as WallPicture
	if wp: wp.focus()

## F11 (Q69=a): exactly one picture is selected in wall view, always -- empty only before the wall
## has any pictures to select. Set by enter_wall_view()/move_selection(), never directly.
var selected_id : StringName = &""

## Q105=b: the selection cursor renders only after the first directional input -- a mouse-only
## session never sees a keyboard cursor. move_selection() is the only thing that latches this true;
## nothing ever clears it back to false (same one-way-latch shape WallTransition's own pause/
## unpause/input-unlock booleans use).
var selection_visible : bool = false

## Every currently packed picture, id -> node, read from %Pictures' own children (each one's
## `rect` was set by WallPicture.build()). Pictures with no rect yet (never built()'ed) are
## skipped -- the same "un-built fixture" shape T9/T10 already rely on elsewhere. Typed (not a bare
## Dictionary) so callers get WallPicture back, not Variant -- warnings-as-errors otherwise rejects
## `.rect`/`.set_selected()` on an inferred Variant.
func _pictures_by_id() -> Dictionary[StringName, WallPicture]:
	var out : Dictionary[StringName, WallPicture] = {}
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp and wp.rect:
			out[wp.rect.id] = wp
	return out

## F10 ("the wall remembers its selected picture... starting at the one you came from") + F11
## ("starting at the one you came from", Q69=a): entering wall view always re-seeds the selection
## to whichever picture the player is coming FROM. A screen's own internal Control focus (F10's
## other half, "every picture remembers its internal focus for the session") needs no code here --
## screen_root nodes are never destroyed/recreated across a wall-view visit (§1.6/§1.8), so Godot's
## own Control focus state already persists on the same node instance (ASSUMPTIONS.md).
func enter_wall_view(from_id: StringName) -> void:
	selected_id = from_id

## Q98=a (I4, TEST_PLAN I5): moves the selection to the geometrically NEAREST OTHER picture whose
## centre lies at least partly in `direction`'s half-plane from the current selection. Q106=a
## (TEST_PLAN I6): wraps -- when nothing lies in that direction at all (the current selection is
## already the extreme one that way), picks whichever picture is MOST OPPOSITE `direction` instead,
## which is exactly "the first" from the far end of that same axis. Also latches
## `selection_visible` true (Q105=b) -- the cursor was invisible until this, the first directional
## input, ever ran.
func move_selection(direction: Vector2) -> void:
	selection_visible = true
	var pictures := _pictures_by_id()
	if pictures.is_empty(): return
	if selected_id == &"" or not pictures.has(selected_id):
		selected_id = pictures.keys()[0]
		return
	var dir := direction.normalized()
	var current : PictureRect = pictures[selected_id].rect
	var best_id := &""
	var best_dist := INF
	var wrap_id := &""
	var wrap_dot := INF
	for id : StringName in pictures:
		if id == selected_id: continue
		var candidate : PictureRect = pictures[id].rect
		var offset : Vector2 = candidate.centre - current.centre
		if offset.is_zero_approx(): continue
		var d := offset.normalized().dot(dir)
		if d > 0.0:
			var dist := offset.length()
			if dist < best_dist:
				best_dist = dist
				best_id = id
		if d < wrap_dot:
			wrap_dot = d
			wrap_id = id
	var new_id := best_id if best_id != &"" else wrap_id
	if new_id == &"": return
	if pictures.has(selected_id): pictures[selected_id].set_selected(false)
	selected_id = new_id
	pictures[selected_id].set_selected(true)

## S36's own done-when: how many pictures currently exist to overview -- the only piece of state
## only the wall itself knows, needed by the overlay's Wall-button visibility (refresh_overlay()).
func picture_count() -> int:
	return %Pictures.get_child_count()

## G9 (Q5=b): wall view's own camera framing -- FILL AND CROP the whole wall's extent (the union of
## every packed picture's frame outer rect) into the window, the SAME larger-of-two-axis-ratios
## formula WallPicture.focused_scale() already uses for a single picture at rest (H3), just applied
## to the wall's whole bounding box instead of one picture's native size. 1.0 (no-op) when nothing
## is packed yet.
func wall_view_zoom(window_size: Vector2) -> float:
	var extent := _wall_extent()
	if extent.size.x <= 0.0 or extent.size.y <= 0.0: return 1.0
	return WallPicture.focused_scale(extent.size, window_size)

## G10: free pan is clamped so the visible window never shows past the wall's own extent ("never
## pans into void"), and collapses to the extent's own centre on whichever axis the extent is
## already smaller than the visible window -- panning is a no-op there, matching G10's "on a large
## screen everything is visible and panning is off." `target` is the camera position a drag/stick
## is requesting; the return value is what the camera should actually be set to.
func clamp_pan(target: Vector2, window_size: Vector2) -> Vector2:
	var extent := _wall_extent()
	if extent.size.x <= 0.0 or extent.size.y <= 0.0: return Vector2.ZERO
	var zoom := wall_view_zoom(window_size)
	var visible := window_size / zoom
	var half_visible := visible * 0.5
	var min_pos := extent.position + half_visible
	var max_pos := extent.position + extent.size - half_visible
	var x := clampf(target.x, min_pos.x, max_pos.x) if min_pos.x <= max_pos.x \
			else extent.get_center().x
	var y := clampf(target.y, min_pos.y, max_pos.y) if min_pos.y <= max_pos.y \
			else extent.get_center().y
	return Vector2(x, y)

## The union of every packed picture's frame outer rect -- the wall's own bounding box in wall
## space. Empty (zero size) when nothing is packed yet.
func _wall_extent() -> Rect2:
	var extent := Rect2()
	var first := true
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp and wp.rect:
			var frame := WallPacker.frame_outer_rect(wp.rect)
			extent = frame if first else extent.merge(frame)
			first = false
	return extent

## S36's own done-when ("the wall button is hidden while only one picture exists"): forwards to the
## overlay, adding the one piece of state only the wall itself knows.
func refresh_overlay(stack: FocusStack) -> void:
	var overlay : WallOverlay = %Overlay
	overlay.refresh(stack, picture_count())

## §1.8 "window restored from minimise" (E7, Q208=b): every frozen picture texture may have been
## discarded by the GPU while the window was minimised, so every picture is force-rendered once.
## Godot has no dedicated "un-minimise" signal on desktop — `NOTIFICATION_APPLICATION_FOCUS_IN` is
## the closest built-in event (it also fires on a plain alt-tab back, Q207=a; harmless here, since a
## forced re-render costs one frame and E6 already treats a frozen-texture re-render as cheap by
## construction). See ASSUMPTIONS.md.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	for child : Node in %Pictures.get_children():
		var wp := child as WallPicture
		if wp:
			wp.mark_for_rerender()
