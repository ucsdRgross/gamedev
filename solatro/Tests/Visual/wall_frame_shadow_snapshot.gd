extends Node2D
# res://Tests/Visual/wall_frame_shadow_snapshot.gd
# ==============================================================================
# S24/S25 VERIFICATION (picture-wall PLAN.md S24, S25) — both by-eye only, TEST_PLAN.md §10 items
# 2 and 3, no automated gate (deliberate, §11). Two shots:
#
#   01 — the SAME shared nine-slice frame texture (`WallPicture.shared_frame_texture()`, S24) on
#        the LARGEST and the SMALLEST picture on one wall, zoomed in enough to actually read the
#        bevel -- "does the corner hold at both extremes" (§10 item 2).
#   02 — six pictures spread around a wall, every one shadowed from the SAME authored light
#        position (`PlayerSettings.wall_light_offset`, S25) -- "do all pictures read as lit from
#        one direction" (§10 item 3).
#
# Builds a REAL res://UI/Wall/wall.tscn plus REAL WallPicture instances from small PROGRAMMATIC
# WallLayouts (never res://Assets/Wall/layout_default.tres -- the layout tool's own saved output,
# PLAN.md S34, Phase 8, out of scope), same "no mocks" discipline every other Tests/Visual
# snapshot in this folder follows. `entry.scene` is a flat-colour ColorRect filling the picture's
# own design_size -- diagnostic scaffolding (Q214=a, real screen content out of scope), not the
# frame texture under test, which IS the real `WallPicture.shared_frame_texture()` this time (S24
# is what is being verified, so the placeholder swatches every OTHER snapshot in this folder uses
# for the frame would defeat the point).
#
# One-off diagnostic, run windowed by hand, WITH AN EXTERNAL KILLING TIMEOUT (it calls
# get_tree().quit() itself, but a caller should still bound the process):
#     OUT_DIR=<absolute dir> <console exe> --path solatro res://Tests/Visual/wall_frame_shadow_snapshot.tscn
# ==============================================================================

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
const FALLBACK_OUT_DIR := "user://wall_frame_shadow_snapshot"
const WINDOW_SIZE := Vector2i(1600, 900)

var _wall : Wall
var _pictures : Array[WallPicture] = []
var _out_dir : String

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wall_frame_shadow_snapshot needs a REAL renderer: --headless never fires "
				+ "frame_post_draw. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	_out_dir = _resolve_out_dir()
	if _out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame

	_wall = WALL_SCENE.instantiate()
	add_child(_wall)

	await _shot_1_corner_art_largest_and_smallest()
	await _shot_2_consistent_shadow_direction()

	print("WALL_FRAME_SHADOW_SNAPSHOT wrote 2 PNGs to ", ProjectSettings.globalize_path(_out_dir))
	get_tree().quit()

# ------------------------------------------------------------------ shot 1 (S24)

## The SAME shared frame texture on a LARGE picture (design 1152x648, size_multiplier 1.6, a thick
## 60-unit frame) and a SMALL one (design 300x300, size_multiplier 0.5, a thin 14-unit frame) side
## by side, zoomed in on just the two of them (not the whole wall) so the bevel actually reads.
func _shot_1_corner_art_largest_and_smallest() -> void:
	var layout := WallLayout.new()
	layout.gap_px = 40.0
	layout.ellipse_aspect_min = 1.2
	layout.ellipse_aspect_max = 2.6
	layout.home_id = &"large"

	var large := PictureEntry.new()
	large.id = &"large"
	large.slot = 0
	large.size_multiplier = 1.6
	large.design_size = Vector2i(1152, 648)
	large.frame_px = Vector4(60, 60, 60, 60)
	large.frame_texture = WallPicture.shared_frame_texture()
	large.scene = _content_scene(Color(0.75, 0.60, 0.40), large.design_size)

	var small := PictureEntry.new()
	small.id = &"small"
	small.slot = 90
	small.size_multiplier = 0.5
	small.design_size = Vector2i(300, 300)
	small.keep_aspect = true
	small.frame_px = Vector4(14, 14, 14, 14)
	small.frame_texture = WallPicture.shared_frame_texture()
	small.scene = _content_scene(Color(0.40, 0.55, 0.75), small.design_size)

	# `get_viewport_rect().size` -- the LOGICAL canvas size, not the raw window pixel size --
	# project.godot's `canvas_items`/`expand` stretch mode decouples the two (ASSUMPTIONS.md,
	# "Facts measured for S14"); framing math must use the canvas size or it silently mis-fits.
	var window := get_viewport_rect().size
	layout.pictures = [large, small]
	var ids : Array[StringName] = [&"large", &"small"]
	var rects := WallPacker.pack(layout, ids, window.x / window.y)
	print("SHOT1 packed=%d of %d" % [rects.size(), ids.size()])
	_rebuild_pictures(layout, rects)

	# Fit BOTH frames with a modest margin -- FIT, not fill-and-crop, so neither corner is ever
	# cropped out of the shot (the whole point is comparing both extremes at once).
	var bbox := Rect2()
	var first := true
	for rect : PictureRect in rects:
		var frame := WallPacker.frame_outer_rect(rect)
		bbox = frame if first else bbox.merge(frame)
		first = false
	var camera : Camera2D = _wall.get_node(^"%Camera2D")
	var margin := 1.15
	var size := bbox.size * margin
	var scale_needed := minf(window.x / maxf(size.x, 1.0), window.y / maxf(size.y, 1.0))
	camera.zoom = Vector2.ONE * scale_needed
	camera.position = bbox.get_center()
	print("SHOT1 zoom=%.4f bbox=%s window=%s" % [scale_needed, bbox, window])
	await _capture("01_frame_corner_art_largest_and_smallest")

