extends Node2D
# res://Tests/Visual/main_boot_snapshot.gd
# ==============================================================================
# S30/S31 WIRE-UP VERIFICATION (picture-wall, by-eye only) -- instantiates the REAL
# res://Levels/main.tscn (never a stand-in) as a child, waits for it to render, screenshots, and
# quits. Proves the cold-launch boot (M1) actually shows the start-menu picture focused, not a
# black screen or an error.
#
# One-off diagnostic, run windowed by hand, WITH AN EXTERNAL KILLING TIMEOUT (it calls
# get_tree().quit() itself, but a caller should still bound the process):
#     OUT_PATH=<absolute path> <console exe> --path solatro res://Tests/Visual/main_boot_snapshot.tscn
# ==============================================================================

const MAIN_SCENE := preload("res://Levels/main.tscn")
const FALLBACK_OUT_PATH := "user://main_boot_snapshot/boot.png"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("main_boot_snapshot needs a REAL renderer. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var main : Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var out_path := _resolve_out_path()
	var dir := out_path.get_base_dir()
	if dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(out_path)
	print("MAIN_BOOT_SNAPSHOT wrote=", ProjectSettings.globalize_path(out_path))
	get_tree().quit()

func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return FALLBACK_OUT_PATH
