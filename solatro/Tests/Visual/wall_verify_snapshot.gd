extends Node2D
# res://Tests/Visual/wall_verify_snapshot.gd
# ==============================================================================
# COORDINATOR-REQUESTED VERIFICATION SNAPSHOTS (picture-wall, latch-fix follow-up) -- five shots
# in one run, by-eye sign-off material (repo rule 4: "verify visuals by eye"). Builds a REAL
# res://UI/Wall/wall.tscn plus REAL WallPicture instances from small PROGRAMMATIC WallLayouts
# (never res://Assets/Wall/layout_default.tres -- that is the layout tool's own output, S34, out
# of scope; ASSUMPTIONS.md), same "no mocks" discipline every other Tests/Visual snapshot in this
# folder already follows.
#
# ⚠ Captures are written DIRECTLY (img.save_png(), same recipe as wall_skeleton_snapshot.gd/
# wall_overfill_snapshot.gd/wall_picture_construction_snapshot.gd), NOT via SnapshotScene's own
# capture()/label() helper: that helper's on-screen caption assumes an IDENTITY camera in the root
# viewport, and every shot here actively repositions `wall`'s own real %Camera2D, which BECOMES
# the viewport's current camera the instant it exists -- a caption placed at a fixed "screen"
# position would be drawn through that camera's transform too and land somewhere inside the wall
# instead of at the top of the image (measured: it did, on the first version of this file).
#
# ⚠ Every PictureEntry.scene here is diagnostic scaffolding (a flat-colour ColorRect FILLING the
# picture's own design_size, not a fixed small swatch), and every frame gets a flat runtime swatch
# colour -- same spirit as wall_picture_construction_snapshot.gd (S10) and
# wall_overfill_snapshot.gd (S37). Not authored frame art (S24's job) or real screen content
# (Q214=a, out of scope) -- purely so geometry reads unambiguously in the shot.
#
# One-off diagnostic, run windowed by hand, WITH AN EXTERNAL KILLING TIMEOUT (it calls
# get_tree().quit() itself, but a caller should still bound the process):
#     OUT_DIR=<absolute dir> <console exe> --path solatro res://Tests/Visual/wall_verify_snapshot.tscn
#
# Deliberately NOT in all_tests.tscn: needs a real renderer, and is by-eye sign-off material, not
# an automated gate.
# ==============================================================================

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
const FALLBACK_OUT_DIR := "user://wall_verify_snapshot"
const PICTURE_COUNT := 12

const SWATCH_COLORS : Array[Color] = [
	Color(0.65, 0.45, 0.25), Color(0.30, 0.55, 0.70), Color(0.70, 0.35, 0.40),
	Color(0.45, 0.60, 0.30), Color(0.55, 0.45, 0.70), Color(0.75, 0.60, 0.25),
	Color(0.35, 0.65, 0.60), Color(0.80, 0.50, 0.35), Color(0.40, 0.40, 0.75),
	Color(0.70, 0.70, 0.30), Color(0.55, 0.30, 0.55), Color(0.30, 0.75, 0.45),
]

var _wall : Wall
var _pictures : Array[WallPicture] = []
var _out_dir : String

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wall_verify_snapshot needs a REAL renderer: --headless never fires "
				+ "frame_post_draw. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	_out_dir = _resolve_out_dir()
	if _out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	await get_tree().process_frame

	_wall = WALL_SCENE.instantiate()
	add_child(_wall)

	await _shot_1_everything_unlocked()
	await _shot_2_partial_unlock()
	await _shot_3_mid_transition()
	await _shot_4_landed_focused()
	await _shot_5_extreme_aspect()

	print("WALL_VERIFY_SNAPSHOT wrote 5 PNGs to ", ProjectSettings.globalize_path(_out_dir))
	get_tree().quit()

# ------------------------------------------------------------------ shot 1

