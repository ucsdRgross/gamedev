extends TestSuite
# res://Tests/Wall/test_wall_render.gd
# ==============================================================================
# WALL RENDER (S10): WallPicture construction -- CONSTRUCTION GROUP ONLY. N2-N7 belong to S11
# render gating and are deliberately NOT here (coordinator brief for S10).
# PLAN.md §1.7; TEST_PLAN.md §7, N1, N5.
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