# ------------------------------------------------------------------ shot 2 (S25)

## Six pictures spread around a wall (WallPacker's own real placement, not hand-positioned), every
## one framed with the shared texture and shadowed from the SAME `wall_light_offset` -- consistent
## lighting is exactly "every shadow points the same way regardless of the picture's own position."
func _shot_2_consistent_shadow_direction() -> void:
	var layout := WallLayout.new()
	layout.gap_px = 32.0
	layout.ellipse_aspect_min = 1.2
	layout.ellipse_aspect_max = 2.6
	layout.home_id = &"home"
	var colors : Array[Color] = [
		Color(0.70, 0.55, 0.35), Color(0.35, 0.55, 0.70), Color(0.65, 0.35, 0.40),
		Color(0.45, 0.60, 0.35), Color(0.55, 0.45, 0.70), Color(0.70, 0.65, 0.35),
	]
	var pics : Array[PictureEntry] = []
	var ids : Array[StringName] = []
	var step := 360.0 / 6.0
	for i : int in 6:
		var id := &"home" if i == 0 else StringName("p%d" % i)
		var e := PictureEntry.new()
		e.id = id
		e.slot = int(step * float(i))
		e.size_multiplier = 0.9
		e.design_size = Vector2i(500, 380)
		e.frame_px = Vector4(28, 28, 28, 28)
		e.frame_texture = WallPicture.shared_frame_texture()
		e.scene = _content_scene(colors[i], e.design_size)
		pics.append(e)
		ids.append(id)
	layout.pictures = pics
	var window := get_viewport_rect().size
	var rects := WallPacker.pack(layout, ids, window.x / window.y)
	print("SHOT2 packed=%d of %d, wall_light_offset=%s" \
			% [rects.size(), ids.size(), SettingsManager.settings.wall_light_offset])
	_rebuild_pictures(layout, rects)

	var bbox := Rect2()
	var first := true
	for rect : PictureRect in rects:
		var frame := WallPacker.frame_outer_rect(rect)
		bbox = frame if first else bbox.merge(frame)
		first = false
	var camera : Camera2D = _wall.get_node(^"%Camera2D")
	camera.zoom = Vector2.ONE * WallPicture.focused_scale(bbox.size, window,
			SettingsManager.settings.wall_overfill_margin)
	camera.position = bbox.get_center()
	await _capture("02_consistent_shadow_direction")

# ------------------------------------------------------------------ shared plumbing

## Tears down whatever pictures the previous shot built, then builds fresh ones for `rects`.
func _rebuild_pictures(layout: WallLayout, rects: Array[PictureRect]) -> void:
	for wp : WallPicture in _pictures:
		if is_instance_valid(wp): wp.queue_free()
	_pictures.clear()
	var by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in layout.pictures: by_id[e.id] = e
	var viewports : Node = _wall.get_node(^"%Viewports")
	var pictures_root : Node = _wall.get_node(^"%Pictures")
	for rect : PictureRect in rects:
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		wp.build(rect, by_id[rect.id], viewports)
		_pictures.append(wp)

## Fills the WHOLE picture (design_size), not a small fixed swatch -- a small corner swatch reads
## as a rendering bug once the camera is close enough to actually see it (measured directly while
## building the earlier wall_verify_snapshot.gd, ASSUMPTIONS.md).
func _content_scene(color: Color, design_size: Vector2i) -> PackedScene:
	var rect := ColorRect.new()
	rect.size = Vector2(design_size)
	rect.color = color
	var packed := PackedScene.new()
	packed.pack(rect)
	rect.free()
	return packed

func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, file_name]
	img.save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))

func _resolve_out_dir() -> String:
	var env := OS.get_environment("OUT_DIR")
	if not env.is_empty(): return env
	return FALLBACK_OUT_DIR