## Wall view, EVERY picture unlocked. GAP-010's identity case: nothing is locked, so every angle
## is its own literal authored `slot`, unrebalanced.
func _shot_1_everything_unlocked() -> void:
	var layout := _make_layout()
	var all_ids := _all_ids(layout)
	var window := get_viewport_rect().size
	var rects := WallPacker.pack(layout, all_ids, window.x / window.y)
	print("SHOT1 packed=%d of %d" % [rects.size(), all_ids.size()])
	_rebuild_pictures(layout, rects)
	_frame_wall_view(rects, window)
	await _capture("01_wall_view_everything_unlocked")

# ------------------------------------------------------------------ shot 2

## Wall view, a PARTIAL unlock set -- exactly where GAP-010's `_rebalanced_angles()` re-sequences
## the survivors in authored order and spreads them EVENLY around the full circle, rather than
## leaving them at their original (now gappy) authored angles.
func _shot_2_partial_unlock() -> void:
	var layout := _make_layout()
	var all_ids := _all_ids(layout)
	# Home plus FOUR CONSECUTIVE non-home pictures (indices 1-4 of 12, all authored within one
	# 90-degree arc, slots 30/60/90/120) -- deliberately CLUSTERED, not already-evenly-spaced.
	# Picking every Nth authored picture here would keep them evenly spaced by pure arithmetic
	# coincidence (12/N authored slots stay N apart) and PROVE NOTHING about rebalancing actually
	# firing -- exactly the "fixture chosen so the code passes" trap ASSUMPTIONS.md/HANDOFF already
	# warn about elsewhere in this run. A clustered pick only looks evenly spread in the shot if
	# `_rebalanced_angles()` genuinely redistributed it.
	var unlocked : Array[StringName] = [layout.home_id, all_ids[1], all_ids[2], all_ids[3], all_ids[4]]
	var window := get_viewport_rect().size
	var rects := WallPacker.pack(layout, unlocked, window.x / window.y)
	print("SHOT2 packed=%d of %d unlocked (of %d authored)" \
			% [rects.size(), unlocked.size(), all_ids.size()])
	_rebuild_pictures(layout, rects)
	_frame_wall_view(rects, window)
	await _capture("02_wall_view_partial_unlock_rebalanced")

# ------------------------------------------------------------------ shot 3

## Mid-transition, during the TRAVEL phase (the plateau, both frames guaranteed in view by
## `_wide_zoom()`'s own construction, T4/T7's own definition of that phase) -- driven by
## `WallTransition.sample_at()` directly (a pure function, no live Tween needed for a still shot)
## so the camera lands EXACTLY at the phase midpoint, deterministically.
func _shot_3_mid_transition() -> void:
	# Reuses the same full unlocked pack/pictures as shot 1 so the rest of the wall provides
	# spatial context around the two frames actually in transition.
	var layout := _make_layout()
	var all_ids := _all_ids(layout)
	var window := get_viewport_rect().size
	var rects := WallPacker.pack(layout, all_ids, window.x / window.y)
	_rebuild_pictures(layout, rects)

	var by_id : Dictionary[StringName, PictureRect] = {}
	for r : PictureRect in rects: by_id[r.id] = r
	var source_rect : PictureRect = by_id[layout.home_id]
	# The picture furthest from home in authored order -- a long, visually obvious travel.
	var dest_id : StringName = all_ids[all_ids.size() / 2]
	var dest_rect : PictureRect = by_id[dest_id]

	var settings := PlayerSettings.new()
	settings.base_delay = 1.0
	settings.wall_transition_delay = 1.0
	var total := WallTransition.total_duration(settings)
	var bounds := WallTransition.phase_bounds(settings)
	var travel_mid : float = (bounds["travel_start"] + bounds["travel_end"]) * 0.5 * total
	var sample := WallTransition.sample_at(travel_mid, total, source_rect, dest_rect, window,
			settings)
	print("SHOT3 travel_mid=%.4f camera_pos=%s camera_zoom=%.4f source_in_view=%s dest_visible=%s" \
			% [travel_mid, sample.camera_position, sample.camera_zoom, sample.source_frame_in_view,
					sample.dest_visible])

	var camera : Camera2D = _wall.get_node(^"%Camera2D")
	camera.position = sample.camera_position
	camera.zoom = Vector2.ONE * sample.camera_zoom
	await _capture("03_mid_transition_travel_phase")

