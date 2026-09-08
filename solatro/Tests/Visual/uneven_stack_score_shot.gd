extends Control

## Photographs an UNEVEN-DEPTH board with row scores banked on more than one row, in both
## OVERVIEW and FOCUSED mode, through the real GameView/PlayArea framing (same shape as
## `grid_zoom_shot`). Purpose-built by-eye check for the row-label / height-label alignment
## fix: an even board cannot discriminate a fixed-height gutter from a depth-driven one.
##
## Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
##     OUT_DIR=<absolute dir> <console exe> --path solatro res://Tests/Visual/uneven_stack_score_shot.tscn
##
## THROWAWAY: not in all_tests.tscn, by-eye material only.

const OUT_DIR_FALLBACK := "user://uneven_stack_score_shot"
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const SAVE_TAG := "uneven_stack_score_shot"
const GRID_COUNT := 1

var _out_dir : String

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("uneven_stack_score_shot needs a REAL renderer.")
		get_tree().quit(1)
		return
	_out_dir = OS.get_environment("OUT_DIR")
	if _out_dir.is_empty(): _out_dir = OUT_DIR_FALLBACK
	if _out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(_out_dir)
	TestSuite.backup_real_save(SAVE_TAG)

	var design := PlayArea.game_picture_design_size(SettingsManager.settings)
	print("[uneven_stack_score_shot] picture design_size %d x %d" % [design.x, design.y])
	DisplayServer.window_set_size(design)
	await get_tree().process_frame

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
	seed(20260901)
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

	## Row 0: one card deep. Row 2: three cards deep. Both rows carry a banked score so both
	## actually show a label -- the discriminating case for a fixed-height vs. depth-driven gutter.
	await _stack_row(g, 0, 0, 1)
	await _stack_row(g, 0, 2, 3)
	g.state.bank_line_score(g.state.scores_row, 0, 0, 0, 500)
	g.state.bank_line_score(g.state.scores_row, 0, 2, 0, 700)
	g.state.bank_line_score(g.state.scores_row, 0, 2, 1, 900)
	g.state.bank_line_score(g.state.scores_row, 0, 2, 2, 1100)
	pa.flush_rebuild()
	await _settle(view)

	pa.open_zoomed_out()
	await _settle(view)
	await _shoot(pa, "overview")
	pa.focus_grid(0)
	await _settle(view)
	await _shoot(pa, "focused")

	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

## Draws and places `depth` cards into grid `gi` row `ry` column 0, stacked height 0..depth-1.
func _stack_row(g: Game, gi: int, ry: int, depth: int) -> void:
	for h : int in depth:
		var card := g.draw_card()
		if not card: break
		await g.place_card_in_grid(card, BoardCoord.new(gi, 0, ry, h))

## One shot plus the board window / row geometry, same reporting shape as `grid_zoom_shot`.
func _shoot(pa: PlayArea, tag: String) -> void:
	var sc := pa.scroll_container
	var z := sc.scale.x
	var left := sc.global_position.x
	var right := left + sc.size.x * z
	var top := sc.global_position.y
	var bottom := top + sc.size.y * z
	print("[uneven_stack_score_shot] %s board window x [%.1f .. %.1f] w %.1f, y [%.1f .. %.1f] h %.1f"
			% [tag, left, right, right - left, top, bottom, bottom - top])
	print("[uneven_stack_score_shot] %s board_zoom %.4f, live scale %.4f"
			% [tag, pa.board_zoom, pa.scroll_container.scale.x])
	var panel := pa.grid_container.get_child(0) as Control
	var cells := pa._cells_root(panel)
	for ry : int in cells.get_child_count():
		var row : Control = cells.get_child(ry)
		var r := Rect2(row.global_position, row.size * z)
		print("[uneven_stack_score_shot] %s row %d rect x [%.1f .. %.1f] y [%.1f .. %.1f] h %.1f"
				% [tag, ry, r.position.x, r.end.x, r.position.y, r.end.y, r.size.y])
	var board := panel.get_node_or_null("Board") as Control
	var row_labels := board.get_node_or_null("RowLabels") as Control if board else null
	if row_labels:
		for ry : int in row_labels.get_child_count():
			var stack : Control = row_labels.get_child(ry)
			var r := Rect2(stack.global_position, stack.size * z)
			print("[uneven_stack_score_shot] %s row_label_stack %d rect x [%.1f .. %.1f] y [%.1f .. %.1f] h %.1f"
					% [tag, ry, r.position.x, r.end.x, r.position.y, r.end.y, r.size.y])
			_report_bands(pa, tag, ry, stack, z)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/uneven_stack_%s.png" % [_out_dir, tag])
	print("[uneven_stack_score_shot] wrote uneven_stack_%s.png" % tag)

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

## THE MEASUREMENT THE OWNER'S COMPLAINT NEEDS: every label BAND in a row's stack against the
## PIP ROW of the card it is meant to line up with.
##
## ⚠ **THE TARGET IS THE PIP ROW, NOT THE CARD'S BOTTOM EDGE.** The pips span y 13..23 of a card
## face that runs -27..27, so the card's bottom edge is 4 art units BELOW the thing the player
## reads. "Align to the bottom" is that 4 units off, scaled by `card_scale`.
##
## ⚠ Bands are printed for EVERY height, not only the scored ones: an empty band still occupies
## the stack and still pushes the ones above it.
func _report_bands(pa: PlayArea, tag: String, ry: int, stack: Control, z: float) -> void:
	var art_to_px := CardVisual.card_size_play.y / CardVisual.CARD_SIZE.y
	for i : int in stack.get_child_count():
		var h := stack.get_child_count() - 1 - i
		var label : Control = stack.get_child(i)
		var band := Rect2(label.global_position, label.size * z)
		var centre := pa.slot_center_global(BoardCoord.new(0, 0, ry, h))
		var card_top := centre.y - CardVisual.card_size_play.y * 0.5
		# The pip row's own span, mapped from art units into the card's live pixels.
		var pip_top := card_top + 40.0 * art_to_px
		var pip_bottom := card_top + 50.0 * art_to_px
		var card_bottom := card_top + CardVisual.card_size_play.y
		print("[uneven_stack_score_shot] %s row %d h %d BAND y [%.1f .. %.1f] h %.1f | card y [%.1f .. %.1f] | PIP ROW y [%.1f .. %.1f] | band centre - pip centre = %.1f | text %s"
				% [tag, ry, h, band.position.y, band.end.y, band.size.y, card_top, card_bottom,
				pip_top, pip_bottom,
				(band.position.y + band.end.y) * 0.5 - (pip_top + pip_bottom) * 0.5,
				(label as Label).text if label is Label else "?"])
