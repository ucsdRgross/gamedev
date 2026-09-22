extends Node2D

# Photographs and MEASURES what a board card's HOVER, CLICK and pad FOCUS do to the sidebar, on the
# REAL booted `Main`, into the ROOT WINDOW. `OUT_DIR` names the directory; run windowed, bounded by
# an external killing timeout.

const MAIN_SCENE := preload("res://Levels/main.tscn")
const FALLBACK_OUT_DIR := "user://board_hover_probe"
const SAVE_TAG := "board_hover_probe"

## How long the deal is given to come to rest before a shot is taken anyway.
const SETTLE_TIMEOUT_SEC := 15.0
## How long the probe must read the same to count as at rest.
const STILL_MARGIN_SEC := 0.4

var _out_dir : String = FALLBACK_OUT_DIR
var _main : Main = null
var _play_area : PlayArea = null
var _viewport : SubViewport = null

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("board_hover_probe needs a REAL renderer. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	var env := OS.get_environment("OUT_DIR")
	if not env.is_empty(): _out_dir = env
	if _out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(_out_dir)
	TestSuite.backup_real_save(SAVE_TAG)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	await _await_still()

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	_main.map_scene.start_run(run)
	await _main._focus_picture(&"map")
	await _await_still()
	await _main.enter_game()
	var view := _main._pictures[&"game"].screen_root as GameView
	CardEnvironment.CURRENT = view.game
	_play_area = view.play_area
	_viewport = _main._pictures[&"game"].viewport
	await _await_still()

	var cards := _entrance_controls()
	if cards.size() < 2:
		push_error("the dealt board offered fewer than two Entrance cards: %d" % cards.size())
		get_tree().quit(1)
		return

	_report("at rest, nothing touched")
	await _hover(cards[0])
	_report("HOVER card A")
	await _shoot("p34_hover_no_x")

	await _hover_bare(cards)
	_report("pointer left every card")

	_viewport.gui_release_focus()
	await _settle()
	cards[0].grab_focus()
	await _settle()
	_report("PAD FOCUS card A")
	_viewport.gui_release_focus()
	await _settle()
	_report("pad focus left the board")

	var cells := _grid_cell_controls()
	if cells.is_empty(): push_error("the board offered no grid cell control to hover")
	else:
		await _hover(cells[0])
		_report("HOVER a GRID cell")
		await _hover_bare(cards + cells)
		_report("pointer left the grid cell")

	await _hover(cards[0])
	await _click(cards[0])
	_play_area.ungrab_cards()
	await _settle()
	_report("CLICK card A")
	await _shoot("p34_click_sticky_x")

	await _hover_another_card(_play_area.locked_data)
	_report("HOVER card B while A is sticky")
	await _shoot("p34_hover_b_while_sticky")

	await _hover_sidebar()
	_report("pointer moved to the SIDEBAR")
	await _shoot("p34_sidebar_returns_a")

	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit(0)

## Everything this fix is about, in one line per step: what the sidebar shows, whether it is locked, and whether the X is up.
func _report(step: String) -> void:
	var c := _main.hud_container
	var panel : DescriptionPanel = c.get_node(^"%DescriptionPanel")
	var title : Label = panel.get_node(^"%Title")
	var x : Button = c.get_node(^"%ExitX")
	print("PROBE %-34s showing=%s locked=%s x_visible=%s x_focus=%d title=%s" % [step,
			c.showing_description(), c.is_locked(), x.is_visible_in_tree(), x.focus_mode,
			title.text if c.showing_description() else "-"])

func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join("%s.png" % label))

## The Entrance cards a pointer can genuinely land on, in the board's own order.
func _entrance_controls() -> Array[Control]:
	_play_area.flush_rebuild()
	var out : Array[Control] = []
	for control : Control in _play_area.ui_data:
		if not is_instance_valid(control) or control.focus_mode == Control.FOCUS_NONE: continue
		if _play_area.upper_zone_right.is_ancestor_of(control): out.append(control)
	return out

## The grid cells' own zone cards: the ruling covers hovering cards in the game grid, not only the Entrance row.
func _grid_cell_controls() -> Array[Control]:
	var listed : Dictionary[CardData, bool] = {}
	for grid : GridData in CardEnvironment.get_current_game().state.grids:
		for type_card : CardData in grid.cell_types: listed[type_card] = true
	var out : Array[Control] = []
	for control : Control in _play_area.ui_data:
		if not is_instance_valid(control) or control.focus_mode == Control.FOCUS_NONE: continue
		if listed.has(_play_area.ui_data[control]): out.append(control)
	return out

# WHICH CONTROL A POINT HITS IS THE ENGINE'S ANSWER, not the probe's: board cards overlap, so the
# pointer is walked across the candidates until the BOARD reports a different card under it.
func _hover_another_card(avoid: CardData) -> void:
	for control : Control in _entrance_controls():
		if _play_area.ui_data[control] == avoid: continue
		await _hover(control)
		var on := _play_area.moused_hovered_control
		if on and _play_area.ui_data.get(on) != avoid:
			print("PROBE   the pointer is on ", ControlCard.card_title(_play_area.ui_data[on]))
			return
	push_error("no second Entrance card took the pointer")

func _hover(control: Control) -> void:
	_push_motion(control.get_global_rect().get_center())
	await _settle()

## A point on the board belonging to no card control, so the pointer leaving everything is a real mouse exit.
func _hover_bare(controls: Array[Control]) -> void:
	var board := Vector2(_viewport.size)
	var at := Vector2(board.x - 4.0, 4.0)
	for step : int in 20:
		var candidate := Vector2(board.x - 4.0, 4.0 + step * board.y / 20.0)
		var covered := false
		for control : Control in controls:
			if control.get_global_rect().has_point(candidate): covered = true
		if not covered:
			at = candidate
			break
	_push_motion(at)
	await _settle()

# The sidebar is in the ROOT viewport and the board in the picture's own, so reaching it is one
# motion into each: the board must see the pointer leave, and the root must see it arrive.
func _hover_sidebar() -> void:
	_push_motion(Vector2(-100.0, -100.0))
	var at := _main.hud_container.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion)
	await _settle()

func _push_motion(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	_viewport.push_input(motion)

func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	for pressed : bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = at
		button.global_position = at
		_viewport.push_input(button)
		await get_tree().process_frame
	await _settle()

func _settle() -> void:
	for step : int in 4:
		await get_tree().process_frame

# A REST IS MEASURED IN TIME, NOT FRAMES: these boxes differ by an order of magnitude in frame
# rate, and the deal lands long after the camera is still.
func _await_still() -> void:
	var last := _probe()
	var held := 0.0
	var waited := 0.0
	while waited < SETTLE_TIMEOUT_SEC and held < STILL_MARGIN_SEC:
		await get_tree().process_frame
		var step := get_process_delta_time()
		waited += step
		var now := _probe()
		if now == last: held += step
		else: held = 0.0
		last = now

func _probe() -> PackedFloat32Array:
	var camera : Camera2D = _main.wall.get_node(^"%Camera2D")
	var out := PackedFloat32Array([_main.hud_container.position.x, camera.position.x,
			camera.zoom.x])
	if _play_area:
		out.append(_play_area.board_zoom)
		for card : CardVisual in _play_area.data_card.values():
			out.append(card.global_position.x)
			out.append(card.global_position.y)
	return out