# ------------------------------------------------------------------ shot 4

## A landed, FOCUSED picture at rest -- WallPicture.focus() (S13's own NEAREST-at-rest trigger)
## plus the camera framed by focused_scale() (H3, Q27=c: fill-and-crop, never fit), same recipe
## wall_overfill_snapshot.gd (S37) already uses for a single picture at rest.
func _shot_4_landed_focused() -> void:
	var layout := _make_layout()
	var all_ids := _all_ids(layout)
	var window := get_viewport_rect().size
	var rects := WallPacker.pack(layout, all_ids, window.x / window.y)
	_rebuild_pictures(layout, rects)

	var target_id : StringName = all_ids[3]
	var target : WallPicture = null
	for wp : WallPicture in _pictures:
		if wp.rect.id == target_id: target = wp
	target.focus()

	var camera : Camera2D = _wall.get_node(^"%Camera2D")
	var scale := WallPicture.focused_scale(target.rect.size, window,
			SettingsManager.settings.wall_overfill_margin)
	camera.zoom = Vector2.ONE * scale
	camera.position = target.rect.centre
	await _capture("04_landed_focused_picture_at_rest")

# ------------------------------------------------------------------ shot 5

## Wall view at 32:9 -- G13's extreme, the aspect the ellipse clamp (`WallLayout.
## ellipse_aspect_max`, here 2.6, same value every other snapshot in this folder uses) exists to
## save: the PACKING is computed against the CLAMPED aspect, while the CAMERA still fills/crops
## the real, unclamped 32:9 window (G9) -- two different aspects in the same shot, on purpose.
func _shot_5_extreme_aspect() -> void:
	DisplayServer.window_set_size(Vector2i(2560, 720))   # 32:9 exactly
	await get_tree().process_frame
	await get_tree().process_frame
	var window := get_viewport_rect().size
	print("SHOT5 window=%s aspect=%.4f" % [window, window.x / window.y])

	var layout := _make_layout()
	var all_ids := _all_ids(layout)
	var rects := WallPacker.pack(layout, all_ids, window.x / window.y)
	print("SHOT5 packed=%d of %d, layout ellipse_aspect_max=%.2f (clamps the PACKING aspect; the " \
			% [rects.size(), all_ids.size(), layout.ellipse_aspect_max]
			+ "CAMERA still fills/crops the real window aspect, G9/G13)")
	_rebuild_pictures(layout, rects)
	_frame_wall_view(rects, window)
	await _capture("05_wall_view_32x9_extreme_aspect")

# ------------------------------------------------------------------ shared plumbing

func _all_ids(layout: WallLayout) -> Array[StringName]:
	var out : Array[StringName] = []
	for e : PictureEntry in layout.pictures: out.append(e.id)
	return out

## Tears down whatever pictures the previous shot built, then builds fresh ones for `rects` (each
## with a swatch frame colour and a flat-colour content screen FILLING the picture's own
## design_size -- see the file header for why it is not a small fixed swatch).
func _rebuild_pictures(layout: WallLayout, rects: Array[PictureRect]) -> void:
	for wp : WallPicture in _pictures:
		if is_instance_valid(wp): wp.queue_free()
	_pictures.clear()
	var by_id : Dictionary[StringName, PictureEntry] = {}
	for e : PictureEntry in layout.pictures: by_id[e.id] = e
	var viewports : Node = _wall.get_node(^"%Viewports")
	var pictures_root : Node = _wall.get_node(^"%Pictures")
	var i := 0
	for rect : PictureRect in rects:
		var entry : PictureEntry = by_id[rect.id]
		var color : Color = SWATCH_COLORS[i % SWATCH_COLORS.size()]
		entry.frame_texture = _swatch_texture(color)
		entry.scene = _content_scene(color.lightened(0.35), entry.design_size)
		var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
		pictures_root.add_child(wp)
		wp.build(rect, entry, viewports)
		_pictures.append(wp)
		i += 1

