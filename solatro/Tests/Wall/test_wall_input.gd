extends TestSuite
# res://Tests/Wall/test_wall_input.gd
# ==============================================================================
# WALL INPUT (S36 only): TEST_PLAN.md §6 rows I5, I6, I9 -- Wall's own selection state (spatial
# arrow selection, wrap, cursor-visible-only-after-first-input), owed by S36 ("wall view: framing,
# pan and selection") ahead of the rest of TestWallInput, which belongs to Phase 4 (S19-S23, event
# ROUTING over an already-selected picture) and is NOT built here. NAMES.md already fixes this
# suite's name/script/suite_name().
#
# Also covers S36's other done-when clause, which has no TEST_PLAN row of its own: the Wall button
# hides itself while only one picture exists.
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
## positions, not a packed layout) and parents it under `wall`'s own %Pictures/%Viewports.
func _add_picture(wall: Wall, id: StringName, centre: Vector2) -> WallPicture:
	var rect := PictureRect.new(id, centre, Vector2(200, 150), Vector4(10, 10, 10, 10))
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
