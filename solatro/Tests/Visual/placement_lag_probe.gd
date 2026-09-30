extends Node2D

# Times every frame of a real show while Entrance cards are dragged onto legal cells, windowed.
# Env: OUT_DIR (frames.jsonl), GRIDS (1 or 3), PLACEMENTS, PAD_HISTORY (undo snapshots to pre-fill).
# The per-frame bracket sums come from `placement_lag_marks.gd`, added to product code temporarily.

const MAIN_SCENE := preload("res://Levels/main.tscn")
const MARKS := preload("res://Tests/Visual/placement_lag_marks.gd")
const SAVE_TAG := "placement_lag_probe"
const GOAL_OUT_OF_REACH : int = 100000000
const DRAG_STEPS : int = 12
const IDLE_FRAMES : int = 60
const PRE_FRAMES : int = 10
const AFTER_TIMEOUT_SEC := 6.0
const AFTER_TAIL_FRAMES : int = 60

var _out : FileAccess = null
var _main : Main = null
var _game : Game = null
var _pa : PlayArea = null
var _picture : SubViewport = null
var _viewports : Array[Viewport] = []
var _recording := false
var _phase := "boot"
var _placement : int = -1
var _last_usec : int = 0
var _drop_push_usec : int = 0
var _t_first : int = 0
var _t_process_signal : int = 0
var _t_physics_signal : int = 0
var _t_pre_draw : int = 0
var _t_post_draw : int = 0

# The first node to process each frame, so the harness (last) can split the frame into its stages.
class FirstProcess extends Node:
	var stamp : Callable
	func _process(_delta: float) -> void:
		stamp.call()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	var out_dir := OS.get_environment("OUT_DIR")
	var grids := int(OS.get_environment("GRIDS")) if OS.has_environment("GRIDS") else 1
	var placements := int(OS.get_environment("PLACEMENTS")) if OS.has_environment("PLACEMENTS") else 20
	var pad := int(OS.get_environment("PAD_HISTORY")) if OS.has_environment("PAD_HISTORY") else 0
	DirAccess.make_dir_recursive_absolute(out_dir)
	_out = FileAccess.open(out_dir.path_join("frames.jsonl"), FileAccess.WRITE)
	TestSuite.backup_real_save(SAVE_TAG)
	if grids > 1: SettingsManager.settings.grid_cards_per_unlock = ceili(52.0 / grids)
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = GOAL_OUT_OF_REACH
	run.pending_node_id = 2
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	for i : int in 30: await get_tree().process_frame
	await _main.enter_game()
	var view := _main._pictures[&"game"].screen_root as GameView
	_game = view.game
	CardEnvironment.CURRENT = _game
	_pa = view.play_area
	_picture = _main._pictures[&"game"].viewport
	await _await_the_deal()
	_pa.focus_grid(0)
	await _wait_seconds(1.5)
	print("LAGINFO grids=%d window=%s picture=%s undo_cap=%d" % [_game.state.grids.size(),
			DisplayServer.window_get_size(), _picture.size, _game.undo_cap])
	if pad > 0: _pad_history(pad)
	_collect_viewports(get_tree().root)
	for vp : Viewport in _viewports:
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var first := FirstProcess.new()
	first.process_mode = Node.PROCESS_MODE_ALWAYS
	first.process_priority = -1000000
	first.stamp = func() -> void: _t_first = Time.get_ticks_usec()
	add_child(first)
	get_tree().process_frame.connect(func() -> void: _t_process_signal = Time.get_ticks_usec())
	get_tree().physics_frame.connect(func() -> void: _t_physics_signal = Time.get_ticks_usec())
	RenderingServer.frame_pre_draw.connect(func() -> void: _t_pre_draw = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: _t_post_draw = Time.get_ticks_usec())
	_last_usec = Time.get_ticks_usec()
	_recording = true
	_set_phase("idle")
	for i : int in IDLE_FRAMES: await get_tree().process_frame
	for p : int in placements:
		_placement = p
		if not await _place_one(): break
	_recording = false
	_out.close()
	print("LAGINFO done placements=%d history=%d debug_history=%d objects=%d" % [_placement + 1,
			_game.save_history.size(), _game.debug_snapshots().size(),
			Performance.get_monitor(Performance.OBJECT_COUNT)])
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit(0)

