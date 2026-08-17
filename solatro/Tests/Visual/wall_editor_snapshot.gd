extends Node2D
# res://Tests/Visual/wall_editor_snapshot.gd
# ==============================================================================
# S34 WALL EDITOR VERIFICATION (picture-wall, by-eye only) -- instantiates the REAL
# res://Tools/wall_editor.tscn as a child (never a stand-in), waits for it to pack, screenshots,
# then changes ONE LIVE VALUE (preview_aspect) programmatically and screenshots again, so the two
# images together PROVE the live re-pack happened rather than asserting it. Repo rule 6 ("verify
# visuals by eye") -- nothing here asserts; TEST_PLAN.md §11 explicitly excludes S34 from the
# suite, matching Tools/fx_editor.gd and Tools/spotlight_tool.gd, which have none either.
#
# One-off diagnostic, run windowed by hand, WITH AN EXTERNAL KILLING TIMEOUT (it calls
# get_tree().quit() itself, but a caller should still bound the process):
#     OUT_DIR=<absolute path> <console exe> --path solatro res://Tests/Visual/wall_editor_snapshot.tscn
# ==============================================================================

const WALL_EDITOR_SCENE := preload("res://Tools/wall_editor.tscn")

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wall_editor_snapshot needs a REAL renderer. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var editor : WallEditor = WALL_EDITOR_SCENE.instantiate()
	add_child(editor)
	await _settle()
	_save("wall_editor_before.png")

	# A live edit exactly as the Inspector would make it -- far enough from the starting 16:9 that
	# the ellipse shape and per-ring picture count visibly change, so the SECOND image proves the
	# live re-pack fired rather than merely that a second screenshot was taken.
	editor.preview_aspect = 3.0
	await _settle()
	_save("wall_editor_after_aspect_change.png")

	# §3 Phase 8 gate ("tool opens, writes the resource, and re-opens with the same layout") --
	# a real write, then a SEPARATE fresh disk read (CACHE_MODE_IGNORE, never the same in-memory
	# object) proving the file genuinely landed with the edited content, not merely that
	# ResourceSaver.save() returned OK. The probe value is reverted and re-saved afterward
	# (below) so this diagnostic does not leave the actual shipped layout_default.tres sitting at
	# a throwaway gap_px picked only to make the round-trip observable.
	var default_gap := WallLayout.new().gap_px
	var probe_gap := default_gap + 17.0
	editor.layout.gap_px = probe_gap
	editor.save_now = true
	await get_tree().process_frame
	var reloaded : WallLayout = ResourceLoader.load("res://Assets/Wall/layout_default.tres", "",
			ResourceLoader.CACHE_MODE_IGNORE)
	var ok := reloaded != null and is_equal_approx(reloaded.gap_px, probe_gap) \
			and reloaded.pictures.size() == editor.layout.pictures.size()
	print("WALL_EDITOR_SNAPSHOT save+reload round-trip ok=%s (gap_px=%s, pictures=%s/%s)" \
			% [ok, reloaded.gap_px if reloaded else "null", \
			reloaded.pictures.size() if reloaded else -1, editor.layout.pictures.size()])

	# Leave the actual shipped file at the tool's ordinary seeded default, not the probe value.
	editor.layout.gap_px = default_gap
	editor.save_now = true
	await get_tree().process_frame
	print("WALL_EDITOR_SNAPSHOT restored gap_px=%.1f before final save" % default_gap)

	print("WALL_EDITOR_SNAPSHOT done")
	get_tree().quit()

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

func _save(filename: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir.is_empty(): out_dir = "user://wall_editor_snapshot"
	var out_path := out_dir.path_join(filename)
	if out_path.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	img.save_png(out_path)
	print("WALL_EDITOR_SNAPSHOT wrote=", ProjectSettings.globalize_path(out_path))
