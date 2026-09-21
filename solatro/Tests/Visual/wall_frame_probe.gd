extends Node2D

#Measures and photographs every picture FRAME against the ROOT WINDOW on the REAL booted `Main`, in
#each state where a frame could reach the window while a picture is focused.
#`OUT_DIR` names the directory; run windowed, bounded by an external killing timeout.

const MAIN_SCENE := preload("res://Levels/main.tscn")
const FALLBACK_OUT_DIR := "user://wall_frame_probe"
const SAVE_TAG := "wall_frame_probe"

## How long a rest shot waits for everything it photographs to stop moving before it gives up.
const STILL_TIMEOUT_SEC := 12.0

## How long the probe must read the same to count as at rest -- longer than the board's own pan clock, which a re-centre waits out before it aims.
const STILL_MARGIN_SEC := 0.5

## How many grids the board is stood up with, so the overview pan has two end stops to reach.
const GRID_COUNT := 3

var _out_dir : String = FALLBACK_OUT_DIR
var _main : Main = null
var _moved : bool = false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wall_frame_probe needs a REAL renderer. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	var env := OS.get_environment("OUT_DIR")
	if not env.is_empty(): _out_dir = env
	if _out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(_out_dir)
	TestSuite.backup_real_save(SAVE_TAG)
	DisplayServer.window_set_size(Vector2i(1152, 648))
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	await _await_still()
	await _shoot("menu_at_rest")

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1_000_000_000
	run.pending_node_id = 2
	_main.map_scene.start_run(run)
	await _main._focus_picture(&"map")
	await _await_still()
	await _shoot("map_at_rest")

	await _shoot_the_slide_into_the_game()
	await _grow_the_board()
	await _report_the_pan_reach()
	await _shoot_the_overview_pan()
	await _shoot_the_aspects()
	await _shoot_the_leave()
	await _await_still()
	await _shoot("wall_view")
	await _shoot_the_enter_from_wall_view()
	await _shoot_the_picture_to_picture_move()

	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit(1 if _moved else 0)

#The slide itself, the state a white rectangle around the board window was reported in: three
#frames on the way in, each with the frame band measured against the window.
func _shoot_the_slide_into_the_game() -> void:
	_main.enter_game()
	while _main._move_in_flight:
		await get_tree().process_frame
	await _shoot_moving("game_landed_pre_slide")
	for i : int in 3:
		await RenderingServer.frame_post_draw
		await _shoot_moving("slide_in_%d" % i)
	while _main.hud_container.slid_fraction() < 1.0:
		await get_tree().process_frame
	await _await_still()
	await _shoot("game_at_rest")

#The board the product deals has one grid, and the end stops this probe exists for need three.
func _grow_the_board() -> void:
	var pa := _play_area()
	var g := pa.get_parent() as Node
	var view : GameView = _main._pictures[&"game"].screen_root as GameView
	while view.game.state.grids.size() < GRID_COUNT:
		Board.add_grid(view.game.state, GridData.new())
	pa.flush_rebuild()
	pa.open_show_view()
	print("PROBE grew the board to ", view.game.state.grids.size(), " grids under ", g.name)
	await _await_still()

#What a pan that must keep the window INSIDE the picture has left to move, per grid count and per
#window aspect: the picture's width against what the resting zoom already shows, beside the grid
#step the board asks for.
func _report_the_pan_reach() -> void:
	var view : GameView = _main._pictures[&"game"].screen_root as GameView
	var pa := _play_area()
	var wp : WallPicture = _main._pictures[&"game"]
	for count : int in [1, 2, 3]:
		while view.game.state.grids.size() < count:
			Board.add_grid(view.game.state, GridData.new())
		while view.game.state.grids.size() > count:
			Board.remove_grid(view.game.state, view.game.state.grids.size() - 1)
		pa.flush_rebuild()
		pa.open_show_view()
		pa.open_zoomed_out()
		await _await_still()
		for size : Vector2i in [Vector2i(1152, 648), Vector2i(864, 648), Vector2i(1512, 648),
				Vector2i(648, 900)]:
			DisplayServer.window_set_size(size)
			await get_tree().process_frame
			await _await_still()
			var window := get_viewport().get_visible_rect().size
			var zoom := WallPicture.focused_scale(wp.rect.size, window,
					SettingsManager.settings.wall_overfill_margin)
			var shown := window.x / zoom
			var slack := WallPicture.max_pan_px(wp.rect, window, SettingsManager.settings)
			var pitch := pa.grid_pitch_px()
			print("PROBE reach grids=%d window=%dx%d viewport=%s zoom=%.4f picture_w=%.1f shown_w=%.1f slack=%.1f pitch=%.1f steps_in_slack=%.2f"
					% [count, size.x, size.y, window, zoom, wp.rect.size.x, shown, slack, pitch,
					slack / maxf(pitch, 0.0001)])
	DisplayServer.window_set_size(Vector2i(1152, 648))
	await get_tree().process_frame
	while view.game.state.grids.size() < GRID_COUNT:
		Board.add_grid(view.game.state, GridData.new())
	pa.flush_rebuild()
	pa.open_show_view()
	await _await_still()

