extends Node2D
# res://Tests/Visual/hud_follow_camera_probe.gd
# ==============================================================================
# THROWAWAY MEASUREMENT PROBE (not part of the suite). Copy of `overview_pan_route_probe.gd`'s
# real-input setup, extended to sample the Deck furniture control (`GameView.deck_ui`) alongside
# the wall camera and `PlayArea.pan_grid` every frame across a real OVERVIEW pan, to measure
# whether the HUD (furniture, positioned instantly off `pan_grid` in `GameView._process()`) tracks
# the wall camera (which TWEENS to its new position over `settings.grid_pan_duration`) or leads it.
#
# Maps the Deck's SubViewport-local `global_position.x` into WALL space via the picture's `%Screen`
# sprite (`wall_x = screen.global_position.x + (local_x - viewport.size.x/2) * screen.scale.x`,
# `WallPicture._rescale_screen()`'s own `rect.size / viewport.size` scale), then into a
# camera-relative screen offset (`(wall_x - camera.position.x) * camera.zoom.x`) -- the number the
# player actually sees move.
#
# Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#     OUT_PATH=<path> <console exe> --path solatro res://Tests/Visual/hud_follow_camera_probe.tscn
# ==============================================================================

const MAIN_SCENE := preload("res://Levels/main.tscn")
const FALLBACK_OUT_DIR := "user://hud_follow_camera_probe"
const SAVE_TAG := "hud_follow_camera_probe"
const GRID_COUNT := 3
const KEY_COMMA := 44
const KEY_PERIOD := 46

var _out_base : String
var _out_ext : String

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("hud_follow_camera_probe needs a REAL renderer.")
		get_tree().quit(1)
		return
	TestSuite.backup_real_save(SAVE_TAG)
	var window_size := Vector2i(1280, 720)
	DisplayServer.window_set_size(window_size)
	await get_tree().process_frame
	await get_tree().process_frame

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260901)

	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame

	await main.enter_game()
	await get_tree().process_frame

	var game_wp : WallPicture = main._pictures[&"game"]
	var view : GameView = game_wp.screen_root as GameView
	CardEnvironment.CURRENT = view.game
	var g := view.game
	var pa := view.play_area
	while g.state.grids.size() < GRID_COUNT:
		Board.add_grid(g.state, GridData.new())
	while g.state.grids.size() > GRID_COUNT:
		Board.remove_grid(g.state, g.state.grids.size() - 1)
	pa.flush_rebuild()
	await get_tree().process_frame
	await g.next()
	await g.next()
	pa.flush_rebuild()
	await get_tree().process_frame

	pa.open_zoomed_out()
	await get_tree().process_frame
	await get_tree().process_frame

	var camera : Camera2D = main.wall.get_node(^"%Camera2D")
	var screen : Sprite2D = game_wp.get_node(^"%Screen")
	var deck : Control = view.deck_ui

	var out_path := _resolve_out_path()
	var out_dir := out_path.get_base_dir()
	if out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(out_dir)
	_out_base = out_path.get_basename()
	_out_ext = out_path.get_extension()

	_log_offset(camera, pa, screen, deck, game_wp, "rest before any pan")
	await _shoot(camera, "grid%d_rest" % pa.pan_grid)

	print("[hud_follow_camera_probe] ===== STEP 1: grid_pan_left via real key event =====")
	await _sample_across_key(camera, pa, screen, deck, game_wp, KEY_COMMA, "step1_left")
	await _shoot(camera, "grid%d_after_left" % pa.pan_grid)

	print("[hud_follow_camera_probe] ===== STEP 2: grid_pan_right via real key event =====")
	await _sample_across_key(camera, pa, screen, deck, game_wp, KEY_PERIOD, "step2_right")
	await _shoot(camera, "grid%d_after_right" % pa.pan_grid)

	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

func _fire_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)

func _fire_key_release(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = false
	Input.parse_input_event(ev)

## Deck's SubViewport-local x mapped into wall space through `%Screen`'s own position/scale --
## the SAME mapping `WallPicture._rescale_screen()` uses to draw the SubViewport onto the wall.
func _deck_wall_x(screen: Sprite2D, deck: Control, game_wp: WallPicture) -> float:
	var vp_size := Vector2(game_wp.viewport.size)
	return screen.global_position.x + (deck.global_position.x - vp_size.x / 2.0) * screen.scale.x

## Camera-relative screen-space offset -- what the player actually sees the Deck sit at relative
## to the camera's framed centre, in pixels.
func _screen_offset(camera: Camera2D, wall_x: float) -> float:
	return (wall_x - camera.position.x) * camera.zoom.x

func _log_offset(camera: Camera2D, pa: PlayArea, screen: Sprite2D, deck: Control,
		game_wp: WallPicture, tag: String) -> void:
	var wall_x := _deck_wall_x(screen, deck, game_wp)
	var offset := _screen_offset(camera, wall_x)
	print(("[hud_follow_camera_probe] STATE[%s] pan_grid=%d camera.position.x=%.3f "
			+ "deck.global_position.x(subviewport-local)=%.3f deck_wall_x=%.3f screen_offset_px=%.3f")
			% [tag, pa.pan_grid, camera.position.x, deck.global_position.x, wall_x, offset])

## Fires `keycode`, samples EVERY FRAME (camera position, pan_grid, deck wall_x, screen offset)
## until the camera tween settles (position stops changing), up to a 2s cap.
func _sample_across_key(camera: Camera2D, pa: PlayArea, screen: Sprite2D, deck: Control,
		game_wp: WallPicture, keycode: int, tag: String) -> void:
	var pos_before := camera.position
	var grid_before := pa.pan_grid
	var offset_before := _screen_offset(camera, _deck_wall_x(screen, deck, game_wp))
	_fire_key(keycode)
	await get_tree().process_frame
	_fire_key_release(keycode)
	var last := camera.position
	var waited := 0.0
	var frame_i := 0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		frame_i += 1
		var wall_x := _deck_wall_x(screen, deck, game_wp)
		var offset := _screen_offset(camera, wall_x)
		var still_moving := (not is_equal_approx(camera.position.x, last.x)
				or not is_equal_approx(camera.position.x, camera.position.x))
		print(("[hud_follow_camera_probe][%s] frame %d camera.position.x=%.3f pan_grid=%d "
				+ "deck_wall_x=%.3f screen_offset_px=%.3f")
				% [tag, frame_i, camera.position.x, pa.pan_grid, wall_x, offset])
		var settled := is_equal_approx(camera.position.x, last.x) and frame_i > 3
		last = camera.position
		if frame_i == 1 or frame_i == 3 or frame_i == 6:
			await _shoot(camera, "%s_frame%d" % [tag, frame_i])
		if settled:
			break
	var offset_after := _screen_offset(camera, _deck_wall_x(screen, deck, game_wp))
	print(("[hud_follow_camera_probe][%s] SUMMARY camera_before=%s camera_after=%s "
			+ "grid_before=%d grid_after=%d offset_before_px=%.3f offset_after_px=%.3f waited=%.3fs")
			% [tag, pos_before, camera.position, grid_before, pa.pan_grid,
			offset_before, offset_after, waited])

func _shoot(camera: Camera2D, tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s_%s.%s" % [_out_base, tag, _out_ext]
	img.save_png(path)
	print("[hud_follow_camera_probe] wrote=%s (camera.position=%s)" % [ProjectSettings.globalize_path(path), camera.position])

func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return "%s/hud_follow_camera_probe.png" % FALLBACK_OUT_DIR
