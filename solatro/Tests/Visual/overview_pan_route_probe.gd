extends Node2D
# res://Tests/Visual/overview_pan_route_probe.gd
# ==============================================================================
# THROWAWAY MEASUREMENT PROBE (not part of the suite). Stands up a REAL `Main` (res://Levels/main.tscn)
# and drives it through the REAL enter-game path (`Main.enter_game()` -> `Main._focus_picture()`),
# then fires REAL `InputEventKey` events matching the `grid_pan_left`/`grid_pan_right` InputMap
# bindings via `Input.parse_input_event()` -- the same route a physical key press takes through
# `PlayArea._unhandled_input()` -- rather than calling `Main._on_overview_pan_requested()` directly.
# Samples `%Camera2D.position`/`zoom` and `PlayArea.pan_grid` every frame across the tween, and
# screenshots at rest before/after a step.
#
# Godot docs (godotengine.org/... InputEvent / Input.parse_input_event): "parse_input_event" feeds
# an event into the engine's input pipeline "as if it came from a device", the same pipeline real
# hardware events take -- the standard way to simulate input in an automated run.
#
# Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#     OUT_PATH=<path> <console exe> --path solatro res://Tests/Visual/overview_pan_route_probe.tscn
# ==============================================================================

const MAIN_SCENE := preload("res://Levels/main.tscn")
const FALLBACK_OUT_DIR := "user://overview_pan_route_probe"
const SAVE_TAG := "overview_pan_route_probe"
const GRID_COUNT := 3
const KEY_COMMA := 44
const KEY_PERIOD := 46

var _out_base : String
var _out_ext : String

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("overview_pan_route_probe needs a REAL renderer.")
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
	get_tree().paused = false   # Wall._ready() sets this globally; undone same as other Wall tests.
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

	var out_path := _resolve_out_path()
	var out_dir := out_path.get_base_dir()
	if out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(out_dir)
	_out_base = out_path.get_basename()
	_out_ext = out_path.get_extension()

	_log_state(camera, pa, "rest before any pan (grid %d of %d)" % [pa.pan_grid, GRID_COUNT])
	await _shoot(camera, "grid%d_rest" % pa.pan_grid)

	# ===== 1) A real pan LEFT input, driven the way a player would press it. =====
	print("[overview_pan_route_probe] ===== STEP 1: grid_pan_left via real key event =====")
	await _sample_across_key(camera, pa, KEY_COMMA, "step1_left")
	await _shoot(camera, "grid%d_after_left" % pa.pan_grid)

	# ===== 2) A real pan RIGHT input (back toward the middle / other direction). =====
	print("[overview_pan_route_probe] ===== STEP 2: grid_pan_right via real key event =====")
	await _sample_across_key(camera, pa, KEY_PERIOD, "step2_right")
	await _shoot(camera, "grid%d_after_right" % pa.pan_grid)

	# ===== 3) Walk to the edge (repeat RIGHT until bounce), then one more (must bounce, not move). =====
	print("[overview_pan_route_probe] ===== STEP 3: walk to the right edge =====")
	for i : int in GRID_COUNT:
		await _sample_across_key(camera, pa, KEY_PERIOD, "step3_right_%d" % i)
	await _shoot(camera, "grid%d_at_edge" % pa.pan_grid)

	# ===== 4) _move_in_flight gating: fire a pan the instant a fresh navigation starts. =====
	print("[overview_pan_route_probe] ===== STEP 4: pan issued mid-transition (_move_in_flight) =====")
	pa.open_zoomed_out()
	await get_tree().process_frame
	var pre_grid := pa.pan_grid
	var pre_cam := camera.position
	main._focus_picture(&"map")   # NOT awaited -- leaves _move_in_flight true mid-transition.
	print("[overview_pan_route_probe] mid-flight: _move_in_flight=%s _current_focus=%s"
			% [main._move_in_flight, main._current_focus])
	_fire_key(KEY_COMMA)
	await get_tree().process_frame
	_fire_key_release(KEY_COMMA)
	print("[overview_pan_route_probe] pan_grid right after mid-flight key: %d (was %d)"
			% [pa.pan_grid, pre_grid])
	# Let the navigation to map finish, then navigate back to game to settle the app.
	var waited := 0.0
	while main._move_in_flight and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	print("[overview_pan_route_probe] map focus settled: _current_focus=%s waited=%.3fs"
			% [main._current_focus, waited])
	await main._focus_picture(&"game")
	await get_tree().process_frame
	await get_tree().process_frame
	print("[overview_pan_route_probe] back on game: pan_grid=%d camera.position=%s (pre-flight was pan_grid=%d camera=%s)"
			% [pa.pan_grid, camera.position, pre_grid, pre_cam])

	# Now issue the SAME pan once settled, for comparison -- does it take effect now?
	print("[overview_pan_route_probe] ===== STEP 4b: same pan, issued once settled =====")
	await _sample_across_key(camera, pa, KEY_COMMA, "step4b_left_settled")

	# ===== 5) Focused mode still crisp/unchanged (H20 sprite scale, board sharp). =====
	print("[overview_pan_route_probe] ===== STEP 5: focused mode check =====")
	pa.focus_grid(1)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var screen_node : Sprite2D = game_wp.get_node(^"%Screen")
	print("[overview_pan_route_probe] FOCUSED: pa.view_mode=%d screen.scale=%s camera.zoom=%s camera.position=%s"
			% [pa.view_mode, screen_node.scale, camera.zoom, camera.position])
	await RenderingServer.frame_post_draw
	var focused_img := get_viewport().get_texture().get_image()
	var focused_path := "%s_focused_check.%s" % [_out_base, _out_ext]
	focused_img.save_png(focused_path)
	print("[overview_pan_route_probe] wrote=%s" % ProjectSettings.globalize_path(focused_path))

	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

