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
const WALL_OVERLAY_SCENE := preload("res://UI/Wall/wall_overlay.tscn")

func suite_name() -> String:
	return "WALL INPUT"

func _ready() -> void:
	TestLog.line("============ WALL INPUT TEST PASS ============")
	behavior_section("SPATIAL SELECTION (I5, I6)")
	_test_arrow_selection_is_spatial()
	_test_selection_wraps()
	behavior_section("THE INFO CONTROL IS THE GLASS, NOT THE WORD (MINOR, J1/Q135)")
	_test_the_info_button_wears_the_magnifying_glass()
	behavior_section("THE SELECTION IS ACTUALLY DRAWN (MINOR, PICTURE_WALL.md, F11/Q105=b)")
	_test_the_selected_picture_is_the_one_visibly_lifted()
	behavior_section("HELD-STICK REPEAT (M9, PICTURE_WALL.md, I7/Q116=a)")
	await _test_a_held_direction_repeats_after_the_configured_delay()
	behavior_section("CURSOR VISIBILITY (I9)")
	_test_cursor_appears_only_after_a_key_press()
	behavior_section("WALL BUTTON VISIBILITY (S36's own done-when)")
	_test_wall_button_hidden_with_one_picture()
	behavior_section("WALL-VIEW FRAMING (G9)")
	_test_wall_view_zoom_fills_and_crops_the_correct_axis()
	_test_wall_view_zoom_reads_the_layouts_own_crop_bias()
	behavior_section("CLAMPED PAN (G10)")
	_test_clamp_pan_never_shows_past_the_outermost_frames()
	_test_clamp_pan_is_effectively_a_no_op_when_everything_already_fits()
	_test_dragging_bare_wall_pans_the_clamped_camera()
	_test_dragging_pans_nothing_when_the_whole_wall_already_fits()
	behavior_section("ROUTING (I1, I2, S19)")
	await _test_click_routes_to_the_right_screen_coordinate_at_three_zoom_levels()
	await _test_non_focused_picture_never_receives_input()
	behavior_section("MOUSE (I8, S20)")
	_test_wheel_reaches_the_focused_screen_but_never_the_wall()
	behavior_section("THE FOUR wall_* ACTIONS HAVE READERS (M3, PICTURE_WALL.md, I6/Q102=a)")
	_test_wall_overview_asks_for_wall_view()
	_test_wall_back_asks_for_back()
	_test_wall_forward_asks_for_forward()
	_test_wall_info_asks_for_an_info_toggle()
	implementation_section("THE FOUR wall_* ACTIONS ARE ACTUALLY BOUND (M3)")
	_test_every_wall_action_has_at_least_one_binding()
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
	behavior_section("TOUCH TARGETS REACH THE REAL CONTROLS (M6, PICTURE_WALL.md, GAP-004=b)")
	_test_every_overlay_control_meets_the_clamped_touch_target()
	behavior_section("TOUCH (I11, I12, I13, S23)")
	_test_pinch_is_derived_from_two_touches()
	_test_magnify_gesture_is_never_listened_for()
	_test_touch_target_size_is_clamped()
	behavior_section("PINCH WIRING (A3, PICTURE_WALL.md, Q119=a)")
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
	# M9: the FILLED axis is not flush with the extent -- it is the extent divided by the layout's
	# own crop bias (GAP-008/GAP-018). This used a hand-picked "within 5% of the extent" tolerance
	# because "the actual overfill margin constant is private to WallPicture" (its own words); that
	# tolerance was sized for the 2% picture knob it used to read and went red the moment the wall
	# read its own 6% one. The margin is no longer private, so the exact relationship is asserted
	# instead of a percentage -- strictly stronger, and it cannot be silently recalibrated again.
	var filled_span := 1.0 / (1.0 + Wall.load_layout().view_margin)

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
			check(is_equal_approx(visible.x, extent.size.x * filled_span),
					"aspect %.2f: X is the FILLED axis (window/extent ratio %.4f > %.4f)"
					% [aspect, x_ratio, y_ratio],
					"visible.x=%.2f expected=%.2f" % [visible.x, extent.size.x * filled_span])
			check(visible.y < extent.size.y * filled_span - 0.5,
					"aspect %.2f: Y is genuinely CROPPED, not just flush" % aspect,
					"visible.y=%.2f extent.y=%.2f" % [visible.y, extent.size.y])
		else:
			check(is_equal_approx(visible.y, extent.size.y * filled_span),
					"aspect %.2f: Y is the FILLED axis (window/extent ratio %.4f >= %.4f)"
					% [aspect, y_ratio, x_ratio],
					"visible.y=%.2f expected=%.2f" % [visible.y, extent.size.y * filled_span])
			check(visible.x < extent.size.x * filled_span - 0.5,
					"aspect %.2f: X is genuinely CROPPED, not just flush" % aspect,
					"visible.x=%.2f extent.x=%.2f" % [visible.x, extent.size.x])
	_teardown(wall, [wp])

