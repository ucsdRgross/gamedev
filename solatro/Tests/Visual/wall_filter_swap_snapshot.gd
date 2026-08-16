extends Node2D
# res://Tests/Visual/wall_filter_swap_snapshot.gd
# ==============================================================================
# S13 VERIFICATION (picture-wall PLAN.md S13) — done-when is VISUAL and requires BY-EYE SIGN-OFF
# (repo rule 4, PLAN.md's own note: "a test cannot tell you it looks right"): "the focused picture
# at rest is NEAREST, everything else LINEAR." N7 (Tests/Wall/test_wall_render.gd) already proves
# the SWAP MECHANISM headlessly (pan vs zoom); this renders what it looks like.
#
# Builds a REAL res://UI/Wall/wall.tscn plus TWO real WallPicture instances, both showing the SAME
# small checkerboard pattern (fine detail makes NEAREST-vs-LINEAR unmistakable once magnified) --
# one FOCUSED (WallPicture.focus(), which forces update_filter(false) -- NEAREST, per S13's own
# wiring in wall_picture.gd), one left exactly as build() leaves it (LINEAR, H5's baseline, never
# focused) -- so both filters are visible side by side in one shot rather than asking the owner to
# compare across two separate renders.
#
# One-off diagnostic, run windowed by hand, WITH AN EXTERNAL KILLING TIMEOUT (it calls
# get_tree().quit() itself, but a caller should still bound the process):
#     OUT_PATH=<path> <console exe> --path solatro res://Tests/Visual/wall_filter_swap_snapshot.tscn
#
# Deliberately NOT in all_tests.tscn: needs a real renderer, and the judgement itself is by-eye.
# ==============================================================================

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
const FALLBACK_OUT_DIR := "user://wall_filter_swap_snapshot"
const WINDOW_SIZE := Vector2i(1280, 800)
## Small and coarse-checkered on purpose: once magnified by the camera, a NEAREST sample shows
## hard-edged blocks and a LINEAR sample shows visibly soft/blurred edges between them.
const NATIVE_SIZE := Vector2i(32, 32)
const CELL_PX := 4

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wall_filter_swap_snapshot needs a REAL renderer: --headless never fires "
				+ "frame_post_draw. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(WINDOW_SIZE)

	var wall : Wall = WALL_SCENE.instantiate()
	add_child(wall)

	var focused_entry := _entry(&"focused_pic", 0)
	var bg_entry := _entry(&"bg_pic", 90)
	var layout := WallLayout.new()
	layout.gap_px = 24.0
	layout.ellipse_aspect_min = 1.2
	layout.ellipse_aspect_max = 2.6
	layout.home_id = &"focused_pic"
	layout.pictures = [focused_entry, bg_entry] as Array[PictureEntry]

	var window_aspect := float(WINDOW_SIZE.x) / float(WINDOW_SIZE.y)
	var unlocked : Array[StringName] = [&"focused_pic", &"bg_pic"]
	var rects := WallPacker.pack(layout, unlocked, window_aspect)
	print("WALL_FILTER_SWAP_SNAPSHOT packed=%d" % rects.size())

	var by_id : Dictionary[StringName, PictureEntry] = {&"focused_pic": focused_entry,
			&"bg_pic": bg_entry}
	var viewports : Node = wall.get_node(^"%Viewports")
	var pictures_root : Node = wall.get_node(^"%Pictures")
	var focused_wp : WallPicture = null
	for rect : PictureRect in rects:
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		wp.build(rect, by_id[rect.id], viewports)
		if rect.id == &"focused_pic":
			focused_wp = wp
			wp.focus()   # NEAREST at rest, via wall_picture.gd's own S13 wiring.
		# bg_pic is left exactly as build() leaves it -- LINEAR, H5's non-focused baseline.

	# A MODERATE zoom (not H3's full overfill) so both pictures stay in frame for direct
	# side-by-side comparison -- S37's own snapshot is the one proving full-window overfill.
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	camera.zoom = Vector2.ONE * 10.0
	camera.position = focused_wp.position

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var out_path := _resolve_out_path()
	var dir := out_path.get_base_dir()
	if dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(out_path)
	print("WALL_FILTER_SWAP_SNAPSHOT wrote=%s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

func _entry(id: StringName, slot_deg: int) -> PictureEntry:
	var e := PictureEntry.new()
	e.id = id
	e.slot = slot_deg
	e.size_multiplier = 1.0
	e.frame_px = Vector4(2, 2, 2, 2)
	e.keep_aspect = true
	e.design_size = NATIVE_SIZE
	e.scene = _checkerboard_scene()
	return e

## A Sprite2D showing a small, coarse, high-contrast checkerboard -- see the CELL_PX/NATIVE_SIZE
## comment above for why fine detail is the point.
func _checkerboard_scene() -> PackedScene:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = _checkerboard_texture()
	var packed := PackedScene.new()
	packed.pack(sprite)
	sprite.free()
	return packed

func _checkerboard_texture() -> ImageTexture:
	var img := Image.create(NATIVE_SIZE.x, NATIVE_SIZE.y, false, Image.FORMAT_RGBA8)
	for y : int in NATIVE_SIZE.y:
		for x : int in NATIVE_SIZE.x:
			var on := ((x / CELL_PX) + (y / CELL_PX)) % 2 == 0
			img.set_pixel(x, y, Color.WHITE if on else Color.BLACK)
	return ImageTexture.create_from_image(img)

## An absolute filesystem path from OUT_PATH if the caller set one, else the user:// fallback.
func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return "%s/wall_filter_swap.png" % FALLBACK_OUT_DIR
