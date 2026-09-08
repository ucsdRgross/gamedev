extends Control
# res://Tests/Visual/standalone_view_shot.gd
# ==============================================================================
# THE OWNER'S OWN F6: res://Levels/game_view.tscn run on its own, with NO wall, NO SubViewport and
# NO camera, so the view lays out at the OS WINDOW's size rather than the picture's.
#
# ⚠ THIS IS A DIFFERENT POSE FROM `focused_pose_probe`, and both are real. The wall gives the view
# an 841-tall canvas; a bare window gives it whatever the window is. Anything that assumes the
# picture's height is wrong in exactly this scene, which is the one the owner opens to look at the
# board.
#
# Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#     OUT_PATH=<path> <console exe> --path solatro res://Tests/Visual/standalone_view_shot.tscn
# ==============================================================================

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const SAVE_TAG := "standalone_view_shot"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("standalone_view_shot needs a REAL renderer.")
		get_tree().quit(1)
		return
	TestSuite.backup_real_save(SAVE_TAG)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ⚠ **A SubViewport, NOT `DisplayServer.window_set_size`.** The OS refuses a window narrower
	# than the project's minimum -- asking for 412 x 892 got 1152 x 2494 back -- so a screen-size
	# sweep driven through the real window silently tests the same size four times. A SubViewport
	# takes whatever size it is given, and it is also what the wall hosts the view in.
	var holder := SubViewportContainer.new()
	holder.stretch = false
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var vp := SubViewport.new()
	vp.size = _window_knob()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)
	await get_tree().process_frame
	await get_tree().process_frame
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260903)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	vp.add_child(view)
	for _i : int in 8:
		await get_tree().process_frame
	CardEnvironment.CURRENT = view.game
	await view.game.next()
	for _i : int in 30:
		await get_tree().process_frame
	var pa := view.play_area
	var bar := pa.scroll_container.get_v_scroll_bar()
	print("[standalone_view_shot] window=%s play_container=%s play_area=%s"
			% [vp.size, view.play_container.size, pa.size])
	print("[standalone_view_shot] view_mode=%d board_zoom=%.4f grids=%d"
			% [pa.view_mode, pa.board_zoom, pa.grid_container.get_child_count()])
	print("[standalone_view_shot] V-SCROLLBAR visible=%s (max %.1f, page %.1f)"
			% [bar.visible if bar else false, bar.max_value if bar else -1.0,
			bar.page if bar else -1.0])
	var cells := pa._cells_root(pa.grid_container.get_child(0) as Control)
	var block := cells.get_global_transform() * Rect2(Vector2.ZERO, cells.size)
	var strip := pa.entrance_h_track.get_global_transform() 			* Rect2(Vector2.ZERO, pa.entrance_h_track.size)
	var panel : Control = pa.grid_container.get_child(0)
	print("[standalone_view_shot] scroller rect=%s (local) content TopLevelVBox=%s min=%s"
			% [pa.scroll_container.size, pa.top_level_vbox.size,
			pa.top_level_vbox.custom_minimum_size])
	print("[standalone_view_shot] grid_container=%s panel=%s cells=%s  panel-cells=%.1f"
			% [pa.grid_container.size, panel.size, cells.size, panel.size.y - cells.size.y])
	print("[standalone_view_shot] block_h=%.1f strip_base=%.1f pad=%.1f  fit sum=%.1f"
			% [PlayArea.grid_block_size_px(SettingsManager.settings, GridData.new()).y,
			PlayArea.entrance_strip_height_px(SettingsManager.settings, 1.0),
			PlayArea.board_edge_pad_px(SettingsManager.settings),
			PlayArea.grid_block_size_px(SettingsManager.settings, GridData.new()).y
			+ PlayArea.entrance_strip_height_px(SettingsManager.settings, 1.0)
			+ 2.0 * PlayArea.board_edge_pad_px(SettingsManager.settings)])
	for c : Node in panel.get_children():
		print("[standalone_view_shot]   panel child %s size=%s min=%s"
				% [c.name, (c as Control).size, (c as Control).get_combined_minimum_size()])
	print("[standalone_view_shot]   panel separation=%d  grid_container min=%s"
			% [panel.get_theme_constant("separation"),
			pa.grid_container.get_combined_minimum_size()])
	var hb := pa.scroll_container.get_h_scroll_bar()
	var sb := pa.scroll_container.get_theme_stylebox("panel")
	print("[standalone_view_shot]   stylebox=%s  h_bar visible=%s min=%s size=%s"
			% [sb, hb.visible if hb else false,
			hb.get_combined_minimum_size() if hb else Vector2.ZERO, hb.size if hb else Vector2.ZERO])
	print("[standalone_view_shot]   scroller min=%s  v_bar rect=%s"
			% [pa.scroll_container.get_combined_minimum_size(), bar.size])
	var post_hud_centre := pa.board_inset_left + (pa.size.x - pa.board_inset_left) * 0.5
	print("[standalone_view_shot] hud_inset=%.1f post-HUD centre=%.1f  block centre=%.1f  off=%.1f"
			% [pa.board_inset_left, post_hud_centre, block.position.x + block.size.x * 0.5,
			block.position.x + block.size.x * 0.5 - post_hud_centre])
	print("[standalone_view_shot] CELL BLOCK %s" % [block])
	print("[standalone_view_shot] ENTRANCE TRACK %s" % [strip])
	var win := Rect2(Vector2.ZERO, Vector2(vp.size))
	print("[standalone_view_shot] block inside window=%s   entrance inside window=%s"
			% [win.encloses(block), win.encloses(strip)])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out := _resolve_out_path()
	var dir := out.get_base_dir()
	if dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(dir)
	vp.get_texture().get_image().save_png(out)
	print("[standalone_view_shot] wrote=%s" % ProjectSettings.globalize_path(out))
	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

func _window_knob() -> Vector2i:
	var parts := OS.get_environment("WINDOW").split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(1147, 649)

func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return "user://standalone_view_shot/view.png"
