extends TestSuite
# res://Tests/Wall/test_wall_input.gd
# ==============================================================================
# WALL INPUT (S36, S19, S20, S21, S22, S23): TEST_PLAN.md §6 rows I1-I14, all of them.
# NAMES.md already fixes this suite's name/script/suite_name().
#
# ⚠ S22's own done-when (PLAN.md) ALSO requires "the controller driven by hand through one full
# navigate-enter-back-wall cycle" -- that is NOT done here and cannot be, headless. I10 below is
# AUTOMATED COVERAGE ONLY, per the owner's explicit ruling ("automated coverage for now"); the
# hand-driven pass is still owed (design/picture-wall/ASSUMPTIONS.md).
#
# Also covers two clauses of S36's done-when that have no TEST_PLAN row of their own (the plan's
# own hole, closed per the overseer's phase3-close instruction -- extra coverage is welcome):
#   - the Wall button hides itself while only one picture exists (G9/G10 are otherwise untested).
#   - G9 fill-and-crop wall-view framing, and G10 clamped pan (never past the outermost frames,
#     and effectively a no-op once nothing falls outside the view).
# ==============================================================================

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")

func suite_name() -> String:
	return "WALL INPUT"

func _ready() -> void:
	TestLog.line("============ WALL INPUT TEST PASS ============")
	behavior_section("SPATIAL SELECTION (I5, I6)")
	_test_arrow_selection_is_spatial()
	_test_selection_wraps()
	behavior_section("CURSOR VISIBILITY (I9)")
	_test_cursor_appears_only_after_a_key_press()
	behavior_section("WALL BUTTON VISIBILITY (S36's own done-when)")
	_test_wall_button_hidden_with_one_picture()
	behavior_section("WALL-VIEW FRAMING (G9)")
	_test_wall_view_zoom_fills_and_crops_the_correct_axis()
	behavior_section("CLAMPED PAN (G10)")
	_test_clamp_pan_never_shows_past_the_outermost_frames()
	_test_clamp_pan_is_effectively_a_no_op_when_everything_already_fits()
	behavior_section("ROUTING (I1, I2, S19)")
	await _test_click_routes_to_the_right_screen_coordinate_at_three_zoom_levels()
	await _test_non_focused_picture_never_receives_input()
	behavior_section("MOUSE (I8, S20)")
	_test_wheel_reaches_the_focused_screen_but_never_the_wall()
	behavior_section("KEYBOARD (I3, I4, I7, I14, S21)")
	_test_screen_that_consumes_escape_wall_does_not_go_back()
	_test_screen_that_ignores_escape_wall_goes_back()
	_test_wall_jump_3_enters_the_third_picture_in_placement_order()
	_test_wall_is_deaf_to_arrows_while_a_screen_is_focused()
	behavior_section("ENTER (Q88, Q99 -- S31 wire-up)")
	_test_ui_accept_enters_the_selected_picture()
	await _test_click_enters_an_unfocused_picture_immediately()
	behavior_section("CONTROLLER (I10, S22 -- automated coverage only, see ASSUMPTIONS.md)")
	_test_most_recent_device_wins_controller_after_mouse()
	behavior_section("TOUCH (I11, I12, I13, S23)")
	_test_pinch_is_derived_from_two_touches()
	_test_magnify_gesture_is_never_listened_for()
	_test_touch_target_size_is_clamped()
	behavior_section("PINCH WIRING (A3, CODE_REVIEW.md, Q119=a)")
	_test_pinch_out_enters_the_selected_picture()
	_test_pinch_in_returns_to_wall_view()
	finish()

# ------------------------------------------------------------------ fixtures

## ⚠ `wall` is parented under an ISOLATED SubViewport, not this suite's own root directly.
## `Wall._unhandled_input()` (S19-S21) calls `get_viewport().set_input_as_handled()`; if `wall`
## lived straight in the shared root viewport (as every earlier S36 fixture did, when nothing here
## called `_unhandled_input()` yet), that call would mark the SAME viewport ~38 OTHER concurrently-
## running suites dispatch REAL input through -- measured directly: it broke INTERACTION's own
## real Escape/click tests, which silently found their events already "handled" by a stale flag
## this suite's I3/I4/I7/I14 tests left set outside the engine's own per-event dispatch/reset
## cycle. `_teardown()` frees the wrapper viewport (which takes `wall` with it), not `wall` alone.
func _build_wall() -> Wall:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var wall : Wall = WALL_SCENE.instantiate()
	viewport.add_child(wall)
	# ⚠ Wall._ready() sets get_tree().paused = true GLOBALLY -- undo immediately, same reasoning
	# TestWallRender/TestWallPause already document (ASSUMPTIONS.md): add_child() above already ran
	# Wall._ready() SYNCHRONOUSLY, and GDScript only yields at an explicit await, so nothing else
	# can run in the gap.
	get_tree().paused = false
	return wall

## Builds one real WallPicture directly at `centre` (no WallPacker -- these tests need EXACT known
## positions, not a packed layout) and parents it under `wall`'s own %Pictures/%Viewports. `size`/
## `frame_px` default to the values every I5/I6/I9/wall-button fixture already used before G9/G10
## needed to control them precisely.
func _add_picture(wall: Wall, id: StringName, centre: Vector2,
		size: Vector2 = Vector2(200, 150), frame_px: Vector4 = Vector4(10, 10, 10, 10)) -> WallPicture:
	var rect := PictureRect.new(id, centre, size, frame_px)
	var entry := PictureEntry.new()
	entry.id = id
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	var pictures_root : Node = wall.get_node(^"%Pictures")
	var viewports : Node = wall.get_node(^"%Viewports")
	pictures_root.add_child(wp)
	wp.build(rect, entry, viewports)
	return wp