## G9's own formula (Wall.wall_view_zoom/`_wall_extent`, called directly here since this snapshot
## already has `rects` in hand and does not need Wall's private helper): fill-and-crop the union
## of every packed frame's OUTER rect into the window.
func _frame_wall_view(rects: Array[PictureRect], window: Vector2) -> void:
	var bbox := Rect2()
	var first := true
	for rect : PictureRect in rects:
		var frame := WallPacker.frame_outer_rect(rect)
		bbox = frame if first else bbox.merge(frame)
		first = false
	var camera : Camera2D = _wall.get_node(^"%Camera2D")
	if bbox.size.x <= 0.0 or bbox.size.y <= 0.0:
		camera.zoom = Vector2.ONE
		camera.position = Vector2.ZERO
		return
	camera.zoom = Vector2.ONE * WallPicture.focused_scale(bbox.size, window,
			SettingsManager.settings.wall_overfill_margin)
	camera.position = bbox.get_center()

## A reasonably rich 12-picture synthetic "full picture set" -- no real catalog exists yet (the
## layout tool's own saved output, PLAN.md S34, Phase 8, out of scope). Spread evenly around the
## authored circle, varied size/frame/aspect-keeping, same spirit as the fuzz soak's own
## `_make_layout()` (Tests/Visual/wall_transition_fuzz_soak.gd) but sized for a legible screenshot
## rather than a stress soak.
func _make_layout() -> WallLayout:
	var l := WallLayout.new()
	l.gap_px = 24.0
	l.ellipse_aspect_min = 1.2
	l.ellipse_aspect_max = 2.6
	l.home_id = &"verify_home"
	var pics : Array[PictureEntry] = []
	var step := 360.0 / float(PICTURE_COUNT)
	for i : int in PICTURE_COUNT:
		var id := &"verify_home" if i == 0 else StringName("verify_p%d" % i)
		var e := PictureEntry.new()
		e.id = id
		e.slot = int(step * float(i))
		e.size_multiplier = 0.7 + 0.7 * (float(i % 4) / 3.0)
		var side := 8.0 + 6.0 * float(i % 3)
		e.frame_px = Vector4(side, side, side * (1.0 if i % 4 != 0 else 2.5), side)
		e.keep_aspect = (i % 5 == 0)
		e.design_size = Vector2i(700, 700) if e.keep_aspect else Vector2i(1152, 648)
		pics.append(e)
	l.pictures = pics
	return l

func _swatch_texture(color: Color) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

## Fills the WHOLE picture (design_size), not a small fixed swatch -- a small corner swatch (the
## first version of this file) reads as a rendering bug rather than "content exists here" once the
## camera zooms out far enough to see many pictures at once.
func _content_scene(color: Color, design_size: Vector2i) -> PackedScene:
	var rect := ColorRect.new()
	rect.size = Vector2(design_size)
	rect.color = color
	var packed := PackedScene.new()
	packed.pack(rect)
	rect.free()
	return packed

## Two frames (state settle + actually drawn), then a direct save_png() -- same recipe every other
## Tests/Visual snapshot in this folder uses (see the file header for why NOT SnapshotScene.capture()).
func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, file_name]
	img.save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))

## An absolute filesystem path from OUT_DIR if the caller set one, else the user:// fallback --
## lets an external caller aim the PNGs straight at a scratch directory outside the project.
func _resolve_out_dir() -> String:
	var env := OS.get_environment("OUT_DIR")
	if not env.is_empty(): return env
	return FALLBACK_OUT_DIR
