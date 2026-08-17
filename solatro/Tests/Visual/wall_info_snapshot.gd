extends Node2D
# res://Tests/Visual/wall_info_snapshot.gd
# ==============================================================================
# S26-S29 VERIFICATION (picture-wall, Phase 6 Info mode) -- by-eye only, TEST_PLAN.md §10 item 6
# ("does the self-sizing read as each notecard is unique"), no automated gate for the visual
# judgement itself (§11; the SIZING behaviour is what test_wall_info.gd's J4 already asserts).
#
#   01 -- two REAL InfoCard instances, one showing a short entry and one a long one, side by
#        side, so the size difference reads directly in one image.
#   02 -- a real Wall + focused WallPicture framed by `WallPicture.info_zoom_state()` (S28) --
#        the bottom frame edge revealed, top/left/right still cropped.
#
# One-off diagnostic, run windowed by hand, WITH AN EXTERNAL KILLING TIMEOUT (it calls
# get_tree().quit() itself, but a caller should still bound the process):
#     OUT_DIR=<absolute dir> <console exe> --path solatro res://Tests/Visual/wall_info_snapshot.tscn
# ==============================================================================

const INFO_CARD_SCENE := preload("res://UI/Wall/info_card.tscn")
const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
const FALLBACK_OUT_DIR := "user://wall_info_snapshot"
const WINDOW_SIZE := Vector2i(1400, 900)

var _out_dir : String

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wall_info_snapshot needs a REAL renderer: --headless never fires "
				+ "frame_post_draw. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	_out_dir = _resolve_out_dir()
	if _out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame

	await _shot_1_short_and_long_cards()
	await _shot_2_info_zoom_bottom_revealed()

	print("WALL_INFO_SNAPSHOT wrote 2 PNGs to ", ProjectSettings.globalize_path(_out_dir))
	get_tree().quit()

# ------------------------------------------------------------------ shot 1 (S27, TEST_PLAN §10.6)

## Two real InfoCard instances side by side (never both anchored to the SAME window bottom slot at
## once -- each is repositioned by hand here purely so both are visible in one frame; a live wall
## only ever shows one at a time). Left: a short entry. Right: a long one. Backdrop is a plain
## dark rect so the cards read clearly regardless of window theme.
func _shot_1_short_and_long_cards() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.14, 0.14, 0.17)
	bg.size = Vector2(WINDOW_SIZE)
	add_child(bg)

	var short_entry := InfoEntry.new()
	short_entry.title = "Backstage Pass"
	short_entry.body = "A simple keepsake from the first show."

	var long_entry := InfoEntry.new()
	long_entry.title = "The Travelling Almanac"
	long_entry.body = "A dog-eared notebook passed between every performer who has worked this " \
			+ "circuit, each one adding a page: routes between towns, which innkeepers water " \
			+ "down the ale, and a running tally of which acts drew a crowd worth the walk. By " \
			+ "the time it reaches you, it is less a book than a small, opinionated country."

	var short_card : InfoCard = INFO_CARD_SCENE.instantiate()
	add_child(short_card)
	short_card.show_entry(short_entry)
	short_card.position = Vector2(60, 60)

	var long_card : InfoCard = INFO_CARD_SCENE.instantiate()
	add_child(long_card)
	long_card.show_entry(long_entry)
	long_card.position = Vector2(60 + short_card.size.x + 80, 60)

	print("SHOT1 short_size=%s long_size=%s" % [short_card.size, long_card.size])
	await _capture("01_info_card_short_and_long")
	bg.queue_free()
	short_card.queue_free()
	long_card.queue_free()

# ------------------------------------------------------------------ shot 2 (S28)

## A real Wall + one real, focused WallPicture, camera framed by `WallPicture.info_zoom_state()`
## instead of the plain at-rest `focused_scale()` -- the bottom frame edge should read as a visible
## sliver below the picture; top/left/right should stay cropped exactly as they are at rest.
func _shot_2_info_zoom_bottom_revealed() -> void:
	var wall : Wall = WALL_SCENE.instantiate()
	add_child(wall)

	var layout := WallLayout.new()
	layout.gap_px = 24.0
	layout.ellipse_aspect_min = 1.2
	layout.ellipse_aspect_max = 2.6
	layout.home_id = &"info_demo"
	var entry := PictureEntry.new()
	entry.id = &"info_demo"
	entry.slot = 0
	entry.size_multiplier = 1.0
	entry.design_size = Vector2i(1152, 648)
	entry.frame_px = Vector4(30, 30, 30, 40)
	entry.frame_texture = WallPicture.shared_frame_texture()
	entry.scene = _content_scene(Color(0.55, 0.65, 0.45), entry.design_size)
	layout.pictures = [entry]

	var window := get_viewport_rect().size
	var rects := WallPacker.pack(layout, [&"info_demo"] as Array[StringName], window.x / window.y)
	print("SHOT2 packed=%d" % rects.size())
	var viewports : Node = wall.get_node(^"%Viewports")
	var pictures_root : Node = wall.get_node(^"%Pictures")
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	pictures_root.add_child(wp)
	wp.build(rects[0], entry, viewports)
	wp.focus()

	var settings := SettingsManager.settings
	var state := WallPicture.info_zoom_state(rects[0], window, settings)
	var camera : Camera2D = wall.get_node(^"%Camera2D")
	camera.position = state["position"]
	camera.zoom = Vector2.ONE * (state["zoom"] as float)
	print("SHOT2 info_zoom position=%s zoom=%.4f" % [state["position"], state["zoom"]])

	await _capture("02_info_zoom_bottom_frame_revealed")

# ------------------------------------------------------------------ shared plumbing

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
