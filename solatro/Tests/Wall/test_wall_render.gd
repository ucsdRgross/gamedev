extends TestSuite
# res://Tests/Wall/test_wall_render.gd
# ==============================================================================
# WALL RENDER (S10 CONSTRUCTION group: N1, N5. S11 RENDER GATING group: N2, N3, N4, N6, N7).
# PLAN.md §1.7, §1.8; TEST_PLAN.md §7.
#
# Builds a real res://UI/Wall/wall.tscn plus a few real WallPicture instances from a small
# PROGRAMMATIC WallLayout (never res://Assets/Wall/layout_default.tres -- that is the layout
# TOOL's output, S34, out of scope here), then inspects the constructed tree.
# ==============================================================================

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")

func suite_name() -> String:
	return "WALL RENDER"

var _wall : Wall = null
var _pictures : Array[WallPicture] = []

func _ready() -> void:
	TestLog.line("============ WALL RENDER TEST PASS ============")
	behavior_section("CONSTRUCTION")
	_build_wall()
	test_every_subviewport_is_explicitly_nearest()
	test_no_subviewport_container_anywhere()
	behavior_section("RENDER GATING")
	test_unvisited_picture_has_rendered_once()
	test_non_focused_picture_keeps_texture()
	test_wall_view_size_written_and_clamped()
	test_restore_from_minimise_rerenders()
	test_filter_swaps_on_zoom_not_pan()
	behavior_section("OVERFILL MARGIN (H3, GAP-011)")
	test_overfill_margin_knob_actually_changes_the_scale()
	_teardown_wall()
	finish()

# ------------------------------------------------------------------ fixture

func _entry(id: StringName, slot_deg: int, size_multiplier: float,
		frame_px: Vector4) -> PictureEntry:
	var e := PictureEntry.new()
	e.id = id
	e.slot = slot_deg
	e.size_multiplier = size_multiplier
	e.frame_px = frame_px
	return e

## A small, varied, PROGRAMMATIC layout -- three pictures, different sizes and frame thicknesses,
## enough to exercise real construction without authoring the tool's own layout resource.
func _make_layout() -> WallLayout:
	var l := WallLayout.new()
	l.gap_px = 24.0
	l.ellipse_aspect_min = 1.2
	l.ellipse_aspect_max = 2.6
	l.home_id = &"a"
	var pics : Array[PictureEntry] = [
		_entry(&"a", 0, 1.0, Vector4(16, 16, 16, 16)),
		_entry(&"b", 90, 1.3, Vector4(8, 8, 40, 8)),
		_entry(&"c", 210, 0.8, Vector4(24, 24, 24, 24)),
	]
	l.pictures = pics
	return l

func _build_wall() -> void:
	_wall = WALL_SCENE.instantiate()
	add_child(_wall)
	# ⚠ Wall._ready() sets get_tree().paused = true, GLOBALLY, by design (§1.6) -- correct
	# standalone, but this suite runs CONCURRENTLY with ~33 others that need normal processing to
	# ever finish, and a global pause with no unpause hangs the whole run with no banner (measured:
	# a 600s timeout, no suite ever signals finished). Safe to undo immediately: add_child() above
	# already ran Wall._ready() SYNCHRONOUSLY (the parent was already in the tree), and nothing else
	# can run between that call and this line since GDScript only yields at an explicit await.
	get_tree().paused = false
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

## Frees every constructed picture (and its off-tree SubViewport, teardown()'s whole reason to
## exist) plus the wall itself, so this suite leaves nothing behind for its siblings.
func _teardown_wall() -> void:
	for wp : WallPicture in _pictures: wp.teardown()
	_pictures.clear()
	if _wall and is_instance_valid(_wall): _wall.queue_free()
	_wall = null

# ------------------------------------------------------------------ N1, N5

## N1: every SubViewport constructed for the wall is explicitly NEAREST -- the trap this repo has
## hit four times (§1c).
func test_every_subviewport_is_explicitly_nearest() -> void:
	check(_pictures.size() == 3, "3 pictures were constructed", str(_pictures.size()))
	for wp : WallPicture in _pictures:
		check(wp.viewport != null, "%s has a SubViewport" % wp.name)
		if wp.viewport:
			check(wp.viewport.canvas_item_default_texture_filter
					== Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST,
					"%s's SubViewport is explicitly NEAREST" % wp.name)

## N5: no SubViewportContainer exists anywhere in the wall (GAP-001=b -- the decision this defends).
func test_no_subviewport_container_anywhere() -> void:
	check(not _has_subviewport_container(_wall), "no SubViewportContainer anywhere in the wall")

func _has_subviewport_container(node: Node) -> bool:
	if node is SubViewportContainer: return true
	for child : Node in node.get_children():
		if _has_subviewport_container(child): return true
	return false

# ------------------------------------------------------------------ N2, N3, N4, N6, N7 (S11)

