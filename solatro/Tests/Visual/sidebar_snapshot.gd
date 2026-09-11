extends Node2D
# res://Tests/Visual/sidebar_snapshot.gd
# By-eye diagnostic: boots the REAL `main.tscn`, enters the game screen through
# `Main.enter_game()` -- the same path a save's continue takes -- and screenshots the sidebar HUD.

const MAIN_SCENE := preload("res://Levels/main.tscn")
const FALLBACK_OUT_PATH := "user://sidebar_snapshot/game_hud.png"
const TOP_CASE_OUT_PATH := "user://sidebar_snapshot/game_hud_top.png"
const TOP_CASE_WINDOW_SIZE := Vector2i(600, 1000)
const SAVE_TAG := "sidebar_snapshot"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("sidebar_snapshot needs a REAL renderer. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	TestSuite.backup_real_save(SAVE_TAG)
	DisplayServer.window_set_size(_resolve_window_size())
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	await main.enter_game()
	await get_tree().process_frame
	await get_tree().process_frame
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
