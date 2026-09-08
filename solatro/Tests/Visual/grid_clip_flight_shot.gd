extends Control

## Photographs a card IN FLIGHT between the Entrance and a grid cell, inside the REAL game picture.
##
## ⚠ **THE ENTRANCE IS PINNED OUTSIDE THE BOARD'S SCROLL CONTAINER AND THE GRIDS ARE INSIDE IT**, so
## a placement carries the card's visual ACROSS that boundary — the one journey a clipped board
## window could cut. A still frame cannot show it: the ease has a DURATION, so this shoots a BURST
## of consecutive frames and prints the flying card's rect against the window on each of them.
##
## Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
##     OUT_DIR=<absolute dir> <console exe> --path solatro res://Tests/Visual/grid_clip_flight_shot.tscn
##
## Deliberately NOT in all_tests.tscn: needs a real renderer and is by-eye material.

const OUT_DIR_FALLBACK := "user://reveal_shots"
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const SAVE_TAG := "grid_clip_flight_shot"
const GRID_COUNT := 3
## How many consecutive frames the burst covers. The ease is exponential toward the anchor, so the
## interesting part is the first few frames after the placement — long enough to see it arrive.
const BURST_FRAMES := 14

var _out_dir : String

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("grid_clip_flight_shot needs a REAL renderer: --headless never fires frame_post_draw.")
		get_tree().quit(1)
		return
	_out_dir = OS.get_environment("OUT_DIR")
	if _out_dir.is_empty(): _out_dir = OUT_DIR_FALLBACK
	if _out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(_out_dir)
	TestSuite.backup_real_save(SAVE_TAG)

	var design := PlayArea.game_picture_design_size(SettingsManager.settings)
	DisplayServer.window_set_size(design)
	await get_tree().process_frame

	# The picture IS a SubViewport at the design size (grid_zoom_shot's comment records why): the
	# board's geometry is only true inside one.
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
	await g.refill_entrance_if_due()
	pa.flush_rebuild()
	pa.focus_grid(1)
	await _settle(view)

	var held := _entrance_card(g)
	if not held:
		push_error("grid_clip_flight_shot: the Entrance holds no card to place.")
		get_tree().quit(1)
		return
	var vis : CardVisual = pa.data_card.get(held)
	print("[grid_clip_flight_shot] placing %s from the Entrance into grid 1" % held.log_str())
	_report_window(pa)
	# NOT awaited: the burst below has to run WHILE the placement's ease is in flight.
	g.place_card_in_grid(held, BoardCoord.new(1, 2, 4, 0))
	for i : int in BURST_FRAMES:
		await RenderingServer.frame_post_draw
		CardEnvironment.CURRENT = g
		_report_card(pa, vis, i)
		var img := vp.get_texture().get_image()
		img.save_png("%s/grid_clip_flight_%02d.png" % [_out_dir, i])
	print("[grid_clip_flight_shot] wrote %d frames to %s" % [BURST_FRAMES, _out_dir])

	# THE TOP EDGE, which the same clip governs: a stack in the focused grid's TOP row grows
	# UPWARD toward the window's top edge, and a card that jumps rises further still.
	await _stack_the_top_row(g, pa, view)
	print("[grid_clip_flight_shot] wrote the top-row stack and jump frames")

	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

## Fills the focused grid's TOP-LEFT cell with as many Entrance cards as it will take, then makes
## the top card JUMP — the two things that reach highest on the board. Shot at each step, and the
## card's own top edge is printed against the window's, because a cut of a few pixels is easier to
## measure than to see.
func _stack_the_top_row(g: Game, pa: PlayArea, view: GameView) -> void:
	var cell := BoardCoord.new(1, 0, 0, 0)
	for i : int in 4:
		await g.refill_entrance_if_due()
		var card := _entrance_card(g)
		if not card: break
		await g.place_card_in_grid(card, cell)
		pa.flush_rebuild()
		await _settle(view)
		var vis : CardVisual = pa.data_card.get(card)
		_report_top(pa, vis, "stack %d" % i)
		var img := view.get_viewport().get_texture().get_image()
		img.save_png("%s/grid_clip_stack_%02d.png" % [_out_dir, i])
	var top := pa.data_card.get(g.state.grids[1].cells[0].datas.back()) as CardVisual
	if not top: return
	top.anim_jump()
	for i : int in 6:
		await RenderingServer.frame_post_draw
		CardEnvironment.CURRENT = g
		_report_top(pa, top, "jump %d" % i)
		var img := view.get_viewport().get_texture().get_image()
		img.save_png("%s/grid_clip_jump_%02d.png" % [_out_dir, i])

## How far a card's own top edge sits ABOVE the board window's top edge — 0 when it is inside.
func _report_top(pa: PlayArea, vis: CardVisual, tag: String) -> void:
	if not is_instance_valid(vis):
		print("[grid_clip_flight_shot] %s: the visual is gone" % tag)
		return
	var sc := pa.scroll_container
	var top : float = sc.global_position.y
	var half : float = vis.card_size.y * 0.5 * vis.scale.y
	var above : float = maxf(top - (vis.global_position.y - half), 0.0)
	print("[grid_clip_flight_shot] %s: card centre %s, %.1f px above the window top"
			% [tag, str(vis.global_position), above])

## The topmost card of the first occupied Entrance slot — the one a player could pick up.
func _entrance_card(g: Game) -> CardData:
	for column : ArrayCardData in g.state.upper_zone:
		if not column.datas.is_empty(): return column.datas.back()
	return null

## The board's window on screen, and the clip state that decides what may paint outside it.
func _report_window(pa: PlayArea) -> void:
	var sc := pa.scroll_container
	var z := sc.scale.x
	var r := Rect2(sc.global_position, sc.size * z)
	print("[grid_clip_flight_shot] board window x [%.1f .. %.1f] y [%.1f .. %.1f], clip_contents %s"
			% [r.position.x, r.end.x, r.position.y, r.end.y, str(sc.clip_contents)])
	print("[grid_clip_flight_shot] entrance strip %s" % [pa.entrance_strip.get_global_rect()])

## Where the flying card is this frame, and how far it hangs BELOW the board window — the edge it
## crosses on the way up out of the Entrance.
func _report_card(pa: PlayArea, vis: CardVisual, frame: int) -> void:
	if not is_instance_valid(vis):
		print("[grid_clip_flight_shot] frame %d: the visual is gone" % frame)
		return
	var sc := pa.scroll_container
	var bottom : float = sc.global_position.y + sc.size.y * sc.scale.y
	var half : float = vis.card_size.y * 0.5 * vis.scale.y
	var below : float = maxf(vis.global_position.y + half - bottom, 0.0)
	print("[grid_clip_flight_shot] frame %d: card centre %s, parent %s, %.1f px below the window"
			% [frame, str(vis.global_position), vis.get_parent().name, below])

## Waits until the board stops moving, so the burst never starts mid-transition.
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