func _process(_delta: float) -> void:
	if not _recording: return
	var now := Time.get_ticks_usec()
	var frame := int(Engine.get_process_frames())
	var gpu : Dictionary[String, float] = {}
	var cpu_render := RenderingServer.get_frame_setup_time_cpu()
	for vp : Viewport in _viewports:
		if not is_instance_valid(vp): continue
		cpu_render += RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid())
		var ms := RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
		if ms > 0.0: gpu[str(vp.get_path()).get_file() + "#" + str(vp.get_instance_id() % 1000)] = ms
	var row := {
		"f": frame, "phase": _phase, "p": _placement, "since_last_us": now - _last_usec,
		"t_process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"t_physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"cpu_render_ms": cpu_render,
		"gpu": gpu, "marks": MARKS.take(frame - 1), "marks_now": MARKS.take(frame),
		"t_now": now, "t_first": _t_first, "t_procsig": _t_process_signal,
		"t_physsig": _t_physics_signal, "t_pre_prev": _t_pre_draw, "t_post_prev": _t_post_draw,
		"drop_push_us": _drop_push_usec, "threads": MARKS.take_thread_events(),
		"history": _game.save_history.size(), "processing": _game.processing,
	}
	_drop_push_usec = 0
	_out.store_line(JSON.stringify(row))
	_last_usec = now

func _set_phase(phase: String) -> void:
	_phase = phase
	print("LAGMARK p=%d phase=%s frame=%d" % [_placement, phase, Engine.get_process_frames()])

func _collect_viewports(node: Node) -> void:
	if node is Viewport: _viewports.append(node as Viewport)
	for child : Node in node.get_children(): _collect_viewports(child)

# A play mod may raise the cap toward MAX_UNDO_HISTORY; this is that board, reached without playing
# every action: copies of the live board fill the history the way commits would.
func _pad_history(count: int) -> void:
	_game.undo_cap = Game.MAX_UNDO_HISTORY
	while _game.save_history.size() < count:
		_game.save_history.append(_game.state.to_saveable())
	RunManager.run.game_history = _game.save_history
	print("LAGINFO padded history to %d" % _game.save_history.size())

func _await_the_deal() -> void:
	var waited := 0.0
	while waited < 10.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not _entrance_controls().is_empty() and not _game.processing: return

func _wait_seconds(sec: float) -> void:
	var waited := 0.0
	while waited < sec:
		await get_tree().process_frame
		waited += get_process_delta_time()

func _entrance_controls() -> Array[Control]:
	_pa.flush_rebuild()
	var out : Array[Control] = []
	for control : Control in _pa.ui_data:
		if control.focus_mode == Control.FOCUS_NONE: continue
		if _pa.is_stock_control(control): continue
		if _pa.upper_zone_right.is_ancestor_of(control): out.append(control)
	out.sort_custom(func(a: Control, b: Control) -> bool:
			return a.get_global_rect().position.x < b.get_global_rect().position.x)
	return out

func _legal_target(held: CardData) -> Control:
	var grids : Array[GridData] = _game.state.grids
	if _game.state.committed_grid != -1: grids = [_game.state.grids[_game.state.committed_grid]]
	var legal := await _game.legal_cells_for([held] as Array[CardData], grids)
	var on_screen := Rect2(Vector2.ZERO, Vector2(_picture.size))
	for control : Control in _pa.ui_data:
		var drawn := control.get_global_rect()
		if not drawn.has_area() or not on_screen.encloses(drawn): continue
		if _pa.ui_data[control] in legal: return control
	return null

func _place_one() -> bool:
	_set_phase("choose")
	var entrance := _entrance_controls()
	var source : Control = null
	var target : Control = null
	for control : Control in entrance:
		if _game.state.committed_grid != -1 and _pa.view_mode != PlayArea.ViewMode.FOCUSED:
			_pa.focus_grid(_game.state.committed_grid)
		target = await _legal_target(_pa.ui_data[control])
		if target:
			source = control
			break
	if not target:
		print("LAGINFO no legal placement left at p=%d" % _placement)
		return false
	var from := source.get_global_rect().get_center()
	var to := target.get_global_rect().get_center()
	var placed_before := _game.history_trimmed + _game.save_history.size()
	_set_phase("pre")
	for i : int in PRE_FRAMES: await get_tree().process_frame
	_set_phase("press")
	_push(_motion(from))
	await get_tree().process_frame
	_push(_button(from, true))
	await get_tree().process_frame
	_set_phase("drag")
	for step : int in DRAG_STEPS:
		_push(_motion(from.lerp(to, float(step + 1) / DRAG_STEPS)))
		await get_tree().process_frame
	_set_phase("drop")
	var t0 := Time.get_ticks_usec()
	_push(_button(to, false))
	_drop_push_usec = Time.get_ticks_usec() - t0
	await get_tree().process_frame
	_set_phase("after")
	var waited := 0.0
	while waited < AFTER_TIMEOUT_SEC and (_game.processing or not _pa.selected_cards.is_empty()
			or _game.history_trimmed + _game.save_history.size() == placed_before):
		await get_tree().process_frame
		waited += get_process_delta_time()
	_set_phase("tail")
	for i : int in AFTER_TAIL_FRAMES: await get_tree().process_frame
	var placed := _game.history_trimmed + _game.save_history.size() > placed_before
	print("LAGINFO p=%d placed=%s after_wait=%.2fs history=%d" % [_placement, placed, waited,
			_game.save_history.size()])
	return true

func _push(event: InputEvent) -> void:
	_picture.push_input(event)

func _motion(at: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	return event

func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event