## `is_equal_approx` only accepts a fixed built-in tolerance; a few comparisons here need a
## caller-chosen one.
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
	# ⚠ SMALL and OFF-CENTRE, both deliberately. A button filling the middle of the screen is
	# pressed by any routing transform that is even roughly right, and the exact centre is the ONE
	# point every wrong scale factor maps correctly (it is the fixed point of a scale about the
	# centre). I1 used to be exactly that shape and could not fail; see its own comment.
	button.size = Vector2(24, 24)
	button.position = Vector2(design_size) * Vector2(0.85, 0.25) - button.size * 0.5
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

## I1 (GAP-001 -- the risk that caused it): a click aimed at a known viewport pixel of a focused
## picture lands on THAT pixel, at three camera zoom levels (0.5, 1.0, 2.0) -- and presses a small,
## off-centre Button placed there.
##
## ⚠ THIS TEST WAS VACUOUS AND FOUND NOTHING FOR A WHOLE RUN. It used `rect.size == design_size`,
## which makes `%Screen.scale` exactly (1, 1), and it clicked the sprite's exact CENTRE, whose local
## coordinate is (0, 0) -- and `f * (0, 0) == (0, 0)` for every factor `f`. Both halves had to be
## wrong for it to pass; either one alone would have caught `route()` dividing by the sprite's scale
## twice. `TEST_PLAN.md` §10's I1 row literally specifies "click its wall-space centre", so the
## vacuity was authored, not accidental. The rect below is now a NON-square multiple of the design
## size, so the scale is (0.8, 1.0) -- the shape a non-16:9 window actually produces -- and every
## probe point is off-centre.
func _test_click_routes_to_the_right_screen_coordinate_at_three_zoom_levels() -> void:
	var rig := _camera_rig()
	var design_size := Vector2i(200, 150)
	# NOT Vector2(design_size): a rect equal to the design size makes %Screen.scale exactly 1 and
	# hides every scale-dependent routing error. WallPacker produces this shape at any window
	# aspect other than 16:9.
	var rect := PictureRect.new(&"a", Vector2(300, -150), Vector2(design_size) * Vector2(0.8, 1.0),
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
	check(not screen.scale.is_equal_approx(Vector2.ONE),
			"sanity: %Screen.scale is NOT 1 in this fixture, so a scale error can actually show",
			str(screen.scale))
	# The screen root is a Control at (0, 0) sized to the design, so its own gui_input position IS
	# the viewport pixel the event landed on -- read directly rather than inferred from whether a
	# widget happened to react.
	var landed : Array[Vector2] = [Vector2.INF]   # boxed -- lambdas capture locals BY VALUE
	(wp.screen_root as Control).gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton: landed[0] = (e as InputEventMouseButton).position)

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
		var target := button.position + button.size * 0.5
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		var half_vp := Vector2(wp.viewport.size) * 0.5
		event.position = screen.get_global_transform_with_canvas() * (target - half_vp)
		var handled := WallInput.route(event, wp)
		check(handled, "zoom %.1f: route() reports the event as routed" % zoom)
		check(pressed[0],
				"zoom %.1f: the small off-centre button at the aimed pixel reports pressed" % zoom,
				"event.position=%s" % event.position)
		button.pressed.disconnect(handler)

		# Three points spread across the screen, none of them the centre, checked as COORDINATES.
		# A scale error is zero at the centre and grows outward, so a corner is where it shows.
		for probe : Vector2 in [Vector2(12, 12), Vector2(design_size) - Vector2(12, 12),
				Vector2(design_size.x - 12, 12)]:
			landed[0] = Vector2.INF
			var probe_event := InputEventMouseButton.new()
			probe_event.button_index = MOUSE_BUTTON_LEFT
			probe_event.pressed = true
			probe_event.position = screen.get_global_transform_with_canvas() * (probe - half_vp)
			WallInput.route(probe_event, wp)
			# HALF A PIXEL, not is_equal_approx(): a round trip through the canvas transform at
			# zoom 0.5/2.0 lands ~1e-4 off, which is inside is_equal_approx's RELATIVE epsilon at
			# small coordinates and outside it at large ones -- measured, it flaked at (12, 12).
			# ⚠ This is a float-precision bound, NOT a tolerance fitted to a defect: the routing
			# error this test exists to catch displaced clicks by 38-57 PIXELS.
			check(landed[0].distance_to(probe) < 0.5,
					"zoom %.1f: a click aimed at viewport pixel %s lands there" % [zoom, probe],
					"landed=%s off by %.4f" % [landed[0], landed[0].distance_to(probe)])

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
## M2: watches `back_requested`, the signal `ui_cancel` actually emits now. Watching
## `wall_view_entered` here is what let keyboard Back mean WALL for the whole run.
func _test_screen_that_consumes_escape_wall_does_not_go_back() -> void:
	var wall := _build_wall()
	var wp := _add_scripted_picture(wall, &"consumer", Vector2.ZERO, _CONSUMES_CANCEL_SOURCE)
	wp.focus()
	var went_back : Array[bool] = [false]
	wall.back_requested.connect(func() -> void: went_back[0] = true)

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
	var went_to_wall_view : Array[bool] = [false]
	wall.back_requested.connect(func() -> void: went_back[0] = true)
	wall.wall_view_entered.connect(func() -> void: went_to_wall_view[0] = true)

	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	wall._unhandled_input(event)

	check(went_back[0], "a screen that ignores Escape lets it through -- the wall DOES go back")
	check(not went_to_wall_view[0],
			"M2/Q65=a: and asks for BACK, not for wall view -- only the FocusStack decides whether "
			+ "Back bottoms out into the overview, and `Wall` does not hold it")
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

	# apply_layout() is what records placement order (PICTURE_WALL.md C4) -- without it the wall
	# has no idea what "the third picture" means, so drive the real path rather than assuming.
	var rects_by_id : Dictionary[StringName, PictureRect] = {}
	for rect : PictureRect in rects: rects_by_id[rect.id] = rect
	wall.apply_layout(rects_by_id, false)

	# ⚠ ONE PICTURE IS ALREADY FOCUSED. The original fixture focused nothing, so it could not see
	# that _jump_to_index() called focus() directly without unfocusing anything -- leaving TWO
	# screen roots at PROCESS_MODE_ALWAYS and breaking §1.6's "exactly one" (Q74=a).
	var already : WallPicture = pictures[0]
	already.focus()

	var emitted : Array[StringName] = []
	wall.picture_enter_requested.connect(func(id: StringName) -> void: emitted.append(id))

	var event := InputEventAction.new()
	event.action = &"wall_jump_3"
	event.pressed = true
	wall._unhandled_input(event)

	var expected : StringName = rects[2].id
	check(emitted.size() == 1 and emitted[0] == expected,
			"wall_jump_3 REQUESTS the third picture in the packer's own placement order, through "
			+ "the same signal a click uses", "emitted=%s expected=%s" % [emitted, expected])
	var focused_count := 0
	for wp : WallPicture in pictures:
		if wp.is_focused: focused_count += 1
	check(focused_count == 1,
			"a jump leaves EXACTLY ONE focused picture -- it must not focus a second one behind "
			+ "the first", "focused=%d" % focused_count)
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