## Frees every constructed picture (teardown()'s own reason to exist -- the SubViewport lives under
## %Viewports, not under the picture, so a plain queue_free() on the picture alone would leak it),
## then `wall`'s own ISOLATING SubViewport wrapper (see `_build_wall()`) -- freeing the wrapper
## takes `wall` itself with it, in one deferred call.
func _teardown(wall: Wall, pictures: Array) -> void:
	for wp : WallPicture in pictures:
		if is_instance_valid(wp): wp.teardown()
	if wall and is_instance_valid(wall): wall.get_parent().queue_free()

## Six pictures at known positions around a centre point, sized so pressing Down from "top" has
## exactly ONE unambiguous nearest candidate ("below1", distance ~316) rather than a symmetric tie,
## and "bottom" is the unique extreme on the far side (distance 800 from "top", the largest of all
## six) -- both I5 and I6 read off this same fixture.
func _six_pictures(wall: Wall) -> Array[WallPicture]:
	return [
		_add_picture(wall, &"top", Vector2(0, -400)),
		_add_picture(wall, &"below1", Vector2(100, -100)),
		_add_picture(wall, &"below2", Vector2(-350, 50)),
		_add_picture(wall, &"right", Vector2(400, 0)),
		_add_picture(wall, &"bottom", Vector2(0, 400)),
		_add_picture(wall, &"left", Vector2(-400, 0)),
	]

# ------------------------------------------------------------------ I5, I6 (spatial selection)

## I5 (I4, Q98=a): selection starts at the TOP picture; pressing Down selects the geometrically
## NEAREST picture that lies below it -- not just any picture in that half-plane.
func _test_arrow_selection_is_spatial() -> void:
	var wall := _build_wall()
	var pictures := _six_pictures(wall)
	wall.enter_wall_view(&"top")
	wall.move_selection(Vector2.DOWN)
	check(wall.selected_id == &"below1",
			"pressing Down from the top picture selects the geometrically NEAREST one below it",
			str(wall.selected_id))
	_teardown(wall, pictures)

## I6 (I4, Q106=a): stepping past the extreme end wraps to the picture furthest in the OPPOSITE
## direction -- from the bottom-most picture, pressing Down again (nothing lies further below)
## wraps to the top-most one, "the first."
func _test_selection_wraps() -> void:
	var wall := _build_wall()
	var pictures := _six_pictures(wall)
	wall.enter_wall_view(&"bottom")
	wall.move_selection(Vector2.DOWN)
	check(wall.selected_id == &"top",
			"pressing Down from the BOTTOM-most picture (nothing lies further below) wraps to the "
			+ "TOP-most one", str(wall.selected_id))
	_teardown(wall, pictures)

# ------------------------------------------------------------------ I9 (cursor visibility)

## I9 (I10, Q105=b): a fresh wall (mouse-only session, no directional input yet) shows NO selection
## indicator; the first arrow press makes one appear.
func _test_cursor_appears_only_after_a_key_press() -> void:
	var wall := _build_wall()
	check(not wall.selection_visible,
			"a fresh wall with no directional input yet shows no selection indicator")
	wall.move_selection(Vector2.DOWN)
	check(wall.selection_visible, "the first arrow press makes the selection indicator appear")
	_teardown(wall, [])

# ------------------------------------------------------------------ wall button visibility

## S36's own done-when: the Wall button hides itself while only one picture exists (nothing to
## overview), and reappears once a second picture is packed.
func _test_wall_button_hidden_with_one_picture() -> void:
	var wall := _build_wall()
	var pictures : Array[WallPicture] = [_add_picture(wall, &"only", Vector2.ZERO)]
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	var wall_button : Button = overlay.get_node(^"%WallButton")
	var fs := FocusStack.new()
	fs.visit(&"only")
	wall.refresh_overlay(fs)
	check(not wall_button.visible, "the Wall button is hidden while only one picture exists")

	pictures.append(_add_picture(wall, &"other", Vector2(500, 0)))
	wall.refresh_overlay(fs)
	check(wall_button.visible, "the Wall button reappears once a second picture is packed")
	_teardown(wall, pictures)

# ------------------------------------------------------------------ G9 (fill-and-crop framing)