## N3 (E4, Q78=b): every picture has a non-null texture straight out of build(), before any focus()
## call is made anywhere in this suite -- run first in the RENDER GATING group on purpose so later
## tests' focus()/unfocus() calls cannot retroactively make this claim vacuous.
func test_unvisited_picture_has_rendered_once() -> void:
	for wp : WallPicture in _pictures:
		check(wp.viewport.get_texture() != null,
				"%s's texture is non-null before any focus() call" % wp.name)

## N2 (E3, Q82=a): a non-focused picture reports UPDATE_DISABLED, but its already-rendered texture
## persists -- never null, never zero-size.
func test_non_focused_picture_keeps_texture() -> void:
	var wp := _pictures[0]
	wp.focus()
	wp.unfocus(Vector2(200, 120))
	check(wp.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"a non-focused picture's SubViewport reports UPDATE_DISABLED")
	var tex := wp.viewport.get_texture()
	check(tex != null, "its texture is non-null")
	check(tex != null and tex.get_size() != Vector2.ZERO, "its texture is non-zero-size",
			str(tex.get_size()) if tex else "null")

## N4 (§1.8, GAP-002): SubViewport.size is written straight from the on-screen footprint, each axis
## independently clamped below by settings.wall_view_min_texture_px -- shrinking one axis to 10px
## clamps that (short) axis to the floor without disturbing the other.
func test_wall_view_size_written_and_clamped() -> void:
	var wp := _pictures[0]
	wp.unfocus(Vector2(10, 500))
	var min_px := SettingsManager.settings.wall_view_min_texture_px
	check(mini(wp.viewport.size.x, wp.viewport.size.y) == min_px,
			"a 10px footprint clamps the short axis to wall_view_min_texture_px",
			str(wp.viewport.size))

## N6 (E7, Q208=b): restoring from minimise re-renders every picture once. Wall._notification hooks
## NOTIFICATION_APPLICATION_FOCUS_IN (ASSUMPTIONS.md -- the closest built-in "un-minimise" event on
## desktop) and calls mark_for_rerender() on every WallPicture under %Pictures.
func test_restore_from_minimise_rerenders() -> void:
	for wp : WallPicture in _pictures:
		wp.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED  # simulate "settled"
	_wall.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	for wp : WallPicture in _pictures:
		check(wp.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,
				"%s went UPDATE_ONCE after the restore notification" % wp.name)

## N7 (H6, Q34): the filter swaps on zoom, not on pan -- pure translation must never flip it. Owed
## to S11 per TEST_PLAN.md §7's own suite header ("S10, S11"), even though the full camera-driven
## wiring is S13's job (§1.7); this pins the method's own contract directly.
func test_filter_swaps_on_zoom_not_pan() -> void:
	var wp := _pictures[0]
	var screen : Sprite2D = wp.get_node(^"%Screen")
	wp.update_filter(false)
	check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"pan only (zoom unchanged) leaves the filter NEAREST")
	wp.update_filter(true)
	check(screen.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR,
			"a zoom change flips the filter to LINEAR")

# ------------------------------------------------------------------ GAP-011 (H3)

## GAP-011: `wall_overfill_margin` is a real, READ knob, not a promoted-but-ignored export -- the
## exact defect §1.8 exists to prevent ("a knob nothing reads is the defect"). `focused_scale()`
## takes the margin as a REQUIRED parameter (no default), so this also proves the parameter is
## actually wired through, not merely present on `PlayerSettings`. Two visibly different margins on
## the SAME native/window sizes must produce two DIFFERENT scales, and each must equal the plain
## fill-ratio times its own margin exactly -- not just "different", which a sign flip or an
## unrelated bug could also produce.
func test_overfill_margin_knob_actually_changes_the_scale() -> void:
	var native := Vector2(400, 300)
	var window := Vector2(1280, 720)
	var fill_ratio := maxf(window.x / native.x, window.y / native.y)

	var scale_a := WallPicture.focused_scale(native, window, 1.02)
	var scale_b := WallPicture.focused_scale(native, window, 1.10)
	check(not is_equal_approx(scale_a, scale_b),
			"two different wall_overfill_margin values produce two different focused_scale() results",
			"scale_a=%.6f scale_b=%.6f" % [scale_a, scale_b])
	check(is_equal_approx(scale_a, fill_ratio * 1.02),
			"the 1.02 result equals the plain fill ratio times exactly that margin, not a fixed 1.02",
			"scale_a=%.6f expected=%.6f" % [scale_a, fill_ratio * 1.02])
	check(is_equal_approx(scale_b, fill_ratio * 1.10),
			"the 1.10 result equals the plain fill ratio times exactly that margin",
			"scale_b=%.6f expected=%.6f" % [scale_b, fill_ratio * 1.10])

	var settings := PlayerSettings.new()
	check(is_equal_approx(settings.wall_overfill_margin, 1.02),
			"PlayerSettings.wall_overfill_margin defaults to 1.02 (GAP-011's answered value)",
			"%.4f" % settings.wall_overfill_margin)
