extends TestSuite
# res://Tests/Wall/test_wall_input.gd
# ==============================================================================
# WALL INPUT (S36 only): TEST_PLAN.md §6 rows I5, I6, I9 -- Wall's own selection state (spatial
# arrow selection, wrap, cursor-visible-only-after-first-input), owed by S36 ("wall view: framing,
# pan and selection") ahead of the rest of TestWallInput, which belongs to Phase 4 (S19-S23, event
# ROUTING over an already-selected picture) and is NOT built here. NAMES.md already fixes this
# suite's name/script/suite_name().
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
	finish()

# ------------------------------------------------------------------ fixtures

func _build_wall() -> Wall:
	var wall : Wall = WALL_SCENE.instantiate()
	add_child(wall)
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
## then the wall itself.
func _teardown(wall: Wall, pictures: Array) -> void:
	for wp : WallPicture in pictures:
		if is_instance_valid(wp): wp.teardown()
	if wall and is_instance_valid(wall): wall.queue_free()

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
## window's exactly, fill-and-crop crops (almost) nothing on either axis, so pan has (almost) no
## room to move -- contrasted directly against the SAME extreme request against a genuinely
## oversized wall (the previous test's fixture shape), whose real pan range is two-plus orders of
## magnitude larger. clamp_pan(extreme) IS the clamped boundary itself, so the difference between
## the two extreme requests IS the pan range -- no private state needs reading.
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

	check(range_matching.length() > 0.0 and range_oversized.length() > 0.0,
			"both fixtures report a measurable pan range before comparing them",
			"matching=%s oversized=%s" % [range_matching, range_oversized])
	check(range_matching.length() < range_oversized.length() * 0.05,
			"pan range collapses to (near) nothing when the wall's aspect already matches the "
			+ "window's, versus a genuinely oversized wall's real free-pan room",
			"matching=%.2f oversized=%.2f" % [range_matching.length(), range_oversized.length()])
	_teardown(matching_wall, [matching_wp])
	_teardown(oversized_wall, [oversized_wp])