## G9 (Q5=b): wall_view_zoom() FILLS the window with the packed extent and crops whichever axis
## has the smaller window/extent ratio -- exercised at three real window aspects (1.33, 1.78, 2.33)
## against one FIXED extent (1000x550, aspect 1.818 -- deliberately between 1.78 and 2.33 so the
## filled/cropped axis actually FLIPS within these three points, proving the axis choice responds
## to the real aspect comparison rather than always favouring one hardcoded axis). At every aspect:
## (1) no letterbox -- the visible rect never shows anything outside the wall's own extent, on
## EITHER axis, which is what FILL (never FIT) guarantees by construction; (2) the axis with the
## larger window/extent ratio is FILLED (visible size close to the full extent); (3) the other axis
## is genuinely CROPPED (visible size strictly less than the extent's own size there).
func _test_wall_view_zoom_fills_and_crops_the_correct_axis() -> void:
	var wall := _build_wall()
	# One picture whose frame OUTER rect is exactly (1000, 550), centred at the origin.
	var wp := _add_picture(wall, &"a", Vector2.ZERO, Vector2(900, 450), Vector4(50, 50, 50, 50))
	var extent := WallPacker.frame_outer_rect(wp.rect)

	for aspect : float in [1.33, 1.78, 2.33]:
		var window := Vector2(720.0 * aspect, 720.0)
		var zoom := wall.wall_view_zoom(window)
		var visible := window / zoom
		check(visible.x <= extent.size.x + 0.5 and visible.y <= extent.size.y + 0.5,
				"aspect %.2f: no letterbox -- nothing outside the wall's extent is visible" % aspect,
				"visible=%s extent=%s" % [visible, extent.size])

		var x_ratio := window.x / extent.size.x
		var y_ratio := window.y / extent.size.y
		if x_ratio > y_ratio:
			check(_close_enough(visible.x, extent.size.x, extent.size.x * 0.05),
					"aspect %.2f: X is the FILLED axis (window/extent ratio %.4f > %.4f)"
					% [aspect, x_ratio, y_ratio], "visible.x=%.2f extent.x=%.2f" % [visible.x, extent.size.x])
			check(visible.y < extent.size.y - 0.5,
					"aspect %.2f: Y is genuinely CROPPED, not just flush" % aspect,
					"visible.y=%.2f extent.y=%.2f" % [visible.y, extent.size.y])
		else:
			check(_close_enough(visible.y, extent.size.y, extent.size.y * 0.05),
					"aspect %.2f: Y is the FILLED axis (window/extent ratio %.4f >= %.4f)"
					% [aspect, y_ratio, x_ratio], "visible.y=%.2f extent.y=%.2f" % [visible.y, extent.size.y])
			check(visible.x < extent.size.x - 0.5,
					"aspect %.2f: X is genuinely CROPPED, not just flush" % aspect,
					"visible.x=%.2f extent.x=%.2f" % [visible.x, extent.size.x])
	_teardown(wall, [wp])

