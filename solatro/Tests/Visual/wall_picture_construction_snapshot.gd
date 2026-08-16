extends Node2D
# res://Tests/Visual/wall_picture_construction_snapshot.gd
# ==============================================================================
# S10 VERIFICATION (picture-wall PLAN.md S10) — done-when is VISUAL: "pictures appear at their
# packed rects with NinePatchRect frames." Builds a REAL res://UI/Wall/wall.tscn plus several REAL
# WallPicture instances (repo rule 5, no mocks) from a small PROGRAMMATIC WallLayout -- never
# res://Assets/Wall/layout_default.tres, which is the layout TOOL's own output (S34, out of
# scope) -- packs it with the real WallPacker, builds each picture, zooms the wall's own
# %Camera2D out to fit the whole arrangement, then writes one screenshot to an absolute path
# handed in via the OUT_PATH env var (falls back to user://wall_picture_construction_snapshot if
# unset) and quits.
#
# ⚠ EVERY PictureEntry.scene STAYS NULL, DELIBERATELY (Q214=a — "registered but unbuilt"; a null
# scene renders as an empty viewport, which is expected and correct). Inventing placeholder scene
# CONTENT would be a design act and a gap. The frames DO get a flat runtime swatch colour each --
# that is diagnostic scaffolding to make frame geometry visible (same spirit as SnapshotScene's
# BACKDROP constant elsewhere in this folder), not authored frame art (S24's job).
#
# One-off diagnostic, run windowed by hand, WITH AN EXTERNAL KILLING TIMEOUT (it calls
# get_tree().quit() itself, but a caller should still bound the process):
#     <console exe> --path solatro res://Tests/Visual/wall_picture_construction_snapshot.tscn
#
# Deliberately NOT in all_tests.tscn: it needs a real renderer. TestWallRender (Tests/Wall/
# test_wall_render.gd) covers the CONSTRUCTION group headlessly-safe (N1, N5); this is the by-eye
# half repo rule 4 requires for any visual change.
# ==============================================================================

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
const FALLBACK_OUT_DIR := "user://wall_picture_construction_snapshot"
const WINDOW_SIZE := Vector2i(1280, 800)

## One swatch colour per picture, cycled -- purely so overlapping/adjacent frames are
## distinguishable in the shot, not a statement about the wall's actual frame art.
const SWATCH_COLORS : Array[Color] = [
	Color(0.65, 0.45, 0.25), Color(0.30, 0.55, 0.70), Color(0.70, 0.35, 0.40),
	Color(0.45, 0.60, 0.30), Color(0.55, 0.45, 0.70), Color(0.75, 0.60, 0.25),
]

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wall_picture_construction_snapshot needs a REAL renderer: --headless never "
				+ "fires frame_post_draw. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(WINDOW_SIZE)

	var wall : Wall = WALL_SCENE.instantiate()
	add_child(wall)

	var layout := _make_layout()
	var unlocked : Array[StringName] = []
	for e : PictureEntry in layout.pictures: unlocked.append(e.id)
	var rects := WallPacker.pack(layout, unlocked, float(WINDOW_SIZE.x) / float(WINDOW_SIZE.y))
	print("WALL_PICTURE_SNAPSHOT packed=%d of %d entries" % [rects.size(), layout.pictures.size()])

	var by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in layout.pictures: by_id[e.id] = e
	var viewports : Node = wall.get_node(^"%Viewports")
	var pictures_root : Node = wall.get_node(^"%Pictures")
	var bbox := Rect2()
	var i := 0
	for rect : PictureRect in rects:
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		wp.build(rect, by_id[rect.id], viewports)
		var frame : NinePatchRect = wp.get_node(^"%Frame")
		frame.texture = _swatch_texture(SWATCH_COLORS[i % SWATCH_COLORS.size()])
		var frame_rect := WallPacker.frame_outer_rect(rect)
		bbox = frame_rect if i == 0 else bbox.merge(frame_rect)
		i += 1

	var camera : Camera2D = wall.get_node(^"%Camera2D")
	_fit_camera(camera, bbox)

	# Two frames: one for the just-built scene to actually enter and draw, one to be sure it has
	# reached the screen (same discipline as SnapshotScene.capture / pause_time_spike._capture).
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var out_path := _resolve_out_path()
	var dir := out_path.get_base_dir()
	if dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(out_path)
	print("WALL_PICTURE_SNAPSHOT rects=%d bbox=%s" % [rects.size(), bbox])
	print("WALL_PICTURE_SNAPSHOT wrote=%s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

## Six pictures, deliberately varied size, frame thickness (including asymmetric L/T/R/B) and
## authored angle, so the placement model actually reads: something centred (the home picture,
## authored at a slot that does NOT sort first -- S4-fix), something pushed further out (the
## oversized one), frames of visibly different thickness never overlapping.
func _make_layout() -> WallLayout:
	var l := WallLayout.new()
	l.gap_px = 24.0
	l.ellipse_aspect_min = 1.2
	l.ellipse_aspect_max = 2.6
	l.home_id = &"home_pic"
	var pics : Array[PictureEntry] = [
		_entry(&"home_pic", 140, 1.2, Vector4(20, 20, 20, 20)),
		_entry(&"p_small", 0, 0.55, Vector4(10, 10, 10, 10)),
		_entry(&"p_wide_frame", 60, 0.9, Vector4(8, 8, 50, 8)),
		_entry(&"p_big", 200, 2.0, Vector4(24, 24, 24, 24)),
		_entry(&"p_mid", 280, 1.0, Vector4(16, 16, 16, 16)),
		_entry(&"p_thin", 330, 0.7, Vector4(6, 6, 6, 6)),
	]
	l.pictures = pics
	return l

func _entry(id: StringName, slot_deg: int, size_multiplier: float,
		frame_px: Vector4) -> PictureEntry:
	var e := PictureEntry.new()
	e.id = id
	e.slot = slot_deg
	e.size_multiplier = size_multiplier
	e.frame_px = frame_px
	return e

## A flat single-colour swatch -- diagnostic scaffolding so each frame reads distinctly in the
## shot, not authored frame art (see the file header).
func _swatch_texture(color: Color) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

## Zooms the wall's own %Camera2D out (and re-centres it) so the whole packed arrangement's
## bounding box fits on screen with a margin -- otherwise the default zoom=1 camera would clip
## everything past a few hundred px from the origin.
func _fit_camera(camera: Camera2D, bbox: Rect2) -> void:
	const MARGIN := 1.2
	var size := bbox.size * MARGIN
	var scale_needed := minf(float(WINDOW_SIZE.x) / maxf(size.x, 1.0),
			float(WINDOW_SIZE.y) / maxf(size.y, 1.0))
	camera.zoom = Vector2.ONE * scale_needed
	camera.position = bbox.get_center()

## An absolute filesystem path from OUT_PATH if the caller set one, else the user:// fallback --
## lets an external caller aim the PNG straight at a scratch directory outside the project.
func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return "%s/wall_s10_construction.png" % FALLBACK_OUT_DIR