# ------------------------------------------------------------------ A3 (PICTURE_WALL.md wiring)

## A3 (PICTURE_WALL.md, Q119=a): `WallInput.PinchTracker` was built and tested in isolation
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

# ------------------------------------------------------------------ M3 (PICTURE_WALL.md)

## M3 (PICTURE_WALL.md): `wall_overview`, `wall_back`, `wall_forward` and `wall_info` were
## registered in the InputMap and read by NOTHING -- Tab, L1/LB, R1/RB and `I` all did nothing, so a
## controller had no Back, no Forward and no Wall at all. One test per action, each asserting the
## signal that action's own reader emits; every one goes red if its `is_action_pressed` branch in
## `Wall._unhandled_input()` is deleted.
##
## Fed as `InputEventAction`, the same shape `ui_cancel` and `wall_jump_3` above already use -- it
## matches by action NAME, so these stay true through any rebinding (I6/Q102=a: they are ordinary
## rebindable actions).
func _feed_action(wall: Wall, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	wall._unhandled_input(event)

## Q101=a/Q110=b: Tab, and the controller's Select/View button, ask for the overview.
func _test_wall_overview_asks_for_wall_view() -> void:
	var wall := _build_wall()
	var wp := _add_picture(wall, &"focused_one", Vector2.ZERO)
	wp.focus()
	var asked : Array[bool] = [false]
	wall.wall_view_entered.connect(func() -> void: asked[0] = true)

	_feed_action(wall, &"wall_overview")

	check(asked[0], "wall_overview asks for wall view -- Tab and Select/View had no reader at all")
	_teardown(wall, [wp])

## Q109=b: the shoulder button is Back, and Back means Back (M2), never wall view.
func _test_wall_back_asks_for_back() -> void:
	var wall := _build_wall()
	var wp := _add_picture(wall, &"focused_one", Vector2.ZERO)
	wp.focus()
	var asked_back : Array[bool] = [false]
	var asked_wall_view : Array[bool] = [false]
	wall.back_requested.connect(func() -> void: asked_back[0] = true)
	wall.wall_view_entered.connect(func() -> void: asked_wall_view[0] = true)

	_feed_action(wall, &"wall_back")

	check(asked_back[0], "wall_back asks for Back -- the controller had no Back at all")
	check(not asked_wall_view[0],
			"and asks for Back, not the overview -- same Q65=a retrace the keyboard gets (M2)")
	_teardown(wall, [wp])

## The mirror of Back on the other shoulder. Nothing read `wall_forward`, and it had no binding
## either, so Forward existed only as an overlay button.
func _test_wall_forward_asks_for_forward() -> void:
	var wall := _build_wall()
	var wp := _add_picture(wall, &"focused_one", Vector2.ZERO)
	wp.focus()
	var asked : Array[bool] = [false]
	wall.forward_requested.connect(func() -> void: asked[0] = true)

	_feed_action(wall, &"wall_forward")

	check(asked[0], "wall_forward asks for Forward -- the controller had no Forward at all")
	_teardown(wall, [wp])

## J1/Q135 note: the Info toggle is "always accessible regardless of screen", so `I` is read while a
## picture is focused too -- which is the only state in which Info has anything to reveal.
func _test_wall_info_asks_for_an_info_toggle() -> void:
	var wall := _build_wall()
	var wp := _add_picture(wall, &"focused_one", Vector2.ZERO)
	wp.focus()
	var asked : Array[bool] = [false]
	wall.info_toggle_requested.connect(func() -> void: asked[0] = true)

	_feed_action(wall, &"wall_info")

	check(asked[0], "wall_info asks for an Info toggle -- the `I` key had no reader at all")
	_teardown(wall, [wp])

## A reader is only half of it: `wall_back` and `wall_forward` were registered with an EMPTY event
## list, so even a wired reader could never fire from a real controller. Asserts that the bindings
## exist and that BOTH input families reach all four navigation actions -- never which button or
## keycode, since Q102=a makes them rebindable and pinning one would turn a rebind into a failure.
func _test_every_wall_action_has_at_least_one_binding() -> void:
	var actions : Array[StringName] = [&"wall_overview", &"wall_back", &"wall_forward", &"wall_info"]
	for action : StringName in actions:
		check(InputMap.has_action(action), "the InputMap registers %s" % action)
		if not InputMap.has_action(action): continue
		var events := InputMap.action_get_events(action)
		var message := "%s has at least one real binding -- an action nobody can press is as " % action
		check(not events.is_empty(), message + "dead as one nobody reads",
				"events=%d" % events.size())
		# ⚠ "AT LEAST ONE" IS NOT ENOUGH FOR THESE FOUR, and that is how `wall_back`/`wall_forward`
		# shipped joypad-ONLY (buttons 9 and 10, no key at all) while `wall_info` shipped key-only.
		# A keyboard player had no Forward and a controller player had no Info -- each invisible to
		# the other's half of the check. These four are the wall's whole navigation vocabulary, so
		# both input families must reach all of them. Asserts the KIND of event, never the button or
		# keycode: Q102=a makes them rebindable, and pinning one would turn a rebind into a failure.
		var has_key := false
		var has_pad := false
		for e : InputEvent in events:
			if e is InputEventKey: has_key = true
			elif e is InputEventJoypadButton or e is InputEventJoypadMotion: has_pad = true
		check(has_key, "%s is reachable from the KEYBOARD" % action, "events=%d" % events.size())
		check(has_pad, "%s is reachable from a CONTROLLER" % action, "events=%d" % events.size())

# ------------------------------------------------------------------ M4 (PICTURE_WALL.md)

## M4 (PICTURE_WALL.md): `clamp_pan()` had NO CALLER, so free pan did not exist and the two
## tests above guarded maths nothing ever ran. These drive the REAL pointer path -- press, move,
## release through `Wall._unhandled_input()` -- and go red if `pan_by()`'s branch there is removed.
##
## Both fixtures put the pressed point on BARE WALL, addressed through the viewport's own
## `canvas_transform` rather than a guessed screen coordinate: that is the exact inverse of the
## transform `_unhandled_input()` applies, so the press lands where the test says it does whether or
## not the fixture camera is driving the canvas. `_picture_at()` is asserted empty there first --
## a press INSIDE a picture enters it (Q88=a) and never arms a pan, so a fixture that quietly
## drifted onto a picture would prove nothing.
func _screen_pos_of(wall: Wall, wall_pos: Vector2) -> Vector2:
	return wall.get_viewport().canvas_transform * wall_pos

func _press_left(wall: Wall, screen_pos: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = screen_pos
	wall._unhandled_input(event)

func _drag_mouse(wall: Wall, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	wall._unhandled_input(event)

## G10 (Q1 note, Q3 note): on a wall too big for the window, dragging bare wall moves the camera by
## the pointer's own movement -- and never past the wall's own extent, however hard it is dragged.
func _test_dragging_bare_wall_pans_the_clamped_camera() -> void:
	var wall := _build_wall()
	var window := Vector2(1280, 720)
	# Two small pictures FAR apart: the extent is much wider than the window (so G10 allows pan at
	# all) and the origin between them is genuinely bare wall (so a press there can arm one).
	var left := _add_picture(wall, &"left", Vector2(-1400, 0))
	var right := _add_picture(wall, &"right", Vector2(1400, 0))
	check(wall._picture_at(Vector2.ZERO) == &"",
			"fixture: the wall origin really is BARE WALL, not inside a picture's frame (Q88=a)")

	var camera : Camera2D = wall.get_node(^"%Camera2D")
	camera.position = wall.wall_view_centre()
	camera.zoom = Vector2.ONE * wall.wall_view_zoom(window)
	var zoom := camera.zoom.x
	var start := camera.position
	var bare_wall := _screen_pos_of(wall, Vector2.ZERO)

	_press_left(wall, bare_wall, true)
	_drag_mouse(wall, Vector2(-100.0, 0.0))
	check(not camera.position.is_equal_approx(start),
			"dragging bare wall PANS the wall-view camera -- clamp_pan() had no caller at all",
			"start=%s now=%s" % [start, camera.position])
	check(_close_enough(camera.position.x, start.x + 100.0 / zoom, 0.01),
			"...by exactly the pointer's own movement, in the opposite direction and divided by the "
			+ "live zoom, so the wall tracks the pointer 1:1 on screen",
			"expected=%.4f got=%.4f" % [start.x + 100.0 / zoom, camera.position.x])

	# Drag far past the edge: the clamp, not the drag, is what stops the camera.
	for _i : int in range(20):
		_drag_mouse(wall, Vector2(-500.0, 0.0))
	var limit := wall.clamp_pan(Vector2(999999.0, 0.0), window)
	check(camera.position.x <= limit.x + 0.01,
			"G10: dragging hard never pans into void -- the camera stops at the clamped boundary",
			"camera=%.4f limit=%.4f" % [camera.position.x, limit.x])
	check(_close_enough(camera.position.x, limit.x, 0.01),
			"...and actually REACHES it, so the clamp is what stopped it and not a short drag",
			"camera=%.4f limit=%.4f" % [camera.position.x, limit.x])

	_press_left(wall, bare_wall, false)
	var after_release := camera.position
	_drag_mouse(wall, Vector2(-100.0, 0.0))
	check(camera.position.is_equal_approx(after_release),
			"releasing the button ends the drag -- moving the pointer afterwards pans nothing",
			"after_release=%s now=%s" % [after_release, camera.position])
	_teardown(wall, [left, right])

## G10's other half, now that something actually pans: "on a large screen everything is visible and
## panning is off." Two pictures whose combined frame-outer extent is EXACTLY the window's own
## 1280x720, with bare wall between them -- fill and fit coincide, `clamp_pan()` collapses both
## axes, and a real drag therefore moves the camera by nothing at all.
func _test_dragging_pans_nothing_when_the_whole_wall_already_fits() -> void:
	var wall := _build_wall()
	# Each picture is 600x700 with a 10 px frame -> 620x720 outer; centred at +-330 the pair spans
	# exactly x -640..640 and y -360..360.
	var left := _add_picture(wall, &"left", Vector2(-330, 0), Vector2(600, 700),
			Vector4(10, 10, 10, 10))
	var right := _add_picture(wall, &"right", Vector2(330, 0), Vector2(600, 700),
			Vector4(10, 10, 10, 10))
	check(wall._picture_at(Vector2.ZERO) == &"",
			"fixture: there is bare wall between the pair to press on")

	var camera : Camera2D = wall.get_node(^"%Camera2D")
	camera.position = wall.wall_view_centre()
	camera.zoom = Vector2.ONE * wall.wall_view_zoom(Vector2(1280, 720))
	var start := camera.position
	var bare_wall := _screen_pos_of(wall, Vector2.ZERO)

	_press_left(wall, bare_wall, true)
	for _i : int in range(10):
		_drag_mouse(wall, Vector2(-400.0, -400.0))

	check(camera.position.is_equal_approx(start),
			"G10: with the whole wall already visible, panning is OFF -- a real drag moves the "
			+ "camera by nothing", "start=%s now=%s" % [start, camera.position])
	_press_left(wall, bare_wall, false)
	_teardown(wall, [left, right])

# ------------------------------------------------------------------ M6 (PICTURE_WALL.md)

## M6 (PICTURE_WALL.md, GAP-004=b, I8c): `WallInput.touch_target_px()` had NO CALLER -- the
## overlay's buttons were whatever size the scene authored (80x32), and GAP-004's clamp, which its
## own answer calls "a contract, not a guard clause", never ran on anything. `_test_touch_target_
## size_is_clamped()` below pins the FORMULA; this pins the fact that a real control obeys it.
##
## Driven through a DELIBERATELY LARGE `wall_touch_target_min_px` rather than the machine's own DPI:
## the real reading on this box already produces a target the authored 80 px width happens to
## exceed, so a same-DPI assertion would pass against a `_ready()` that did nothing at all. The
## floor is raised past every authored dimension, so only a real clamp can satisfy it -- and it also
## proves the KNOB is read, not just some constant.
func _test_every_overlay_control_meets_the_clamped_touch_target() -> void:
	backup_real_settings()
	var settings := SettingsManager.settings
	var real_min := settings.wall_touch_target_min_px
	var real_max := settings.wall_touch_target_max_px
	settings.wall_touch_target_max_px = 400.0
	settings.wall_touch_target_min_px = 120.0   # larger than every authored offset in the scene

	var overlay : WallOverlay = WALL_OVERLAY_SCENE.instantiate()
	add_child(overlay)
	var target := WallInput.touch_target_px(DisplayServer.screen_get_dpi(), settings)
	check(target >= 120.0,
			"fixture: the raised floor really is what the clamp returns, so the assertions below "
			+ "cannot be satisfied by the scene's own authored sizes", "target=%.1f" % target)

	var names : Array[StringName] = [&"%BackButton", &"%ForwardButton", &"%WallButton",
			&"%InfoButton"]
	var previous_right := -INF
	for path : StringName in names:
		var button : Button = overlay.get_node(NodePath(path))
		check(button.size.x >= target and button.size.y >= target,
				"%s is at least the clamped touch target on BOTH axes" % path,
				"size=%s target=%.1f" % [button.size, target])
	# The three left-hand buttons grew; they must not have grown INTO each other.
	for path : StringName in [&"%BackButton", &"%ForwardButton", &"%WallButton"]:
		var button : Button = overlay.get_node(NodePath(path))
		check(button.position.x >= previous_right,
				"%s still starts at or after the previous button ends -- growing the row kept its "
				% path + "authored gap instead of overlapping",
				"left=%.1f previous_right=%.1f" % [button.position.x, previous_right])
		previous_right = button.position.x + button.size.x

	overlay.queue_free()
	settings.wall_touch_target_min_px = real_min
	settings.wall_touch_target_max_px = real_max
	restore_real_settings()

# ------------------------------------------------------------------ M9 (PICTURE_WALL.md)

## M9 (PICTURE_WALL.md, GAP-008=a, G9/Q5=b): `WallLayout.view_margin` -- the crop bias
## GAP-008 deliberately homed on the LAYOUT -- had no reader; `wall_view_zoom()` used
## `wall_overfill_margin`, which is a PICTURE knob (H3/GAP-011) about the focused picture's own
## overfill, not the wall's framing.
##
## Proven by CHANGING the knob on disk and watching the zoom follow, which is the only assertion a
## knob-nothing-reads cannot satisfy. The layout is written to a temp path and loaded through the
## real `Wall.load_layout()` seam that `test_wall_render.gd`'s own disk test already uses.
##
## A MISMATCHED aspect on purpose: `focused_scale()` applies the margin only when the ratios differ
## (H3/DEFECT 1), so a matching-aspect fixture would read identically at every margin and prove
## nothing.
func _test_wall_view_zoom_reads_the_layouts_own_crop_bias() -> void:
	var window := Vector2(1280, 720)
	var wall := _build_wall()
	var wp := _add_picture(wall, &"a", Vector2.ZERO, Vector2(900, 900), Vector4(10, 10, 10, 10))
	var extent := WallPacker.frame_outer_rect(wp.rect)
	check(not is_equal_approx(window.x / extent.size.x, window.y / extent.size.y),
			"fixture: the wall's aspect really does differ from the window's, so the crop bias is "
			+ "applied at all (H3)")

	var plain := WallPicture.focused_scale(extent.size, window, 1.0)
	var zoom := wall.wall_view_zoom(window)
	var layout_margin : float = Wall.load_layout().view_margin
	check(is_equal_approx(zoom, plain * (1.0 + layout_margin)),
			"wall-view zoom is the plain fill times the LAYOUT's own view_margin",
			"zoom=%.5f expected=%.5f margin=%.3f" % [zoom, plain * (1.0 + layout_margin),
					layout_margin])
	check(not is_equal_approx(layout_margin,
			SettingsManager.settings.wall_overfill_margin - 1.0),
			"...and that margin is a DIFFERENT number from wall_overfill_margin, so the check "
			+ "above cannot be satisfied by the knob this used to read",
			"view_margin=%.3f wall_overfill_margin=%.3f"
					% [layout_margin, SettingsManager.settings.wall_overfill_margin])
	_teardown(wall, [wp])

# ------------------------------------------------------------------ M9 (PICTURE_WALL.md)

## M9 (PICTURE_WALL.md, I7/Q116=a: "one step per press with a repeat after a hold delay"):
## `wall_selection_repeat_delay` had NO READER, which is what "held-stick repeat does not exist"
## means in practice -- a held arrow or stick moved the selection once and then sat there.
##
## Three pictures in a COLUMN so a repeated Down has somewhere new to land each time, and the
## repeat delay is set SHORT for the run: that keeps the test to a few frames AND proves the knob
## is genuinely read, which a test using the 0.4 s default could not distinguish from a hardcoded
## constant.
##
## The release half matters as much as the repeat: an implementation that never disarmed would sail
## through the repeat assertion and then move the selection forever.
func _test_a_held_direction_repeats_after_the_configured_delay() -> void:
	backup_real_settings()
	var settings := SettingsManager.settings
	var real_delay : float = settings.wall_selection_repeat_delay
	settings.wall_selection_repeat_delay = 0.05

	var wall := _build_wall()
	var top := _add_picture(wall, &"top", Vector2(0, -300))
	var middle := _add_picture(wall, &"middle", Vector2(0, 0))
	var bottom := _add_picture(wall, &"bottom", Vector2(0, 300))
	wall.enter_wall_view(&"top")

	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	wall._unhandled_input(down)
	check(wall.selected_id == &"middle",
			"the PRESS itself still moves exactly one step (Q116=a's first half)",
			str(wall.selected_id))

	# Long enough for the 0.05 s delay to elapse over real frames, bounded so a broken repeat fails
	# rather than hangs.
	for _i : int in range(60):
		if wall.selected_id == &"bottom": break
		await get_tree().process_frame
	check(wall.selected_id == &"bottom",
			"holding it REPEATS after wall_selection_repeat_delay -- nothing read that knob at all "
			+ "before M9", str(wall.selected_id))

	var release := InputEventAction.new()
	release.action = &"ui_down"
	release.pressed = false
	wall._unhandled_input(release)
	# Deliberately back at the TOP, so a still-armed repeat would visibly move it again.
	wall.enter_wall_view(&"top")
	for _i : int in range(30):
		await get_tree().process_frame
	check(wall.selected_id == &"top",
			"releasing DISARMS the repeat -- it does not keep walking the wall on its own",
			str(wall.selected_id))

	settings.wall_selection_repeat_delay = real_delay
	restore_real_settings()
	_teardown(wall, [top, middle, bottom])

# ------------------------------------------------------------------ MINOR (PICTURE_WALL.md)

## MINOR (PICTURE_WALL.md): two findings, one cause -- nothing turned (`selected_id`,
## `selection_visible`) into what is actually DRAWN. Entering wall view set the id and lifted
## nothing, so arriving showed no cursor at all (F11/Q69=a: "exactly one picture is selected in wall
## view, always"); and `selection_visible` had no renderer, so the lift was applied whether or not
## Q105=b said the cursor had been earned yet.
##
## Asserted on the LIFT ITSELF -- `WallPicture.position` against `rect.centre` -- not on the two
## flags, which is the whole point: the flags were already right, and reading them back would
## re-prove a variable assignment while being unable to fail for the bug ([[tests-that-prove-nothing]]
## trap 6).
func _test_the_selected_picture_is_the_one_visibly_lifted() -> void:
	var wall := _build_wall()
	var top := _add_picture(wall, &"top", Vector2(0, -300))
	var bottom := _add_picture(wall, &"bottom", Vector2(0, 300))
	var lift : Vector2 = SettingsManager.settings.wall_selected_lift
	check(not lift.is_zero_approx(),
			"fixture: the lift is a real, visible offset, so 'lifted' and 'not lifted' differ",
			str(lift))

	wall.enter_wall_view(&"top")
	check(top.position.is_equal_approx(top.rect.centre),
			"Q105=b: arriving by MOUSE lifts nothing -- the cursor has not been earned yet",
			"%s vs %s" % [str(top.position), str(top.rect.centre)])

	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	wall._unhandled_input(down)
	check(bottom.position.is_equal_approx(bottom.rect.centre + lift),
			"the first directional input LIFTS the newly selected picture",
			"%s vs %s" % [str(bottom.position), str(bottom.rect.centre + lift)])
	check(top.position.is_equal_approx(top.rect.centre),
			"...and puts the one it left back down -- exactly one picture is lifted (F11/Q69=a)")

	# Re-entering wall view now that the cursor IS earned must show it, which is the half that was
	# missing outright.
	wall.enter_wall_view(&"top")
	check(top.position.is_equal_approx(top.rect.centre + lift),
			"entering wall view shows the selection on the picture you came FROM (F10/F11)",
			"%s vs %s" % [str(top.position), str(top.rect.centre + lift)])
	check(bottom.position.is_equal_approx(bottom.rect.centre),
			"...and only that one")
	_teardown(wall, [top, bottom])

# ------------------------------------------------------------------ MINOR (PICTURE_WALL.md)

## MINOR (PICTURE_WALL.md, J1, Q135's note): the Info control is "a top-right magnifying
## glass"; it shipped wearing the word "Info". The icon is built procedurally
## (`WallOverlay.magnifier_icon()`, the `WallPicture.shared_frame_texture()` idiom) because the
## project's font has no magnifier glyph.
##
## ⚠ This asserts the WIRING and the icon's STRUCTURE only. Whether the drawing reads as a
## magnifying glass is a by-eye question (CLAUDE.md rule 4) and was answered by rendering it and
## looking: a closed circular lens ring with an even-width diagonal handle. No test can make that
## claim, so none here pretends to.
func _test_the_info_button_wears_the_magnifying_glass() -> void:
	var overlay : WallOverlay = WALL_OVERLAY_SCENE.instantiate()
	add_child(overlay)
	var info_button : Button = overlay.get_node(^"%InfoButton")

	check(info_button.icon != null, "the Info button carries an icon at all (J1)")
	check(info_button.text == "",
			"...and no longer wears the WORD -- the glass IS the label", info_button.text)
	check(info_button.tooltip_text == TRANSLATION.find(&"WALL_INFO"),
			"the localised string survives as the tooltip, so the control is still named for a "
			+ "screen reader and still translatable", info_button.tooltip_text)

	# Structure, not looks: an icon that is entirely transparent, or entirely opaque, is not a
	# drawing of anything -- and either would sail past a mere "icon != null" check.
	var img := info_button.icon.get_image()
	var opaque := 0
	for y : int in img.get_height():
		for x : int in img.get_width():
			if img.get_pixel(x, y).a > 0.5: opaque += 1
	var total := img.get_width() * img.get_height()
	check(total > 0, "the icon has pixels to inspect", "total=%d" % total)
	check(opaque > 0 and opaque < total,
			"the icon is a DRAWING -- partly opaque, partly transparent, not a blank or a solid "
			+ "block", "opaque=%d of %d" % [opaque, total])
	overlay.queue_free()
