extends Control

## Photographs a board with cards ON GRID CELLS.
##
## ⚠ THE ONLY INSTRUMENT THAT SHOWS THIS. `reveal_shot` renders an empty grid, so a card drawing
## BEHIND the cell it sits on was invisible to every existing shot -- which is how it reached the
## owner by eye instead of a test. Draw order in a CanvasItem layer is child index, and an index
## is only meaningful within one layer, so this also prints the two indices next to the picture.

const OUT_DIR := "user://reveal_shots"
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
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
	await get_tree().process_frame
	await get_tree().process_frame

	# The measurement that goes with the picture: a card must sit ABOVE its cell's zone card.
	var worst := 1 << 30
	for x : int in placed.size():
		var cell_type : CardData = grid.cell_types[x]
		var cv : CardVisual = pa.data_card.get(placed[x])
		var zv : CardVisual = pa.data_card.get(cell_type)
		if cv and zv and is_instance_valid(cv) and is_instance_valid(zv):
			print("[grid_layer_shot] cell %d: card idx %d vs cell idx %d%s"
					% [x, cv.get_index(), zv.get_index(),
					"" if cv.get_index() > zv.get_index() else "   <-- CARD IS BEHIND ITS CELL"])
			worst = mini(worst, cv.get_index() - zv.get_index())
	print("[grid_layer_shot] worst card-minus-cell index margin = %d (must be > 0)" % worst)
	print("[grid_layer_shot] cards placed = %d, stacked = %s" % [placed.size(), str(stacked != null)])

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/grid_occupied.png" % OUT_DIR)
	print("[grid_layer_shot] wrote grid_occupied.png")
	get_tree().quit()
