extends Node2D
# res://Tests/Visual/wall_overfill_snapshot.gd
# ==============================================================================
# S37 VERIFICATION (picture-wall PLAN.md S37) — done-when is VISUAL: "at aspects 1.33, 1.78 and
# 2.33 the square `map` picture shows no frame at rest." Builds a REAL res://UI/Wall/wall.tscn plus
# ONE real WallPicture -- a square, keep_aspect entry modeled on the design's `map` picture (H2,
# Q32=b) -- from a small PROGRAMMATIC WallLayout, focuses it (WallPicture.focus(), which is also
# S13's own NEAREST-at-rest trigger), frames the wall's %Camera2D using WallPicture.focused_scale()
# (H3, Q27=c: "fill and crop", never "fit" -- the frame is guaranteed off-screen at every aspect,
# not merely at the ones tested here), then writes one screenshot to OUT_PATH and quits.
#
# One-off diagnostic, run windowed by hand ONCE PER ASPECT, WITH AN EXTERNAL KILLING TIMEOUT (it
# calls get_tree().quit() itself, but a caller should still bound the process). WINDOW_W/WINDOW_H
# set the window (and therefore the aspect under test) for that run:
#     OUT_PATH=<path> WINDOW_W=<w> WINDOW_H=<h> \
#         <console exe> --path solatro res://Tests/Visual/wall_overfill_snapshot.tscn
#
# Deliberately NOT in all_tests.tscn: S37 has no TEST_PLAN.md row at all -- it is by-eye only
# (repo rule 4), same as S13/S24/S25.
# ==============================================================================

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
const FALLBACK_OUT_DIR := "user://wall_overfill_snapshot"
## The picture's own native content resolution -- small on purpose, so ANY visible frame sliver
## (or filtering artifact, incidentally) reads unmistakably large relative to it once overfilled.
const NATIVE_SIZE := Vector2i(400, 400)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wall_overfill_snapshot needs a REAL renderer: --headless never fires "
				+ "frame_post_draw. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(_resolve_window_size())
	# Let the stretch transform (project.godot: canvas_items / expand) settle onto the new window
	# size before trusting get_visible_rect() -- window_set_size() does not take effect on the 2D
	# canvas's own logical size synchronously.
	await get_tree().process_frame
	await get_tree().process_frame
	var window_size := get_viewport().get_visible_rect().size

	var wall : Wall = WALL_SCENE.instantiate()
	add_child(wall)

	var entry := _map_entry()
	var layout := WallLayout.new()
	layout.gap_px = 24.0
	layout.ellipse_aspect_min = 1.2
	layout.ellipse_aspect_max = 2.6
	layout.home_id = entry.id
	layout.pictures = [entry] as Array[PictureEntry]

	var window_aspect := float(window_size.x) / float(window_size.y)
	var rects := WallPacker.pack(layout, [entry.id] as Array[StringName], window_aspect)
	print("WALL_OVERFILL_SNAPSHOT packed=%d window=%s aspect=%.4f" % [rects.size(), window_size,
			window_aspect])

	var viewports : Node = wall.get_node(^"%Viewports")
	var pictures_root : Node = wall.get_node(^"%Pictures")
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	pictures_root.add_child(wp)
	wp.build(rects[0], entry, viewports)
	wp.focus()   # S13's own trigger: focus() forces update_filter(false) -- NEAREST at rest.

	# H3 (Q27=c): frame the camera so this ONE picture's native content overfills the window on
	# every axis -- "fill and crop", never "fit". WallPicture.focused_scale() is the same pure
	# function S14's real camera-tracking will eventually call; this snapshot drives it by hand
	# since the transition system (Phase 3) is out of scope for this step.
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	var scale := WallPicture.focused_scale(Vector2(NATIVE_SIZE), Vector2(window_size))
	camera.zoom = Vector2.ONE * scale
	camera.position = wp.position

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var out_path := _resolve_out_path()
	var dir := out_path.get_base_dir()
	if dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(out_path)
	print("WALL_OVERFILL_SNAPSHOT wrote=%s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

## The `map` model (H2, Q32=b): square, `keep_aspect = true`, so WallPacker never stretches it to
## the window aspect -- the overfill has to come from the CAMERA framing alone (H3), exactly the
## case that would show a frame sliver under plain "fit" scaling.
func _map_entry() -> PictureEntry:
	var e := PictureEntry.new()
	e.id = &"map_at_rest"
	e.slot = 0
	e.size_multiplier = 1.0
	e.frame_px = Vector4(24, 24, 24, 24)
	e.keep_aspect = true
	e.design_size = NATIVE_SIZE
	e.frame_texture = _swatch_texture(Color(0.75, 0.60, 0.25))
	e.scene = _content_scene()
	return e

## A bright, saturated ColorRect filling the picture's own content -- so its edge against
## %WallSurface's dark background reads unambiguously in the shot (the actual thing S37 is proving:
## that edge stays off-screen at rest). Diagnostic scaffolding, not authored content (Q214=a --
## every real picture's `scene` is its own actual screen; this one stands in for it).
func _content_scene() -> PackedScene:
	var rect := ColorRect.new()
	rect.size = Vector2(NATIVE_SIZE)
	rect.color = Color(0.95, 0.85, 0.15)
	var packed := PackedScene.new()
	packed.pack(rect)
	rect.free()
	return packed

## A flat swatch so the frame's presence (or, correctly, its absence at rest) reads unambiguously
## against %WallSurface's own colour -- diagnostic scaffolding, not authored frame art (S24's job).
func _swatch_texture(color: Color) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

## WINDOW_W/WINDOW_H from the environment (the caller picks the aspect under test); falls back to
## a 16:9 1280x720 window if unset.
func _resolve_window_size() -> Vector2i:
	var w := OS.get_environment("WINDOW_W")
	var h := OS.get_environment("WINDOW_H")
	if w.is_empty() or h.is_empty(): return Vector2i(1280, 720)
	return Vector2i(int(w), int(h))

## An absolute filesystem path from OUT_PATH if the caller set one, else the user:// fallback.
func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return "%s/wall_overfill.png" % FALLBACK_OUT_DIR
