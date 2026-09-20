extends Control

# PHOTOGRAPHS THE LAYER VIEW in the real game picture, focused and at overview zoom. What has to
# read is that a covered cell shows the mark planned for it, and that a cell already played
# correctly says so with the activated rim.

# Run windowed, WITH AN EXTERNAL KILLING TIMEOUT:
#     OUT_DIR=<absolute dir> <console exe> --path solatro res://Tests/Visual/plan_layer_shot.tscn

#Not in all_tests.tscn: it needs a real renderer and is by-eye material.

const OUT_DIR_FALLBACK := "user://plan_layer_shot"
const SAVE_TAG := "plan_layer_shot"
const REVEAL_WATCHDOG := 40.0

var _out_dir : String
var _input : TestInput
var _realized_cell := BoardCoord.new(0, 2, 2, 0)
var _covered_cells : Array[BoardCoord] = [BoardCoord.new(0, 1, 2, 0), BoardCoord.new(0, 3, 2, 0),
		BoardCoord.new(0, 2, 1, 0)]

func _ready() -> void:
	_out_dir = TestGameViewHost.shot_setup(self, OUT_DIR_FALLBACK)
	if _out_dir.is_empty(): return

	var view := await TestGameViewHost.boot_shot_board(self, SAVE_TAG, 20260913)
	_input = TestInput.driving(self, get_viewport())
	var g := view.game
	var pa := view.play_area
	await _settle(view)
	pa.focus_grid(0)
	await _settle(view)

	await _cover_the_cells(view)
	await _open_the_layer(pa)
	await _shoot(view, "layer_focused")

	pa.open_zoomed_out()
	pa.rest_board()
	await _settle(view)
	await _shoot(view, "layer_overview")

	TestGameViewHost.shot_teardown(SAVE_TAG)
	get_tree().quit()

# FOUR COVERED CELLS, one of them REALIZED: its mark is granted from the very card about to land on
# it, so the marks layer has a cell that was played correctly as well as three that were not.
func _cover_the_cells(view: GameView) -> void:
	var g := view.game
	var first := _an_entrance_card(g, view.play_area)
	g.effect_api.grant_mark(_realized_cell, _source(first.rank, first.suit))
	view.play_area.flush_rebuild()
	await _settle(view)
	await _land_a_card(view, first, _realized_cell)
	for coord : BoardCoord in _covered_cells:
		var card := _an_entrance_card(g, view.play_area)
		if not card: continue
		await _land_a_card(view, card, coord)

# The card this shot picks up: one the board offers as a focus target in the Entrance, which is what
# a pointer or a focus ring can reach.
func _an_entrance_card(g: Game, pa: PlayArea) -> CardData:
	for control : Control in pa.ui_data:
		var data : CardData = pa.ui_data[control]
		if control.focus_mode != Control.FOCUS_ALL or not control.is_visible_in_tree(): continue
		if g.state.grid_position_of(data).is_entrance(): return data
	return null

# THROUGH THE PLATFORM'S OWN ROUTE, not an api call: what is photographed is the board a player's
# own placements produce.
func _land_a_card(view: GameView, card: CardData, coord: BoardCoord) -> void:
	var pa := view.play_area
	var g := view.game
	await _input.click(_centre_of(pa, card))
	await _input.click(_centre_of(pa, g.state.cell_type_at(coord)))
	var waited := 0.0
	while waited < REVEAL_WATCHDOG and g.state.card_at(coord) != card:
		await get_tree().process_frame
		waited += get_process_delta_time()
	pa.flush_rebuild()
	await pa.await_card_settled(card)
	await _settle(view)
	print("[plan_layer_shot] (%d,%d) covered by %s: %s"
			% [coord.x, coord.y, str(card), str(g.state.card_at(coord) == card)])

#The source card a mark is copied from, carrying DUPLICATE pips: handing over a live card's own
#pip rebinds its backref and takes that card off the board.
func _source(rank: PipRank, suit: PipSuit) -> CardData:
	var source := CardData.new()
	source.with_rank(rank.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as PipRank)
	source.with_suit(suit.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as PipSuit)
	return source

# OPENED THE WAY A PLAYER OPENS IT -- the held action, delivered through the viewport -- and left
# held for the rest of the run, because letting it go is what closes the view.
func _open_the_layer(pa: PlayArea) -> void:
	for event : InputEvent in InputMap.action_get_events(&"ui_plan_layer"):
		var key := event as InputEventKey
		if not key: continue
		await _input.key_press(key.keycode)
		break
	await get_tree().process_frame
	print("[plan_layer_shot] the layer view is open: %s" % str(pa.plan_layer_open))

func _centre_of(pa: PlayArea, card: CardData) -> Vector2:
	return (pa.data_ui[card] as Control).get_global_rect().get_center()

# One picture plus the numbers behind it: how many cells are drawing their mark, how many of those
# wear the activated rim, and how many played cards stepped aside -- so a blank frame cannot pass
# for a capture.
func _shoot(view: GameView, tag: String) -> void:
	var pa := view.play_area
	var g := view.game
	var drawn := 0
	var rimmed := 0
	var hidden := 0
	var played := 0
	for gi : int in g.state.grids.size():
		var grid : GridData = g.state.grids[gi]
		for ci : int in grid.cell_types.size():
			var visual : CardVisual = pa.data_card.get(grid.cell_types[ci])
			if visual and visual.mark_drawn and BoardPlan.is_marked(grid.cell_types[ci]): drawn += 1
			if visual and visual.matched_properties != 0 \
					and visual.match_rim_index == PaletteDB.ROLES.match_rim_active: rimmed += 1
			for card : CardData in grid.cells[ci].datas:
				played += 1
				var card_visual : CardVisual = pa.data_card.get(card)
				if card_visual and not card_visual.visible: hidden += 1
	print("[plan_layer_shot] %s: layer open %s, cells drawn as marks %d, realized cells rimmed %d, "
			% [tag, str(pa.plan_layer_open), drawn, rimmed]
			+ "played cards hidden %d of %d, board zoom %.3f" % [hidden, played, pa.board_zoom])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out_dir, tag])
	print("[plan_layer_shot] wrote %s.png" % tag)

#Waits for the board to stop moving, so no shot is taken mid-transition.
func _settle(view: GameView) -> void:
	var last := Vector2(INF, INF)
	for _frame : int in 180:
		await get_tree().process_frame
		var now := view.play_area.slot_center_global(BoardCoord.new(0, 0, 0, 0))
		if now.is_equal_approx(last): return
		last = now
