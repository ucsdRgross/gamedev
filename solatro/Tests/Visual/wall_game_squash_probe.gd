extends Node2D
# res://Tests/Visual/wall_game_squash_probe.gd
# ==============================================================================
# THROWAWAY MEASUREMENT PROBE (not part of the suite). Stands up the REAL res://UI/Wall/wall.tscn
# plus ONE real WallPicture built exactly the way wall.gd/main.gd build the "game" picture -- the
# entry itself comes straight out of Wall.load_layout(), the single seam that sizes AND flags it,
# so this probe cannot drift from what production actually ships -- a real GameView attached as
# the live screen (main.gd's attach_screen path) -- then focuses it
# (WallPicture.focus(), the same call main.gd's _focus_picture uses) and screenshots what the
# WallPicture's own Sprite2D actually shows, so the picture's own rescale (`_rescale_screen`) is
# IN THE SHOT, unlike grid_zoom_shot / grid_layer_shot, which both instantiate GameView directly
# and are structurally blind to it.
#
# Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#     OUT_PATH=<path> <console exe> --path solatro res://Tests/Visual/wall_game_squash_probe.tscn
# ==============================================================================

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const WALL_PICTURE_SCENE := preload("res://UI/Wall/wall_picture.tscn")
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const FALLBACK_OUT_DIR := "user://wall_game_squash_probe"
const SAVE_TAG := "wall_game_squash_probe"
const GRID_COUNT := 3

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wall_game_squash_probe needs a REAL renderer.")
		get_tree().quit(1)
		return
	TestSuite.backup_real_save(SAVE_TAG)
	var window_size := Vector2i(1152, 648)
	DisplayServer.window_set_size(window_size)
	await get_tree().process_frame
	await get_tree().process_frame
	window_size = get_viewport().get_visible_rect().size

	var wall : Wall = WALL_SCENE.instantiate()
	add_child(wall)

	# ⚠ Pulled straight from Wall.load_layout() -- the real "game" PictureEntry, with whatever
	# design_size and keep_aspect production actually sets, rather than a hand-copied duplicate
	# that can silently fall out of sync with the seam.
	var loaded_layout := Wall.load_layout()
	var entry : PictureEntry = null
	for e : PictureEntry in loaded_layout.pictures:
		if e.id == Wall.GAME_PICTURE_ID: entry = e
	print("[wall_game_squash_probe] design_size %s keep_aspect %s"
			% [entry.design_size, entry.keep_aspect])

	var layout := WallLayout.new()
	layout.gap_px = 24.0
	layout.ellipse_aspect_min = 1.2
	layout.ellipse_aspect_max = 2.6
	layout.home_id = entry.id
	layout.pictures = [entry] as Array[PictureEntry]

	var window_aspect := float(window_size.x) / float(window_size.y)
	var rects := WallPacker.pack(layout, [entry.id] as Array[StringName], window_aspect)
	print("[wall_game_squash_probe] packed rect.size %s rect.centre %s (window aspect %.4f)"
			% [rects[0].size, rects[0].centre, window_aspect])

	var viewports : Node = wall.get_node(^"%Viewports")
	var pictures_root : Node = wall.get_node(^"%Pictures")
	var wp : WallPicture = WALL_PICTURE_SCENE.instantiate()
	pictures_root.add_child(wp)

	# Real GameView, real deck, real deal -- same fixture shape as the other probes/shots.
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260831)
	var view : GameView = GAME_VIEW_SCENE.instantiate()

	wp.build(rects[0], entry, viewports, view)
	await get_tree().process_frame
	await get_tree().process_frame
	CardEnvironment.CURRENT = view.game
	var g := view.game
	var pa := view.play_area
	while g.state.grids.size() < GRID_COUNT:
		Board.add_grid(g.state, GridData.new())
	while g.state.grids.size() > GRID_COUNT:
		Board.remove_grid(g.state, g.state.grids.size() - 1)
	pa.flush_rebuild()
	await get_tree().process_frame
	# Real deal via the engine's own path (REUSE, not reinvented placement arithmetic) -- two
	# Nexts, the same fixture shape test_interaction.gd's _setup_view() uses.
	await g.next()
	await g.next()
	pa.flush_rebuild()
	await get_tree().process_frame
	pa.open_zoomed_out()

	wp.focus()   # main.gd's own _focus_picture path -- forces UPDATE_ALWAYS + full-res render.

	var camera : Camera2D = wall.get_node(^"%Camera2D")
	var state := WallPicture.resting_state(rects[0], Vector2(window_size), SettingsManager.settings)
	camera.zoom = state["zoom"] * Vector2.ONE
	camera.position = state["position"]
	print("[wall_game_squash_probe] camera position %s zoom %s" % [camera.position, camera.zoom])
	print("[wall_game_squash_probe] screen sprite scale %s"
			% [(wp.get_node(^"%Screen") as Sprite2D).scale])
	print("[wall_game_squash_probe] wall_transition_delay in force = %s"
			% [SettingsManager.settings.wall_transition_delay])

	# ============================================================================================
	# SAMPLING: log the screen sprite scale, rect size, camera zoom/position and viewport render
	# size every frame for SAMPLE_FRAMES frames, with NO input, then wait for it to go still (the
	# `_settle_layout` pattern used elsewhere) so the report can say whether the values ever stop
	# changing and what they settle to -- rather than assuming a single post-focus shot is already
	# steady state.
	# ============================================================================================
	var screen : Sprite2D = wp.get_node(^"%Screen")
	const SAMPLE_FRAMES := 120
	const SHOT_FRAMES := [1, 5, 15, 30, 60, 120]
	var out_path := _resolve_out_path()
	var out_dir := out_path.get_base_dir()
	if out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(out_dir)
	var out_base := out_path.get_basename()
	var out_ext := out_path.get_extension()

	var last_scale := screen.scale
	for frame_i : int in range(1, SAMPLE_FRAMES + 1):
		await get_tree().process_frame
		print("[wall_game_squash_probe] frame %d screen.scale=%s rect.size=%s camera.zoom=%s camera.position=%s viewport.size=%s"
				% [frame_i, screen.scale, wp.rect.size, camera.zoom, camera.position, viewport_size(wp)])
		if frame_i in SHOT_FRAMES:
			await RenderingServer.frame_post_draw
			var shot_img := get_viewport().get_texture().get_image()
			var shot_path := "%s_frame%03d.%s" % [out_base, frame_i, out_ext]
			shot_img.save_png(shot_path)
			print("[wall_game_squash_probe] wrote=%s" % ProjectSettings.globalize_path(shot_path))
		last_scale = screen.scale

	# Settle-until-still wait, same pattern as `_settle_layout()` (grid_layer_shot.gd /
	# test_interaction.gd): keep waiting frames until the screen sprite's scale stops changing, up
	# to a 2s cap, so the report can say definitively whether it ever moves after the sampled window.
	var waited := 0.0
	var still_moving := false
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not is_equal_approx(screen.scale.x, last_scale.x) or \
				not is_equal_approx(screen.scale.y, last_scale.y):
			still_moving = true
			last_scale = screen.scale
		else:
			break
	print("[wall_game_squash_probe] settle wait=%.3fs still_moving_after_sample=%s final scale=%s"
			% [waited, still_moving, screen.scale])

	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("[wall_game_squash_probe] wrote=%s" % ProjectSettings.globalize_path(out_path))

	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

## The SubViewport render-target size backing `wp`'s screen, for the per-frame settling log.
func viewport_size(wp: WallPicture) -> Vector2i:
	return wp.viewport.size

func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return "%s/wall_game_squash.png" % FALLBACK_OUT_DIR
