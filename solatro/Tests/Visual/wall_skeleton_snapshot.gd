extends Node2D
# res://Tests/Visual/wall_skeleton_snapshot.gd
# ==============================================================================
# S9 VERIFICATION (picture-wall PLAN.md S9) — done-when is VISUAL: "the scene runs and shows a
# flat coloured wall with nothing on it." Instantiates the REAL res://UI/Wall/wall.tscn (repo
# rule 5, no mocks in tools), waits for it to actually render, then writes one screenshot to an
# absolute path handed in via the OUT_PATH env var (falls back to user://wall_skeleton_snapshot
# if unset) and quits.
#
# One-off diagnostic, run windowed by hand, WITH AN EXTERNAL KILLING TIMEOUT (it calls
# get_tree().quit() itself, but a caller should still bound the process):
#     <console exe> --path solatro res://Tests/Visual/wall_skeleton_snapshot.tscn
#
# Deliberately NOT in all_tests.tscn: it needs a real renderer, and S9 owes TEST_PLAN.md no rows
# (TestWallPause is S12, TestWallRender is S10/S11 — both out of this run).
# ==============================================================================

const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const FALLBACK_OUT_DIR := "user://wall_skeleton_snapshot"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wall_skeleton_snapshot needs a REAL renderer: --headless never fires "
				+ "frame_post_draw. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1152, 648))

	var wall : Wall = WALL_SCENE.instantiate()
	add_child(wall)

	# Two frames: one for the just-added scene to actually enter and draw, one to be sure it has
	# reached the screen (same discipline as SnapshotScene.capture / pause_time_spike._capture).
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var out_path := _resolve_out_path()
	var dir := out_path.get_base_dir()
	if dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(out_path)
	print("WALL_SKELETON_SNAPSHOT paused=%s" % str(get_tree().paused))
	print("WALL_SKELETON_SNAPSHOT wrote=%s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

## An absolute filesystem path from OUT_PATH if the caller set one, else the user:// fallback —
## lets an external caller aim the PNG straight at a scratch directory outside the project.
func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return "%s/wall_s9_skeleton.png" % FALLBACK_OUT_DIR