## Fires the `pressed` half of a real `InputEventKey` through the engine's own pipeline.
func _fire_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)

## Fires the matching release -- `is_action_pressed` only fires on the press edge, but a real key
## press is press-then-release and leaving it held could confuse the next simulated key.
func _fire_key_release(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = false
	Input.parse_input_event(ev)

## Presses+releases `keycode` (a real InputMap-bound key) and samples camera position/zoom and
## `pan_grid` every frame until the tween settles (position stops changing), up to a 2s cap.
func _sample_across_key(camera: Camera2D, pa: PlayArea, keycode: int, tag: String) -> void:
	var pos_before := camera.position
	var zoom_before := camera.zoom
	var grid_before := pa.pan_grid
	_fire_key(keycode)
	await get_tree().process_frame
	_fire_key_release(keycode)
	var last := camera.position
	var moved := false
	var waited := 0.0
	var frame_i := 0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		frame_i += 1
		if not is_equal_approx(camera.position.x, last.x) or not is_equal_approx(camera.position.y, last.y):
			moved = true
			print("[overview_pan_route_probe][%s] frame %d camera.position=%s zoom=%s pan_grid=%d"
					% [tag, frame_i, camera.position, camera.zoom, pa.pan_grid])
			last = camera.position
		elif frame_i <= 3:
			print("[overview_pan_route_probe][%s] frame %d camera.position=%s zoom=%s pan_grid=%d (unchanged)"
					% [tag, frame_i, camera.position, camera.zoom, pa.pan_grid])
		else:
			break
	print(("[overview_pan_route_probe][%s] SUMMARY before=%s after=%s zoom_before=%s zoom_after=%s "
			+ "grid_before=%d grid_after=%d moved_during_sample=%s waited=%.3fs")
			% [tag, pos_before, camera.position, zoom_before, camera.zoom, grid_before, pa.pan_grid,
			moved, waited])

func _log_state(camera: Camera2D, pa: PlayArea, tag: String) -> void:
	print("[overview_pan_route_probe] STATE[%s] camera.position=%s camera.zoom=%s pan_grid=%d view_mode=%d"
			% [tag, camera.position, camera.zoom, pa.pan_grid, pa.view_mode])

func _shoot(camera: Camera2D, tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s_%s.%s" % [_out_base, tag, _out_ext]
	img.save_png(path)
	print("[overview_pan_route_probe] wrote=%s (camera.position=%s)" % [ProjectSettings.globalize_path(path), camera.position])

func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return "%s/overview_pan_route_probe.png" % FALLBACK_OUT_DIR
