extends Node2D
# res://Tests/Visual/sidebar_snapshot.gd
# By-eye diagnostic: boots the REAL `main.tscn`, enters the game screen through
# `Main.enter_game()` -- the same path a save's continue takes -- and screenshots the sidebar HUD.

const MAIN_SCENE := preload("res://Levels/main.tscn")
const FALLBACK_OUT_PATH := "user://sidebar_snapshot/game_hud.png"
const TOP_CASE_OUT_PATH := "user://sidebar_snapshot/game_hud_top.png"
const MAP_HUD_OUT_PATH := "user://sidebar_snapshot/map_hud.png"
const MAP_HUD_TOP_OUT_PATH := "user://sidebar_snapshot/map_hud_top.png"
const MENU_OUT_PATH := "user://sidebar_snapshot/menu.png"
const MENU_TOP_OUT_PATH := "user://sidebar_snapshot/menu_top.png"
const TOP_CASE_WINDOW_SIZE := Vector2i(600, 1000)
const SAVE_TAG := "sidebar_snapshot"
# Bound on `_await_deal_settled()`'s poll -- a real hang (not a settle) is a bug the tool should
# surface, not spin on forever.
const DEAL_SETTLE_TIMEOUT_SEC := 5.0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("sidebar_snapshot needs a REAL renderer. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	TestSuite.backup_real_save(SAVE_TAG)
	var window_size := _resolve_window_size()
	DisplayServer.window_set_size(window_size)
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture(MENU_OUT_PATH)

	DisplayServer.window_set_size(TOP_CASE_WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture(MENU_TOP_OUT_PATH)
	DisplayServer.window_set_size(window_size)
	await get_tree().process_frame
	await get_tree().process_frame

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	main.map_scene.start_run(run)
	await main._focus_picture(&"map")
	await _await_map_generated(main.map_scene.controller)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture(MAP_HUD_OUT_PATH)

	DisplayServer.window_set_size(TOP_CASE_WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture(MAP_HUD_TOP_OUT_PATH)
	DisplayServer.window_set_size(window_size)
	await get_tree().process_frame
	await get_tree().process_frame

	await main.enter_game()
	var view := (main._pictures[&"game"].screen_root as GameView)
	CardEnvironment.CURRENT = view.game
	await _await_deal_settled(view)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	_capture(_resolve_out_path())

	DisplayServer.window_set_size(TOP_CASE_WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(TOP_CASE_OUT_PATH)

	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

# Waits for every Entrance card's own move tween to stop running -- the deal's spawn animation --
# so the still is never caught mid-flight. Bounded, not a fixed sleep: it returns the instant the
# board is actually settled.
func _await_deal_settled(view: GameView) -> void:
	var waited := 0.0
	while waited < DEAL_SETTLE_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if _deal_is_settled(view.play_area): return

# The deal spawns its `CardVisual`s deferred, one frame behind `enter_game()`'s own await, so
# "no tween running yet" is a false settle until at least one card has actually arrived.
func _deal_is_settled(pa: PlayArea) -> bool:
	if pa.data_card.is_empty() or not pa.visuals_ready(): return false
	for visual : CardVisual in pa.data_card.values():
		if visual.move_tween and visual.move_tween.is_running():
			return false
	return true

# The map area shows only its loading text until generation finishes -- wait for that state
# rather than a fixed sleep, so the still is never caught mid-generation.
func _await_map_generated(controller: WorldMapController) -> void:
	if controller.is_generated(): return
	await controller.map_ready

func _capture(out_path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var dir := out_path.get_base_dir()
	if dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(out_path)
	print("SIDEBAR_SNAPSHOT wrote=", ProjectSettings.globalize_path(out_path))

func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return FALLBACK_OUT_PATH

## WINDOW_W/WINDOW_H from the environment, else a 16:9 1280x720 window.
func _resolve_window_size() -> Vector2i:
	var w := OS.get_environment("WINDOW_W")
	var h := OS.get_environment("WINDOW_H")
	if w.is_empty() or h.is_empty(): return Vector2i(1280, 720)
	return Vector2i(int(w), int(h))