#The overview pan to the last end stop and the bounce past it: the camera steps inside a picture
#several screens wide, so this is where a frame can reach the middle of the window.
func _shoot_the_overview_pan() -> void:
	var pa := _play_area()
	pa.open_zoomed_out()
	await _await_still()
	await _shoot("overview_first_grid")
	for _step : int in GRID_COUNT - 1:
		pa.pan_by_grids(1)
		await _await_still()
	await _shoot("overview_last_grid")
	print("PROBE bouncing past the last grid, pan_grid=", pa.pan_grid)
	pa.pan_by_grids(1)
	var camera : Camera2D = _main.wall.get_node(^"%Camera2D")
	var peak_x := camera.position.x
	var peak_i := 0
	for i : int in 40:
		await RenderingServer.frame_post_draw
		await _shoot_moving("bounce_%02d" % i)
		if absf(camera.position.x) > absf(peak_x):
			peak_x = camera.position.x
			peak_i = i
	print("PROBE bounce peak camera x=", peak_x, " at frame ", peak_i)
	await _await_still()
	await _shoot("overview_after_bounce")

#Window aspects other than the authored 16:9: a focused picture overfills, so the question is
#whether any frame edge sits inside the window at rest at any of them.
func _shoot_the_aspects() -> void:
	var pa := _play_area()
	pa.pan_to_grid(pa.resting_grid())
	await _await_still()
	for size : Vector2i in [Vector2i(864, 648), Vector2i(1512, 648), Vector2i(648, 900),
			Vector2i(1152, 648)]:
		DisplayServer.window_set_size(size)
		await get_tree().process_frame
		await _await_still()
		await _shoot("aspect_rest_%dx%d" % [size.x, size.y])
	for _step : int in GRID_COUNT - 1:
		pa.pan_by_grids(1)
		await _await_still()
	await _shoot("aspect_last_grid_1152x648")

#The leave to wall view, sampled while the camera is moving: the frames come back into view here
#whatever anything does, so it is the reference the hide is judged against.
func _shoot_the_leave() -> void:
	_main._go_to_wall_view()
	for i : int in 6:
		await RenderingServer.frame_post_draw
		await _shoot_moving("leave_%d" % i)
	while _main._move_in_flight:
		await get_tree().process_frame

#The zoom-in from wall view, sampled every frame across the landing: the frames are the wall being
#dived into, and the landing is where they go.
func _shoot_the_enter_from_wall_view() -> void:
	_main._focus_picture(&"map")
	var i := 0
	while _main._move_in_flight:
		await RenderingServer.frame_post_draw
		await _shoot_moving("enter_%02d" % i)
		i += 1
	await _shoot_moving("enter_landed")

#A real picture-to-picture move, the one case where the camera travels across bare wall between two
#focused states.
func _shoot_the_picture_to_picture_move() -> void:
	await _main._focus_picture(&"map")
	await _await_still()
	_main._focus_picture(&"game")
	for i : int in 8:
		await RenderingServer.frame_post_draw
		await _shoot_moving("travel_%d" % i)
	while _main._move_in_flight:
		await get_tree().process_frame
	await _await_still()
	await _shoot("travel_landed")

## The live board behind the game picture.
func _play_area() -> PlayArea:
	var wp : WallPicture = _main._pictures[&"game"]
	var view := wp.screen_root as GameView
	return view.play_area

