extends Node2D

#The base of the four editor tools' shot scenes: each hosts the REAL tool scene, stages what the
#owner sees in the editor, writes PNGs under OUT_DIR (default user://tool_shots) and quits.
#Run windowed, WITH AN EXTERNAL KILLING TIMEOUT; by-eye material, so it stays out of all_tests.tscn.

const OUT_DIR_FALLBACK := "user://tool_shots"

func _ready() -> void:
	assert(DisplayServer.get_name() != "headless", "a tool shot needs a real renderer")
	await stage()
	get_tree().quit()

## Build and shoot this tool's views; each subclass overrides it.
func stage() -> void:
	pass

func settle(frames : int = 3) -> void:
	for _i : int in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

## Write the window as `file_name` under OUT_DIR and print its absolute path and size.
func save(file_name : String) -> void:
	var img := get_viewport().get_texture().get_image()
	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir.is_empty(): out_dir = OUT_DIR_FALLBACK
	var out_path := out_dir.path_join(file_name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	img.save_png(out_path)
	print("TOOL_SHOT wrote=%s size=%s" % [ProjectSettings.globalize_path(out_path), img.get_size()])
