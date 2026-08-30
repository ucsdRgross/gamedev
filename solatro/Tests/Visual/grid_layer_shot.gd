extends Control

## Photographs a board with cards ON GRID CELLS, at ONE, TWO and THREE grids.
##
## ⚠ THE ONLY INSTRUMENT THAT SHOWS THIS. `reveal_shot` renders an empty grid, so a card drawing
## BEHIND the cell it sits on was invisible to every existing shot -- which is how it reached the
## owner by eye instead of a test. Draw order in a CanvasItem layer is child index, and an index
## is only meaningful within one layer, so this also prints the two indices next to the picture.
##
## The multi-grid counts exist for the claim a single-grid shot can never show: the board is always
## CENTRED -- 1 grid dead centre, 2 straddling the exact centre, 3 putting the middle grid where a
## single grid sits. Each shot prints every grid centre and the window centre so the picture can be
## checked against numbers rather than impression.

const OUT_DIR := "user://reveal_shots"
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const SAVE_TAG := "grid_layer_shot"
const GRID_COUNTS : Array[int] = [1, 2, 3]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	TestSuite.backup_real_save(SAVE_TAG)
	for n : int in GRID_COUNTS:
		await _shoot_board(n)
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

## One shot at `n` grids: real GameView, cards on real cells, picture plus the numbers behind it.
func _shoot_board(n: int) -> void:
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	seed(20260828)
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	CardEnvironment.CURRENT = view.game
	var g := view.game
	var pa := view.play_area

	if g.state.grids.is_empty():
		print("[grid_layer_shot] NO GRID -- nothing to photograph")
		get_tree().quit()
		return
	# ⚠ `grid_max_count` governs UNLOCKING, not `Board.add_grid`, so a fixture may exceed it.
	while g.state.grids.size() < n:
		Board.add_grid(g.state, GridData.new())
	while g.state.grids.size() > n:
		Board.remove_grid(g.state, g.state.grids.size() - 1)
	pa.flush_rebuild()
	await get_tree().process_frame

	# Fill row 0 from the draw deck, then stack a second card on one cell so a covered cell and a
	# stacked cell are both in frame.
	var grid : GridData = g.state.grids[0]
	var placed : Array[CardData] = []
	for x : int in mini(5, grid.grid_width):
		var card := g.draw_card()
		if not card: break
		await g.place_card_in_grid(card, BoardCoord.new(0, x, 0, 0))
		placed.append(card)
	var stacked := g.draw_card()
	if stacked:
		await g.place_card_in_grid(stacked, BoardCoord.new(0, 2, 0, 1))
	pa.flush_rebuild()
	await _settle_layout(view)

	# The measurement that goes with the picture: a card must sit ABOVE its cell's zone card.
	var worst := 1 << 30
	for x : int in placed.size():
		var cell_type : CardData = grid.cell_types[x]
		var cv : CardVisual = pa.data_card.get(placed[x])
		var zv : CardVisual = pa.data_card.get(cell_type)
		if cv and zv and is_instance_valid(cv) and is_instance_valid(zv):
			print("[grid_layer_shot] n=%d cell %d: card idx %d vs cell idx %d%s"
					% [n, x, cv.get_index(), zv.get_index(),
					"" if cv.get_index() > zv.get_index() else "   <-- CARD IS BEHIND ITS CELL"])
			worst = mini(worst, cv.get_index() - zv.get_index())
	print("[grid_layer_shot] n=%d worst card-minus-cell index margin = %d (must be > 0)" % [n, worst])
	print("[grid_layer_shot] n=%d cards placed = %d, stacked = %s"
			% [n, placed.size(), str(stacked != null)])
	_print_centres(pa, n)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/grid_board_%d.png" % [OUT_DIR, n])
	print("[grid_layer_shot] wrote grid_board_%d.png" % n)
	if n == 1:
		img.save_png("%s/grid_occupied.png" % OUT_DIR)
		print("[grid_layer_shot] wrote grid_occupied.png")

	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()

## Every grid centre against the window centre, plus how far each hangs off screen -- the numbers
## that turn "looks centred" into evidence.
func _print_centres(pa: PlayArea, n: int) -> void:
	var bar := pa.scroll_container.get_v_scroll_bar()
	var taken : float = bar.size.x if bar and bar.visible else 0.0
	var left := pa.scroll_container.global_position.x
	var right := left + pa.scroll_container.size.x - taken
	var window_centre := (left + right) * 0.5
	print("[grid_layer_shot] n=%d window x [%.1f .. %.1f] centre %.1f" % [n, left, right, window_centre])
	for gi : int in pa.grid_container.get_child_count():
		var panel := pa.grid_container.get_child(gi) as Control
		var cells := pa._cells_root(panel)
		var panel_centre := panel.global_position.x + panel.size.x * 0.5
		var off := maxf(maxf(left - cells.global_position.x, 0.0),
				maxf(cells.global_position.x + cells.size.x - right, 0.0))
		print("[grid_layer_shot] n=%d grid %d panel centre %.1f (%+.1f from window centre), cells x [%.1f .. %.1f], off-screen %.1f px%s"
				% [n, gi, panel_centre, panel_centre - window_centre,
				cells.global_position.x, cells.global_position.x + cells.size.x, off,
				"" if off <= 0.5 else "   <-- CUT OFF"])

## Waits until the board stops moving, so a shot is never taken mid-settle.
func _settle_layout(view: GameView) -> void:
	var pa := view.play_area
	var last := INF
	var waited := 0.0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var now := pa.slot_center_global(BoardCoord.new(0, 0, 0, 0)).y
		if is_equal_approx(now, last): return
		last = now
