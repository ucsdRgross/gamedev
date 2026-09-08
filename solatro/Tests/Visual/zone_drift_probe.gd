extends Node2D
# res://Tests/Visual/zone_drift_probe.gd
# ==============================================================================
# DO A ROW'S ZONE CARDS STAY ON ONE LINE WHEN ITS STACKS ARE UNEVEN? (not part of the suite)
#
# The board carries TWO independent position sources for the same card:
#   * `PlayArea.slot_center_global()` -- pure arithmetic over the data (row heights, depth pitch,
#     the board's floor). Props, score labels and placement targets read this.
#   * `CardVisual.get_card_control_center()` -- `control.global_position.y + control.size.y -
#     card_h/2`, i.e. the LIVE CONTROL RECT. The card visuals themselves read this.
# They agree only while every container hands out exactly the rect the arithmetic predicts. This
# probe measures the gap directly, per cell, on a row whose cells are deliberately UNEVEN -- the
# only shape that can tell a per-cell error from a whole-row offset.
#
# It also re-measures after a HOVER, because `on_control_focus_entered` writes
# `custom_minimum_size` on the hovered slot's top card AND on its zone control.
#
# Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#     <console exe> --path solatro res://Tests/Visual/zone_drift_probe.tscn
# ==============================================================================

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const SAVE_TAG := "zone_drift_probe"
## Depths for row 0's five cells. ⚠ UNEVEN ON PURPOSE, and it includes an EMPTY cell: an even row
# cannot distinguish "every zone is on the row's bottom line" from "every zone is at its own
# stack's bottom", and those are the same picture until one cell differs.
const DEPTHS : Array[int] = [3, 1, 0, 5, 2]

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("zone_drift_probe hosts a real GameView. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	TestSuite.backup_real_save(SAVE_TAG)
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260903)

	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	for _i : int in 8:
		await get_tree().process_frame
	CardEnvironment.CURRENT = view.game
	var g := view.game
	var pa := view.play_area

	for x : int in DEPTHS.size():
		for h : int in DEPTHS[x]:
			var card := g.draw_card()
			if not card: break
			await g.place_card_in_grid(card, BoardCoord.new(0, x, 0, h))
	pa.flush_rebuild()
	for _i : int in 20:
		await get_tree().process_frame

	_measure(pa, g, "at rest, overview")
	pa.focus_grid(0)
	for _i : int in 30:
		await get_tree().process_frame
	_measure(pa, g, "at rest, FOCUSED")

	# The hover path writes custom_minimum_size on the hovered slot's top card and its zone
	# control. Drive it through the real signal, not by calling the handler.
	var slot := _slot(pa, g, 3)
	if slot and slot.get_child_count() > 0:
		(slot.get_child(0) as Control).grab_focus()
	for _i : int in 20:
		await get_tree().process_frame
	_measure(pa, g, "FOCUSED, with cell x=3's top card HOVERED")

	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

func _slot(pa: PlayArea, g: Game, x: int) -> VBoxContainer:
	var grid : GridData = g.state.grids[0]
	var panel : Control = pa.grid_container.get_child(0)
	return pa._cell_slot(panel, grid, grid.cell_index(x, 0))

## Per cell of row 0: where the zone CONTROL is, where its CARD VISUAL actually draws, and what
## `get_card_control_center()` makes of that control -- plus the same for the stack's top card.
func _measure(pa: PlayArea, g: Game, tag: String) -> void:
	var grid : GridData = g.state.grids[0]
	print("[zone_drift_probe] === %s === board_zoom %.4f" % [tag, pa.board_zoom])
	var zone_ys : Array[float] = []
	for x : int in DEPTHS.size():
		var ci := grid.cell_index(x, 0)
		var slot := _slot(pa, g, x)
		if not slot: continue
		var zone_control : Control = slot.get_child(-1)
		var zone_card : CardData = grid.cell_types[ci]
		var vis : CardVisual = pa.data_card.get(zone_card)
		var zone_rect := zone_control.get_global_transform() * Rect2(Vector2.ZERO, zone_control.size)
		var vis_y : float = vis.global_position.y if vis else NAN
		zone_ys.append(vis_y)
		# The arithmetic's answer for the card that sits ON the row's bottom line: height 0.
		var model := pa.slot_center_global(BoardCoord.new(0, x, 0, 0))
		print("[zone_drift_probe]  x=%d depth=%d | slot h=%.1f | ZONE control y [%.1f..%.1f] h=%.1f | ZONE visual y=%.1f | h0 model y=%.1f | visual-model=%.1f"
				% [x, DEPTHS[x], slot.size.y * pa.board_zoom,
				zone_rect.position.y, zone_rect.end.y, zone_rect.size.y,
				vis_y, model.y, vis_y - model.y])
	var lo := INF
	var hi := -INF
	for y : float in zone_ys:
		lo = minf(lo, y)
		hi = maxf(hi, y)
	print("[zone_drift_probe]  ROW 0 ZONE SPREAD = %.2f px (0.00 == every zone card on one line)"
			% [hi - lo])
