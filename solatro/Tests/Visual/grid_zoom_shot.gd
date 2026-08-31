extends Control

## Photographs and MEASURES the board inside the REAL game picture, in both view modes.
##
## ⚠ **THE INSTRUMENT `grid_layer_shot` IS NOT.** That one renders the board straight into a
## 1152x648 window, so for a multi-grid board its framing is a harness artefact: the real board
## lives in a SubViewport sized `PlayArea.game_picture_design_size` and occupies only the
## `PlayContainer` rect inside it. Every "is the grid cut off" question is about THAT rectangle,
## and only this scene puts it on screen.
##
## Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
##     OUT_DIR=<absolute dir> <console exe> --path solatro res://Tests/Visual/grid_zoom_shot.tscn
##
## Deliberately NOT in all_tests.tscn: needs a real renderer and is by-eye material.

const OUT_DIR_FALLBACK := "user://reveal_shots"
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const SAVE_TAG := "grid_zoom_shot"
const GRID_COUNT := 3

var _out_dir : String

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("grid_zoom_shot needs a REAL renderer: --headless never fires frame_post_draw.")
		get_tree().quit(1)
		return
	_out_dir = OS.get_environment("OUT_DIR")
	if _out_dir.is_empty(): _out_dir = OUT_DIR_FALLBACK
	if _out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(_out_dir)
	TestSuite.backup_real_save(SAVE_TAG)

	var design := PlayArea.game_picture_design_size(SettingsManager.settings)
	print("[grid_zoom_shot] picture design_size %d x %d" % [design.x, design.y])
	DisplayServer.window_set_size(design)
	await get_tree().process_frame

	# The picture IS a SubViewport at the design size; the wall camera only displays it. Standing
	# the real GameView up in one of exactly that size reproduces the product's board geometry
	# without the wall's own transform in the way.
	var holder := SubViewportContainer.new()
	holder.stretch = false
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var vp := SubViewport.new()
	vp.size = design
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260830)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	vp.add_child(view)
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

	# Cards on the board, so the shot shows what a player sees rather than an empty lattice.
	for gi : int in GRID_COUNT:
		var grid : GridData = g.state.grids[gi]
		for x : int in mini(5, grid.grid_width):
			var card := g.draw_card()
			if not card: break
			await g.place_card_in_grid(card, BoardCoord.new(gi, x, 0, 0))
	pa.flush_rebuild()
	await _settle(view)

	pa.open_zoomed_out()
	await _settle(view)
	await _shoot(pa, "overview")
	pa.focus_grid(1)
	await _settle(view)
	await _shoot(pa, "focused")

	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

## One shot plus the numbers behind it: the board window inside the picture, and every grid's
## CELL BLOCK against it. Off-screen is reported per grid because the "no cut-off" rule speaks
## only about the focused one.
func _shoot(pa: PlayArea, tag: String) -> void:
	var sc := pa.scroll_container
	var z := sc.scale.x
	var left := sc.global_position.x
	var right := left + sc.size.x * z
	var top := sc.global_position.y
	var bottom := top + sc.size.y * z
	print("[grid_zoom_shot] %s board window x [%.1f .. %.1f] w %.1f, y [%.1f .. %.1f] h %.1f"
			% [tag, left, right, right - left, top, bottom, bottom - top])
	var block := PlayArea.grid_block_size_px(SettingsManager.settings, GridData.new())
	print("[grid_zoom_shot] %s unscaled grid block %.1f x %.1f, board_zoom %.4f, live scale %.4f"
			% [tag, block.x, block.y, pa.board_zoom, pa.scroll_container.scale.x])
	for gi : int in pa.grid_container.get_child_count():
		var panel := pa.grid_container.get_child(gi) as Control
		var cells := pa._cells_root(panel)
		var r := Rect2(cells.global_position, cells.size * z)
		var off := maxf(maxf(left - r.position.x, 0.0), maxf(r.end.x - right, 0.0))
		print("[grid_zoom_shot] %s grid %d cells x [%.1f .. %.1f] w %.1f, y [%.1f .. %.1f] h %.1f, off-screen %.1f%s"
				% [tag, gi, r.position.x, r.end.x, r.size.x, r.position.y, r.end.y, r.size.y, off,
				"" if off <= 0.5 else "   <-- CUT OFF"])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/grid_zoom_%s.png" % [_out_dir, tag])
	print("[grid_zoom_shot] wrote grid_zoom_%s.png" % tag)

## Waits until the board stops moving, so a shot is never taken mid-transition.
func _settle(view: GameView) -> void:
	var pa := view.play_area
	var last := Vector2(INF, INF)
	var waited := 0.0
	while waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		CardEnvironment.CURRENT = view.game
		var cells := pa._cells_root(pa.grid_container.get_child(0) as Control)
		var now := cells.get_global_rect().position
		if now.is_equal_approx(last): return
		last = now
