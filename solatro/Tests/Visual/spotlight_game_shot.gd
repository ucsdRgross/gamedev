extends "res://Tests/Visual/tool_shot.gd"

# The game's own spotlight on its focused, zoomed board: the real Main in a real show, cards placed
# by real clicks until a line scores, shot on the frame its scoring lights are fully up.

const MAIN_SCENE := preload("res://Levels/main.tscn")
const SAVE_TAG := "spotlight_game_shot"
const WINDOW_SIZE := Vector2i(1280, 720)
## Out of any placement's reach, so the show is still running when a line scores.
const GOAL := 1_000_000_000
## Seconds the deal and the opening view are given to come to rest.
const DEAL_SECS := 4.0
## Placements tried before the run reports that no scoring light came up.
const PLACEMENTS := 30
## Seconds one placement's cascade is watched for its lights.
const WATCH_SECS := 8.0

func stage() -> void:
	TestSuite.backup_real_save(SAVE_TAG)
	DisplayServer.window_set_size(WINDOW_SIZE)
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = GOAL
	run.pending_node_id = 2
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	await settle()
	await main.enter_game()
	var view := main._pictures[&"game"].screen_root as GameView
	CardEnvironment.CURRENT = view.game
	await get_tree().create_timer(DEAL_SECS).timeout
	var shot := false
	for placement : int in PLACEMENTS:
		if not await _place_a_card(main, view): continue
		if not await _the_scoring_lights_came_up(view): continue
		await RenderingServer.frame_post_draw
		save("spotlight_game_zoomed.png")
		_report(view, placement + 1)
		shot = true
		break
	print("SPOTLIGHT_GAME_SHOT captured=%s" % shot)
	while view.game.processing:
		await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)

# A real click lifts the first Entrance card that answers one, a second click sets it on an empty
# legal cell, so a row fills and scores as a player fills it; false when nothing could be placed.
func _place_a_card(main: Main, view: GameView) -> bool:
	var pa := view.play_area
	var viewport : SubViewport = main._pictures[&"game"].viewport
	for data : CardData in pa.data_card.keys():
		var coord := view.game.state.grid_position_of(data)
		if coord == null or not coord.is_entrance() or coord.h != 0: continue
		await _click(viewport, pa.data_ui[data])
		if not pa.selected_cards.is_empty(): break
	if pa.selected_cards.is_empty(): return false
	var legal := await view.game.legal_cells_for(pa.selected_cards.duplicate(), view.game.state.grids)
	var empty := legal.filter(func(cell: CardData) -> bool:
			return cell in view.game.state.grids[0].cell_types)
	if empty.is_empty(): return false
	await _click(viewport, pa.data_ui[empty[0]])
	return pa.selected_cards.is_empty()

func _click(viewport: SubViewport, control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion)
	await get_tree().process_frame
	for pressed : bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		viewport.push_input(click)
		await get_tree().process_frame
	await get_tree().process_frame

## Watches the placement's cascade frame by frame; true on the frame a scoring section's lights are fully up.
func _the_scoring_lights_came_up(view: GameView) -> bool:
	var layer := view.light_layer
	var waited := 0.0
	while waited < WATCH_SECS and (view.game.processing or waited == 0.0):
		await get_tree().process_frame
		waited += get_process_delta_time()
		if _the_show_is_up(layer): return true
	return false

func _the_show_is_up(layer: LightLayer) -> bool:
	return not layer._lights.is_empty() and layer._scoring and layer._show >= 1.0 \
			and is_equal_approx(layer._dim, layer._dim_target()) \
			and layer._lights.all(func(light: LightLayer.Light) -> bool: return light.intensity >= 1.0)

# The still is of a pool as wide as its card's art on a board drawn at a zoom, so each light is
# printed against the lit card nearest it: the two widths, and how far the pool sits off its centre.
func _report(view: GameView, placements: int) -> void:
	var pa := view.play_area
	var layer := view.light_layer
	print(("SPOTLIGHT_GAME_SHOT placements=%d processing=%s scoring=%s up=%s show=%.2f dim=%.3f "
			+ "dim_target=%.3f lights=%d forced=%d")
			% [placements, view.game.processing, layer._scoring, _the_show_is_up(layer), layer._show,
					layer._dim, layer._dim_target(), layer._lights.size(),
					view.game.state.forced_spotlight.size()])
	print("SPOTLIGHT_GAME_SHOT board_zoom=%.4f drawn_zoom=%.4f card_scale=%.4f"
			% [pa.board_zoom, pa.drawn_zoom, SettingsManager.settings.card_scale])
	for index : int in layer._lights.size():
		var light := layer._lights[index]
		var card : CardVisual = null
		for data : CardData in view.game.state.forced_spotlight:
			var lit : CardVisual = pa.data_card[data]
			if card == null or light.centre.distance_to(lit.spotlight_center()) \
					< light.centre.distance_to(card.spotlight_center()):
				card = lit
		print("SPOTLIGHT_GAME_SHOT light%d pool_px=%.1f card_art_px=%.1f off_centre_px=%.2f drawn_scale=%.4f"
				% [index, light.radius * 2.0, CardVisual.CARD_ART_SIZE.x * card.spotlight_scale(),
						light.centre.distance_to(card.spotlight_center()), card.spotlight_scale()])
