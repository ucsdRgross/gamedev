extends Control

## THROWAWAY MEASUREMENT PROBE (not part of the suite). Reproduces test_interaction.gd's
## `test_mouse_click_selects_card` fixture exactly (same window, same setup, same click path) and
## prints the numbers behind a pass/fail instead of just asserting one.
##
## Run windowed:
##     <console exe> --path solatro res://Tests/Visual/interaction_click_probe.tscn

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const SAVE_TAG := "interaction_click_probe"

var view : GameView
var game : Game
var pa : PlayArea
var selections : Array[CardData] = []

func _ready() -> void:
	TestSuite.backup_real_save(SAVE_TAG)
	var src_cards := TestDecks.seeded_deck()
	var src_rules := TestDecks.standard_rules()
	var run := RunManager.new_run(src_cards, src_rules)
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	view = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	for _i in 2: await get_tree().process_frame
	game = view.game
	pa = view.play_area
	pa.data_selected.connect(func(d: CardData) -> void: selections.append(d))
	await game.next()
	await game.next()
	var env_count := OS.get_environment("GRID_COUNT")
	if env_count.is_valid_int():
		var want := maxi(env_count.to_int(), 1)
		while game.state.grids.size() < want: Board.add_grid(game.state, GridData.new())
		while game.state.grids.size() > want: Board.remove_grid(game.state, game.state.grids.size() - 1)
	pa.flush_rebuild()
	pa.focus_grid(0)
	for _i in 2: await get_tree().process_frame

	print("[probe] window size %s" % [get_viewport().get_visible_rect().size])
	print("[probe] GameView rect %s" % [view.get_global_rect()])
	print("[probe] PlayContainer rect %s"
			% [(view.get_node("%SceneRoot/PlayContainer") as Control).get_global_rect() if view.has_node("%SceneRoot/PlayContainer") else "n/a"])
	print("[probe] PlayArea rect %s" % [pa.get_global_rect()])
	print("[probe] scroll_container rect %s, clip_contents %s, scale %s"
			% [pa.scroll_container.get_global_rect(), pa.scroll_container.clip_contents,
			pa.scroll_container.scale])
	print("[probe] pan_grid %d, board_zoom %.4f, view_mode %s"
			% [pa.pan_grid, pa.board_zoom, str(pa.view_mode)])

	var control := a_card_control()
	if not control:
		print("[probe] NO focusable card control found")
		get_tree().quit(1)
		return
	print("[probe] grids: %d" % game.state.grids.size())
	print("[probe] rect jitter check, entrance track pos, 15 frames, NO input:")
	for i in 15:
		await get_tree().process_frame
		print("[probe]  frame %d: h_track.position.x %.6f control global %s"
				% [i, pa.entrance_h_track.position.x, control.get_global_rect()])
	print("[probe] card control %s rect %s visible_in_tree %s mouse_filter %d path %s"
			% [control.name, control.get_global_rect(), control.is_visible_in_tree(),
			control.mouse_filter, control.get_path()])
	print("[probe] entrance_strip rect %s visible %s"
			% [pa.entrance_strip.get_global_rect(), pa.entrance_strip.visible])
	var center := control.get_global_rect().get_center()
	print("[probe] click target (canvas) %s" % [center])
	var wpos := to_window(center)
	print("[probe] click target (window) %s" % [wpos])

	selections.clear()
	var wpos2 := to_window(center)
	var mm := InputEventMouseMotion.new()
	mm.position = wpos2
	mm.global_position = wpos2
	await send(mm)
	print("[probe] after motion: focused_control %s moused_hovered_control %s"
			% [pa.focused_control, pa.moused_hovered_control])
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = wpos2
	down.global_position = wpos2
	await send(down)
	print("[probe] after button-down: focused_control %s moused_hovered_control %s selections %d"
			% [pa.focused_control, pa.moused_hovered_control, selections.size()])
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = wpos2
	up.global_position = wpos2
	await send(up)
	print("[probe] selections after click: %d" % selections.size())
	print("[probe] focus_owner after click: %s" % [get_viewport().gui_get_focus_owner()])
	if selections.size() >= 1:
		print("[probe] RESULT: click landed and emitted selection")
	else:
		print("[probe] RESULT: click did NOT emit a selection")

	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

func a_card_control() -> Control:
	pa.flush_rebuild()
	for control : Control in pa.ui_data:
		if control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			return control
	return null

func to_window(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos

func send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame

func mouse_click(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var wpos := to_window(pos)
	var mm := InputEventMouseMotion.new()
	mm.position = wpos
	mm.global_position = wpos
	await send(mm)
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.position = wpos
	down.global_position = wpos
	await send(down)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = wpos
	up.global_position = wpos
	await send(up)