## `is_equal_approx` only accepts a fixed built-in tolerance; these comparisons need a caller-chosen
## one (percent-of-extent, since the actual overfill margin constant is private to WallPicture).
func _close_enough(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance

# ------------------------------------------------------------------ G10 (clamped pan)

## G10 (Q1 note, Q3 note): free pan is clamped so the visible window never shows past the wall's
## own extent ("never pans into void"). Panning HARD toward all four extremes still leaves the
## visible rect fully CONTAINED in the packed bounding box, on every axis, every time.
func _test_clamp_pan_never_shows_past_the_outermost_frames() -> void:
	var wall := _build_wall()
	var wp := _add_picture(wall, &"a", Vector2.ZERO, Vector2(2600, 2600),
			Vector4(200, 200, 200, 200))
	var window := Vector2(1280, 720)
	var extent := WallPacker.frame_outer_rect(wp.rect)
	var zoom := wall.wall_view_zoom(window)
	var visible_size := window / zoom

	for target : Vector2 in [Vector2(-999999, 0), Vector2(999999, 0), Vector2(0, -999999),
			Vector2(0, 999999)]:
		var clamped := wall.clamp_pan(target, window)
		var visible := Rect2(clamped - visible_size * 0.5, visible_size)
		check(extent.encloses(visible),
				"panning hard toward %s never shows anything outside the wall's own extent" % target,
				"visible=%s extent=%s" % [visible, extent])
	_teardown(wall, [wp])

## G10's other half ("free pan is allowed ONLY when pictures fall outside the view... on a large
## screen everything is visible and panning is off"): when the packed extent's aspect matches the
## window's exactly, pan has EXACTLY zero room to move -- not merely "almost none". Measured update
## (DEFECT 1, wall_picture.gd `focused_scale()`): before that fix, `wall_overfill_margin` applied
## UNCONDITIONALLY, so a matching-aspect extent still got a stray 2% of overfill room to pan into --
## the same "crop/slack on real UI even though nothing needed hiding" defect DEFECT 1 fixed at the
## picture level, just visible here as a nonzero pan range instead of a clipped button. Now that the
## margin is CONDITIONAL (H3: applied only when the aspect ratios differ), fill and fit coincide
## exactly at matching aspect and `clamp_pan()`'s own min/max collapse to the same point -- contrasted
## against the SAME extreme request against a genuinely oversized wall (the previous test's fixture
## shape), whose real pan range stays unambiguously large. clamp_pan(extreme) IS the clamped boundary
## itself, so the difference between the two extreme requests IS the pan range -- no private state
## needs reading.
func _test_clamp_pan_is_effectively_a_no_op_when_everything_already_fits() -> void:
	var window := Vector2(1280, 720)

	var matching_wall := _build_wall()
	# Outer frame rect is EXACTLY the window's own size/aspect (16:9) -- fill-and-crop crops nothing.
	var matching_wp := _add_picture(matching_wall, &"a", Vector2.ZERO, Vector2(1080, 540),
			Vector4(100, 90, 100, 90))
	var range_matching := matching_wall.clamp_pan(Vector2(999999, 999999), window) \
			- matching_wall.clamp_pan(Vector2(-999999, -999999), window)

	var oversized_wall := _build_wall()
	var oversized_wp := _add_picture(oversized_wall, &"b", Vector2.ZERO, Vector2(2600, 2600),
			Vector4(200, 200, 200, 200))
	var range_oversized := oversized_wall.clamp_pan(Vector2(999999, 999999), window) \
			- oversized_wall.clamp_pan(Vector2(-999999, -999999), window)

	check(range_matching.is_zero_approx(),
			"pan range is EXACTLY zero when the wall's aspect already matches the window's -- fill "
			+ "and fit coincide, no margin to leave slack (H3/DEFECT 1)",
			"matching=%s" % range_matching)
	check(range_oversized.length() > 0.0,
			"a genuinely oversized wall still reports a measurable pan range",
			"oversized=%s" % range_oversized)
	_teardown(matching_wall, [matching_wp])
	_teardown(oversized_wall, [oversized_wp])

# ------------------------------------------------------------------ S19 fixtures (I1, I2)

## A throwaway PackedScene: a Control sized exactly `design_size`, with ONE Button (60x40) CENTRED
## in it (a "known spot") named "TheButton". `action_mode` fires `pressed` immediately on press
## (ACTION_MODE_BUTTON_PRESS) so a single synthetic press event is enough -- real press+release
## button semantics are not what I1/I2 are testing.
func _button_screen(design_size: Vector2i) -> PackedScene:
	var root := Control.new()
	root.size = Vector2(design_size)
	var button := Button.new()
	button.name = "TheButton"
	button.size = Vector2(60, 40)
	button.position = Vector2(design_size) * 0.5 - button.size * 0.5
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	root.add_child(button)
	# ⚠ PackedScene.pack() silently DROPS any child whose `.owner` is not the root being packed --
	# without this, "TheButton" compiles fine but is simply ABSENT from the packed scene, and every
	# later get_node() for it fails at runtime. Caught only via the engine-error scan, not a check()
	# failure -- the exact "silently proves nothing" shape this whole run keeps finding new forms of.
	button.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()   # the template Node is NOT RefCounted and never added to a tree -- needs .free()
	return packed

## An isolated SubViewport + Camera2D so `%Screen.get_global_transform_with_canvas()` resolves
## against ONLY this test's own camera -- immune to "current" camera contention from whatever OTHER
## concurrently-running suite's own ad-hoc Camera2D nodes exist on the shared root viewport (none
## of them read a live transform back, so it has never mattered before; I1 is the first test in
## this run that does).
class CameraRig:
	var viewport : SubViewport
	var camera : Camera2D
	var pictures_viewports : Node

func _camera_rig() -> CameraRig:
	var rig := CameraRig.new()
	rig.viewport = SubViewport.new()
	rig.viewport.size = Vector2i(1280, 720)
	add_child(rig.viewport)
	rig.camera = Camera2D.new()
	rig.viewport.add_child(rig.camera)
	rig.camera.make_current()
	rig.pictures_viewports = Node.new()
	rig.viewport.add_child(rig.pictures_viewports)
	return rig

func _teardown_camera_rig(rig: CameraRig) -> void:
	rig.viewport.queue_free()
	await get_tree().process_frame

# ------------------------------------------------------------------ I1, I2 (S19 routing)

## I1 (GAP-001 -- the risk that caused it): a click at the WALL-SPACE centre of a focused picture's
## Button correctly reaches and presses it at THREE different camera zoom levels (0.5, 1.0, 2.0) --
## proving WallInput.route()'s transform is correct as zoom changes, not just coincidentally right
## at 1.0.
func _test_click_routes_to_the_right_screen_coordinate_at_three_zoom_levels() -> void:
	var rig := _camera_rig()
	var design_size := Vector2i(200, 150)
	var rect := PictureRect.new(&"a", Vector2(300, -150), Vector2(design_size),
			Vector4(10, 10, 10, 10))
	var entry := PictureEntry.new()
	entry.id = &"a"
	entry.design_size = design_size
	entry.scene = _button_screen(design_size)
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	rig.viewport.add_child(wp)
	wp.build(rect, entry, rig.pictures_viewports)
	wp.focus()
	var button : Button = wp.screen_root.get_node(^"TheButton")
	var screen : Sprite2D = wp.get_node(^"%Screen")

	for zoom : float in [0.5, 1.0, 2.0]:
		rig.camera.zoom = Vector2(zoom, zoom)
		# Measured (Tests/Visual/wall_input_route_spike.gd): ONE process_frame is not reliably
		# enough for the camera's new canvas transform to actually land -- two, plus a render frame,
		# is what made get_global_transform_with_canvas() stop returning a stale/repeated value.
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pressed : Array[bool] = [false]   # boxed -- lambdas capture locals BY VALUE
		# Signal.connect() returns an Error code (int), not a handle -- keep the Callable itself so
		# disconnect() below has something it actually accepts.
		var handler := func() -> void: pressed[0] = true
		button.pressed.connect(handler)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		event.position = screen.get_global_transform_with_canvas() * Vector2.ZERO
		var handled := WallInput.route(event, wp)
		check(handled, "zoom %.1f: route() reports the event as routed" % zoom)
		check(pressed[0], "zoom %.1f: the button at the picture's known spot reports pressed" % zoom,
				"event.position=%s" % event.position)
		button.pressed.disconnect(handler)

	wp.teardown()
	await _teardown_camera_rig(rig)

## I2 (Q95=a): a click over a NON-focused (background) picture never reaches its viewport at all --
## its Button never reports pressed, and route() itself refuses before touching the viewport.
func _test_non_focused_picture_never_receives_input() -> void:
	var rig := _camera_rig()
	var design_size := Vector2i(200, 150)
	var rect := PictureRect.new(&"b", Vector2(300, -150), Vector2(design_size),
			Vector4(10, 10, 10, 10))
	var entry := PictureEntry.new()
	entry.id = &"b"
	entry.design_size = design_size
	entry.scene = _button_screen(design_size)
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	rig.viewport.add_child(wp)
	wp.build(rect, entry, rig.pictures_viewports)
	# Deliberately never focus()'d -- is_focused stays false, matching a background picture.
	var button : Button = wp.screen_root.get_node(^"TheButton")
	var pressed : Array[bool] = [false]
	button.pressed.connect(func() -> void: pressed[0] = true)

	var screen : Sprite2D = wp.get_node(^"%Screen")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen.get_global_transform_with_canvas() * Vector2.ZERO
	var handled := WallInput.route(event, wp)

	check(not handled, "route() refuses a non-focused picture outright")
	check(not pressed[0], "the background picture's button never reports pressed")

	wp.teardown()
	await _teardown_camera_rig(rig)

# ------------------------------------------------------------------ S20/S21 scripted fixtures

## A minimal throwaway screen script, compiled at runtime (GDScript.new()+source_code+reload()) --
## no `.gd` file for logic that belongs nowhere else, same reasoning as the earlier throwaway
## PackedScene()+pack(Node.new()) screen_root fixtures (S12/T13, ASSUMPTIONS.md), just with actual
## behaviour attached since these fixtures need to OBSERVE a state change, not merely exist.
func _scripted_node(source: String) -> Node:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	var node := Node.new()
	node.set_script(script)
	return node

## A "map" stand-in: tracks its own zoom_level and responds to the mouse wheel -- I8's own fixture
## ("wheel over a focused MAP picture, assert the map zoomed"). ⚠ An `is` check does NOT narrow a
## GDScript variable's STATIC type for later property access -- `event` stays typed `InputEvent`
## even after `event is InputEventMouseButton`, so an explicit `as` cast is required or `.pressed`/
## `.button_index` fail to compile.
const _MAP_SOURCE := "extends Node\nvar zoom_level := 1.0\nfunc _unhandled_input(event: InputEvent) -> void:\n\tif event is InputEventMouseButton:\n\t\tvar mb := event as InputEventMouseButton\n\t\tif mb.pressed:\n\t\t\tif mb.button_index == MOUSE_BUTTON_WHEEL_UP:\n\t\t\t\tzoom_level *= 1.1\n\t\t\t\tget_viewport().set_input_as_handled()\n\t\t\telif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:\n\t\t\t\tzoom_level *= 0.9\n\t\t\t\tget_viewport().set_input_as_handled()\n"

## A screen that consumes ui_cancel outright -- I3's own fixture ("a screen that consumes Escape").
const _CONSUMES_CANCEL_SOURCE := "extends Node\nfunc _unhandled_input(event: InputEvent) -> void:\n\tif event.is_action_pressed(&\"ui_cancel\"):\n\t\tget_viewport().set_input_as_handled()\n"

## Builds a picture whose `entry.scene` is a scripted throwaway Node (see `_scripted_node()`
## above), parented under `wall`'s own %Pictures/%Viewports like `_add_picture()`.
func _add_scripted_picture(wall: Wall, id: StringName, centre: Vector2, source: String) -> WallPicture:
	var rect := PictureRect.new(id, centre, Vector2(200, 150), Vector4(10, 10, 10, 10))
	var entry := PictureEntry.new()
	entry.id = id
	var template := _scripted_node(source)
	var packed := PackedScene.new()
	packed.pack(template)
	template.free()   # the template Node is NOT RefCounted and never added to a tree -- .free() it
	entry.scene = packed
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	var pictures_root : Node = wall.get_node(^"%Pictures")
	var viewports : Node = wall.get_node(^"%Viewports")
	pictures_root.add_child(wp)
	wp.build(rect, entry, viewports)
	return wp

# ------------------------------------------------------------------ I8 (S20 mouse wheel)

## I8 (Q89=a): the wheel always belongs to the focused screen. Routed via WallInput.route() (S19,
## generic over any InputEvent), it reaches the focused "map" picture's own zoom state -- and the
## WALL's own camera zoom is untouched (G11: "no free zoom in wall view" becomes a REAL assertion
## here, not the vacuous one S36 could only report before S20 wired anything to the wheel at all).
func _test_wheel_reaches_the_focused_screen_but_never_the_wall() -> void:
	var wall := _build_wall()
	var wp := _add_scripted_picture(wall, &"map", Vector2.ZERO, _MAP_SOURCE)
	wp.focus()
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	var zoom_before := camera.zoom

	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	var handled := WallInput.route(event, wp)

	check(handled, "the wheel event was routed to the focused picture")
	var zoom_level : float = wp.screen_root.get("zoom_level")
	check(is_equal_approx(zoom_level, 1.1),
			"the focused MAP screen's own zoom changed -- the wheel reached it (Q89=a)",
			"zoom_level=%.4f" % zoom_level)
	check(camera.zoom.is_equal_approx(zoom_before),
			"the WALL's own camera zoom is UNCHANGED -- the wheel is never consumed by the wall "
			+ "itself (G11: no free zoom in wall view)",
			"before=%s after=%s" % [zoom_before, camera.zoom])
	_teardown(wall, [wp])

# ------------------------------------------------------------------ I3, I4, I7, I14 (S21 keyboard)

## I3 (Q100=a): a screen that consumes Escape gets FIRST REFUSAL -- the wall does NOT go back.
func _test_screen_that_consumes_escape_wall_does_not_go_back() -> void:
	var wall := _build_wall()
	var wp := _add_scripted_picture(wall, &"consumer", Vector2.ZERO, _CONSUMES_CANCEL_SOURCE)
	wp.focus()
	var went_back : Array[bool] = [false]
	wall.wall_view_entered.connect(func() -> void: went_back[0] = true)

	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	wall._unhandled_input(event)

	check(not went_back[0],
			"a screen that consumes Escape gets FIRST REFUSAL -- the wall does NOT go back (Q100=a)")
	_teardown(wall, [wp])

## I4 (Q100=a): a screen that ignores Escape (no scene at all -- nothing inside consumes anything)
## lets it through -- the wall DOES go back.
func _test_screen_that_ignores_escape_wall_goes_back() -> void:
	var wall := _build_wall()
	var wp := _add_picture(wall, &"ignorer", Vector2.ZERO)
	wp.focus()
	var went_back : Array[bool] = [false]
	wall.wall_view_entered.connect(func() -> void: went_back[0] = true)

	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	wall._unhandled_input(event)

	check(went_back[0], "a screen that ignores Escape lets it through -- the wall DOES go back")
	_teardown(wall, [wp])

## I7 (Q104=a): wall_jump_3 enters the THIRD picture in PLACEMENT order -- GAP-009 deleted "ring",
## so "placement order" is WallPacker.pack()'s own output order, read here directly from %Pictures'
## child order (pictures are added in that same order below).
func _test_wall_jump_3_enters_the_third_picture_in_placement_order() -> void:
	var wall := _build_wall()
	var layout := WallLayout.new()
	layout.gap_px = 24.0
	layout.home_id = &"a"
	var ids : Array[StringName] = [&"a", &"b", &"c", &"d", &"e"]
	var entries : Array[PictureEntry] = []
	for i : int in ids.size():
		var e := PictureEntry.new()
		e.id = ids[i]
		e.slot = i * 60
		entries.append(e)
	layout.pictures = entries
	var rects := WallPacker.pack(layout, ids, 1.6)

	var pictures_root : Node = wall.get_node(^"%Pictures")
	var viewports : Node = wall.get_node(^"%Viewports")
	var entries_by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in entries: entries_by_id[e.id] = e
	var pictures : Array[WallPicture] = []
	for rect : PictureRect in rects:
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		wp.build(rect, entries_by_id[rect.id], viewports)
		pictures.append(wp)
	check(pictures.size() >= 3, "at least 3 pictures were packed for this fixture",
			str(pictures.size()))

	var event := InputEventAction.new()
	event.action = &"wall_jump_3"
	event.pressed = true
	wall._unhandled_input(event)

	var third := pictures[2]
	check(third.is_focused,
			"wall_jump_3 focuses the THIRD picture in the packer's own placement order",
			"id=%s" % third.rect.id)
	_teardown(wall, pictures)

## I14 (Q103=a, Q115=a): the wall is DEAF to its own arrow-key selection while a screen is focused
## -- "the wall never listens while a screen is focused."
func _test_wall_is_deaf_to_arrows_while_a_screen_is_focused() -> void:
	var wall := _build_wall()
	var wp := _add_picture(wall, &"focused_one", Vector2.ZERO)
	wp.focus()
	var selected_before := wall.selected_id
	var visible_before := wall.selection_visible

	var event := InputEventAction.new()
	event.action = &"ui_down"
	event.pressed = true
	wall._unhandled_input(event)

	check(wall.selected_id == selected_before and wall.selection_visible == visible_before,
			"an arrow press with a picture focused changes NOTHING about the wall's own selection",
			"selected before=%s after=%s" % [selected_before, wall.selected_id])
	_teardown(wall, [wp])

# ------------------------------------------------------------------ Q88, Q99 (S31 wire-up: enter)

## Q99=a: `ui_accept` enters the CURRENTLY SELECTED picture -- fires `picture_enter_requested` with
## `selected_id`, and nothing else (the wall never focuses a picture itself; the caller decides what
## "enter" means, same "wall announces intent, caller decides" shape `wall_view_entered` already
## uses). Reuses I5's own `_six_pictures()`/Down-from-top fixture so the expected selected id
## ("below1") is already independently proven correct by that test, not re-derived here.
func _test_ui_accept_enters_the_selected_picture() -> void:
	var wall := _build_wall()
	var pictures := _six_pictures(wall)
	wall.enter_wall_view(&"top")
	wall.move_selection(Vector2.DOWN)
	check(wall.selected_id == &"below1", "sanity: selection landed where I5 already proved it does",
			str(wall.selected_id))

	var requested : Array[StringName] = [&""]   # boxed -- lambdas capture locals BY VALUE
	wall.picture_enter_requested.connect(func(id: StringName) -> void: requested[0] = id)

	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	wall._unhandled_input(event)

	check(requested[0] == &"below1",
			"ui_accept enters the currently SELECTED picture (Q99=a)", "requested=%s" % requested[0])
	_teardown(wall, pictures)

## Q88=a: a click landing inside an UNFOCUSED picture's own frame-outer rect enters it immediately --
## fires `picture_enter_requested` with that picture's id. Hit-tested in WALL SPACE via the event's
## own `position`, transformed through the wall's own viewport `canvas_transform` -- the exact
## inverse of what `_unhandled_input()` itself applies to the event, so this test is immune to
## whatever the camera's own authored position/zoom actually are; it never assumes a 1:1 mapping.
## The click lands at the target picture's own CENTRE, well inside its frame-outer rect.
func _test_click_enters_an_unfocused_picture_immediately() -> void:
	var wall := _build_wall()
	var pictures := _six_pictures(wall)
	# The camera's canvas_transform is driven by %Camera2D's own _process; give it a couple of
	# frames to settle before reading it back, same reasoning I1's zoom-level loop already documents.
	await get_tree().process_frame
	await get_tree().process_frame

	var requested : Array[StringName] = [&""]
	wall.picture_enter_requested.connect(func(id: StringName) -> void: requested[0] = id)

	var target : WallPicture = pictures[1]   # "below1" -- deliberately NOT focus()'d
	check(not target.is_focused, "sanity: the target picture is unfocused, matching wall view")
	var canvas_transform := wall.get_viewport().canvas_transform
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = canvas_transform * target.rect.centre

	wall._unhandled_input(event)

	check(requested[0] == &"below1",
			"a click inside an unfocused picture's own frame enters it immediately (Q88=a)",
			"requested=%s" % requested[0])
	_teardown(wall, pictures)

# ------------------------------------------------------------------ I10 (S22 controller, AUTOMATED
# COVERAGE ONLY)

## I10 (Q124=a): MOST-RECENT-DEVICE-WINS -- a mouse move alone shows no keyboard/controller
## indicator (same shape as I9's fresh-wall case), then a REAL synthetic `InputEventJoypadButton`
## for `ui_down` (Godot's built-in default UI actions already bind the d-pad/left-stick -- nothing
## in this project's `project.godot` overrides `ui_down`, so this exercises the actual default
## binding, not a stand-in) shows it. This is the one piece of I10 that CAN run headless; it does
## NOT drive a real controller by hand, so it does not meet S22's own done-when -- see the header
## comment and ASSUMPTIONS.md.
func _test_most_recent_device_wins_controller_after_mouse() -> void:
	var wall := _build_wall()
	var pictures := _six_pictures(wall)
	wall.enter_wall_view(&"top")

	var mouse_event := InputEventMouseMotion.new()
	mouse_event.relative = Vector2(5, 5)
	wall._unhandled_input(mouse_event)
	check(not wall.selection_visible,
			"a mouse move alone shows no keyboard/controller indicator")

	var controller_event := InputEventJoypadButton.new()
	controller_event.button_index = JOY_BUTTON_DPAD_DOWN
	controller_event.pressed = true
	wall._unhandled_input(controller_event)
	check(wall.selection_visible,
			"a controller directional press shows the indicator -- the most recent device wins "
			+ "(Q124=a)")
	_teardown(wall, pictures)

# ------------------------------------------------------------------ I11, I12, I13 (S23 touch)

## I11 (GAP-003=a): pinch is DERIVED from two tracked touch ids, not any gesture event -- a touch
## DOWN for id 0 and id 1 six px apart on X, then three `InputEventScreenDrag` events for id 1
## moving it a further +40px on X in total (distance grows past `wall_pinch_threshold_px`=24
## partway through), asserts EXACTLY ONE `PINCH_OUT` across the whole sequence -- the later drag
## events, still past threshold, must NOT re-fire (Q119=a: pinch is one-shot, like a button press).
func _test_pinch_is_derived_from_two_touches() -> void:
	var tracker := WallInput.PinchTracker.new()
	const THRESHOLD := 24.0

	var down0 := InputEventScreenTouch.new()
	down0.index = 0
	down0.pressed = true
	down0.position = Vector2(100, 100)
	check(tracker.feed(down0, THRESHOLD) == WallInput.PinchTracker.Gesture.NONE,
			"first touch-down alone never fires a gesture")

	var down1 := InputEventScreenTouch.new()
	down1.index = 1
	down1.pressed = true
	down1.position = Vector2(106, 100)   # base distance 6px
	check(tracker.feed(down1, THRESHOLD) == WallInput.PinchTracker.Gesture.NONE,
			"second touch-down (base distance established) never fires a gesture by itself")

	# Base distance 6px (id0 at x=100, id1 at x=106). Three drags move id1 by +40px total on X, in
	# steps of 14/13/13 -- absolute id1.x after each: 120 (distance 20, still under the 24px
	# threshold), 133 (distance 33, CROSSES threshold here), 146 (distance 46, stays crossed).
	var fired_count := 0
	var last_gesture := WallInput.PinchTracker.Gesture.NONE
	for id1_x : float in [120.0, 133.0, 146.0]:
		var drag := InputEventScreenDrag.new()
		drag.index = 1
		drag.position = Vector2(id1_x, 100)
		var g := tracker.feed(drag, THRESHOLD)
		if g != WallInput.PinchTracker.Gesture.NONE:
			fired_count += 1
			last_gesture = g

	check(fired_count == 1, "pinch fires EXACTLY ONCE across the whole gesture, not once per event "
			+ "past threshold", "fired_count=%d" % fired_count)
	check(last_gesture == WallInput.PinchTracker.Gesture.PINCH_OUT,
			"the fired gesture is PINCH_OUT (fingers moved apart)", str(last_gesture))

## I12 (GAP-003=a): `InputEventMagnifyGesture` is NEVER listened for -- it does not fire on
## Windows and must not be relied on. Push one straight into a tracker that already has two
## fingers down (the state most likely to accidentally match something) and assert NOTHING
## happens: no gesture returned, no internal state disturbed (a follow-up real drag still behaves
## exactly as it would have without the magnify event ever having been fed).
func _test_magnify_gesture_is_never_listened_for() -> void:
	var tracker := WallInput.PinchTracker.new()
	const THRESHOLD := 24.0
	var down0 := InputEventScreenTouch.new()
	down0.index = 0
	down0.pressed = true
	down0.position = Vector2(100, 100)
	tracker.feed(down0, THRESHOLD)
	var down1 := InputEventScreenTouch.new()
	down1.index = 1
	down1.pressed = true
	down1.position = Vector2(106, 100)
	tracker.feed(down1, THRESHOLD)

	var magnify := InputEventMagnifyGesture.new()
	magnify.factor = 2.0
	var g := tracker.feed(magnify, THRESHOLD)
	check(g == WallInput.PinchTracker.Gesture.NONE,
			"an InputEventMagnifyGesture produces NO gesture -- it is never listened for",
			str(g))

	# Prove the tracker's real state is untouched: the SAME drag that fired PINCH_OUT in the test
	# above still fires it here, unaffected by the magnify event in between.
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(140, 100)   # distance now 40px, well past the 24px threshold
	var after := tracker.feed(drag, THRESHOLD)
	check(after == WallInput.PinchTracker.Gesture.PINCH_OUT,
			"a real drag past threshold still fires normally after the magnify event was ignored",
			str(after))

# ------------------------------------------------------------------ A3 (CODE_REVIEW.md wiring)

## A3 (CODE_REVIEW.md, Q119=a): `WallInput.PinchTracker` was built and tested in isolation
## (I11-I13 above) but never wired into `Wall`'s own input path -- touch pinch did NOTHING in the
## app. Drives REAL `InputEventScreenTouch`/`InputEventScreenDrag` events through
## `wall._unhandled_input()` (never `WallInput.PinchTracker` directly, which would only re-prove
## I11's own isolated arithmetic a second time) and asserts the WALL-LEVEL consequence Q119=a
## names: pinch-out commits to the current selection, same as `ui_accept` (wall view only).
func _test_pinch_out_enters_the_selected_picture() -> void:
	var wall := _build_wall()
	var pictures := _six_pictures(wall)
	wall.enter_wall_view(&"top")
	wall.move_selection(Vector2.DOWN)
	check(wall.selected_id == &"below1", "sanity: selection landed where I5 already proved it does",
			str(wall.selected_id))

	var requested : Array[StringName] = [&""]   # boxed -- lambdas capture locals BY VALUE
	wall.picture_enter_requested.connect(func(id: StringName) -> void: requested[0] = id)
	_feed_pinch_out(wall)

	check(requested[0] == &"below1",
			"pinch-out enters the currently selected picture, same as ui_accept (Q119=a)",
			"requested=%s" % requested[0])
	_teardown(wall, pictures)

## A3 (Q119=a): pinch-in, from a FOCUSED picture, returns to wall view -- the same consequence
## Escape already produces (I4 above), reached through the touch path instead of the keyboard one.
func _test_pinch_in_returns_to_wall_view() -> void:
	var wall := _build_wall()
	var wp := _add_picture(wall, &"focused_one", Vector2.ZERO)
	wp.focus()
	var went_back : Array[bool] = [false]
	wall.wall_view_entered.connect(func() -> void: went_back[0] = true)

	_feed_pinch_in(wall)

	check(went_back[0], "pinch-in on a focused picture returns to wall view (Q119=a)")
	_teardown(wall, [wp])

## Feeds a real two-touch pinch-OUT gesture (fingers spreading, distance growing past
## `wall_pinch_threshold_px`) through `wall._unhandled_input()` -- the same event shapes I11 already
## proves `WallInput.PinchTracker` itself detects correctly, routed through the wall this time.
func _feed_pinch_out(wall: Wall) -> void:
	var down0 := InputEventScreenTouch.new()
	down0.index = 0
	down0.pressed = true
	down0.position = Vector2(100, 100)
	wall._unhandled_input(down0)
	var down1 := InputEventScreenTouch.new()
	down1.index = 1
	down1.pressed = true
	down1.position = Vector2(106, 100)   # base distance 6px
	wall._unhandled_input(down1)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(146, 100)   # distance 46px, past the 24px default threshold
	wall._unhandled_input(drag)

## The pinch-IN mirror of `_feed_pinch_out()` -- fingers start FAR apart and close in past threshold.
func _feed_pinch_in(wall: Wall) -> void:
	var down0 := InputEventScreenTouch.new()
	down0.index = 0
	down0.pressed = true
	down0.position = Vector2(100, 100)
	wall._unhandled_input(down0)
	var down1 := InputEventScreenTouch.new()
	down1.index = 1
	down1.pressed = true
	down1.position = Vector2(160, 100)   # base distance 60px
	wall._unhandled_input(down1)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(120, 100)   # distance now 20px, delta -40, past the -24px threshold
	wall._unhandled_input(drag)

## I13 (GAP-004=b, §1.9's literal formula): the touch target size clamps to the configured
## floor/ceiling at absurd DPI readings -- DPI 1 (absurdly low) and DPI 10000 (absurdly high).
func _test_touch_target_size_is_clamped() -> void:
	var settings := PlayerSettings.new()
	check(settings.wall_touch_target_mm > 0.0 and settings.wall_touch_target_min_px > 0.0
			and settings.wall_touch_target_max_px > settings.wall_touch_target_min_px,
			"the settings this test clamps against are sane before asserting the clamp itself",
			"mm=%.2f min=%.1f max=%.1f" % [settings.wall_touch_target_mm,
					settings.wall_touch_target_min_px, settings.wall_touch_target_max_px])

	var low := WallInput.touch_target_px(1.0, settings)
	check(is_equal_approx(low, settings.wall_touch_target_min_px),
			"DPI 1 (absurdly low) clamps to the configured FLOOR",
			"got=%.4f floor=%.1f" % [low, settings.wall_touch_target_min_px])

	var high := WallInput.touch_target_px(10000.0, settings)
	check(is_equal_approx(high, settings.wall_touch_target_max_px),
			"DPI 10000 (absurdly high) clamps to the configured CEILING",
			"got=%.4f ceiling=%.1f" % [high, settings.wall_touch_target_max_px])