#Every frame BAND against the ROOT WINDOW, so "is a frame on screen" is a measurement rather than a
#look. The band is the frame's outer rect MINUS the picture rect it surrounds: the outer rect
#contains the picture, so its overlap with the window says nothing.
func _report(label: String) -> void:
	var window := get_viewport().get_visible_rect()
	var camera : Camera2D = _main.wall.get_node(^"%Camera2D")
	print("PROBE ", label, " window=", window.size, " camera=", camera.position, " zoom=",
			camera.zoom.x, " focus=", _main._current_focus)
	for id : StringName in _main._pictures:
		var wp : WallPicture = _main._pictures[id]
		var frame : NinePatchRect = wp.get_node(^"%Frame")
		var outer : Rect2 = frame.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, frame.size)
		var zoom := camera.zoom.x
		var inner := Rect2((wp.rect.centre - camera.position) * zoom + window.size / 2.0
				- wp.rect.size * zoom / 2.0, wp.rect.size * zoom)
		var band := window.intersection(outer).size.x > 0.0 \
				and window.intersection(outer).size.y > 0.0 \
				and not _contains(inner, window)
		print("PROBE   %s frame visible=%s outer=%s picture=%s gap l/t/r/b=%.1f/%.1f/%.1f/%.1f%s"
				% [id, frame.visible, outer, inner, inner.position.x - window.position.x,
				inner.position.y - window.position.y, window.end.x - inner.end.x,
				window.end.y - inner.end.y,
				"   <-- FRAME BAND IN WINDOW" if band and frame.visible else ""])

## Whether `outer` covers every point of `inner`, to the half-pixel a rasteriser can actually show.
func _contains(outer: Rect2, inner: Rect2) -> bool:
	return outer.position.x <= inner.position.x + 0.5 and outer.position.y <= inner.position.y + 0.5 \
			and outer.end.x >= inner.end.x - 0.5 and outer.end.y >= inner.end.y - 0.5

#A shot of a state that is supposed to be at rest, guarded: a still that moved across its own grab
#is not evidence about the state it is captioned with.
func _shoot(label: String) -> void:
	_report(label)
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join("%s.png" % label))

#A DELIBERATELY MOVING FRAME, so it carries no stillness guard: what the camera is doing between two
#resting poses is the thing being photographed.
func _shoot_moving(label: String) -> void:
	_report(label)
	get_viewport().get_texture().get_image().save_png(_out_dir.path_join("%s.png" % label))

#⚠ A REST FRAME MUST BE A REST FRAME, AND MEASURED IN TIME, NOT FRAMES: these boxes differ by an
#order of magnitude in frame rate, and the board's re-centre waits out its own pan clock before it
#aims, so a board sitting still inside that settle is not a board at rest.
func _await_still() -> void:
	var last := _pose_signature()
	var held := 0.0
	var waited := 0.0
	while waited < STILL_TIMEOUT_SEC and held < STILL_MARGIN_SEC:
		await get_tree().process_frame
		var step := get_process_delta_time()
		waited += step
		var now := _pose_signature()
		held = held + step if is_equal_approx(now, last) and not _board_is_working() else 0.0
		last = now
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_equal_approx(_pose_signature(), last):
		_moved = true
		push_error("the probe moved across the grab -- this rest shot is not a rest")

#ONE number standing for the whole geometry a frame shot depends on: the wall camera's pose, the
#container's drawn x and the board's zoom and scroll, weighted so two of them cannot cancel out.
func _pose_signature() -> float:
	var camera : Camera2D = _main.wall.get_node(^"%Camera2D")
	var total := _main.hud_container.position.x + camera.position.x * 3.0 \
			+ camera.position.y * 7.0 + camera.zoom.x * 1013.0
	var view := _main._pictures[&"game"].screen_root as GameView
	if view:
		total += view.play_area.board_zoom * 101.0
		total += view.play_area.scroll_container.global_position.x * 17.0
	return total

## Whether the show is still resolving, which a still geometry alone cannot rule out mid-deal.
func _board_is_working() -> bool:
	var view := _main._pictures[&"game"].screen_root as GameView
	return view != null and view.game != null and view.game.processing
