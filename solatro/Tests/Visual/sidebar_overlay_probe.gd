extends Node2D

# Photographs the sidebar overlaying the picture on the REAL booted `Main`, into the ROOT WINDOW:
# each screen at rest, and the frames of the slide itself, which no resting still can show.
# `OUT_DIR` names the directory; run windowed, bounded by an external killing timeout.

const MAIN_SCENE := preload("res://Levels/main.tscn")
const FALLBACK_OUT_DIR := "user://sidebar_overlay_probe"

## How long a rest shot waits for everything it photographs to stop moving before it gives up.
const STILL_TIMEOUT_SEC := 8.0

## How long the probe must read the same to count as at rest -- longer than the board's own pan clock, which a re-centre waits out before it aims.
const STILL_MARGIN_SEC := 0.5

var _out_dir : String = FALLBACK_OUT_DIR
var _main : Main = null
var _moved : bool = false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("sidebar_overlay_probe needs a REAL renderer. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	var env := OS.get_environment("OUT_DIR")
	if not env.is_empty(): _out_dir = env
	if _out_dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(1152, 648))
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	await _await_still()
	await _shoot("menu_at_rest", &"start_menu")
	await _shoot_the_pickers_description()

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	_main.map_scene.start_run(run)
	await _main._focus_picture(&"map")
	await _await_still()
	await _shoot("map_at_rest", &"map")

	await _shoot_the_slide_into_the_game()
	await _shoot_the_slide_out_of_the_game()
	await _await_still()
	await _shoot("wall_view", &"")
	get_tree().quit(1 if _moved else 0)

# ⚠ A REST FRAME MUST BE A REST FRAME, AND MEASURED IN TIME, NOT FRAMES: these boxes differ by an
# order of magnitude in frame rate, and the board's re-centre waits out its own pan clock before it
# aims, so a board sitting still inside that settle is not a board at rest.
func _await_still() -> void:
	var last := _probe()
	var held := 0.0
	var waited := 0.0
	while waited < STILL_TIMEOUT_SEC and held < STILL_MARGIN_SEC:
		await get_tree().process_frame
		var step := get_process_delta_time()
		waited += step
		var now := _probe()
		if _probe_same(now, last): held += step
		else: held = 0.0
		last = now
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not _probe_same(_probe(), last):
		_moved = true
		push_error("the probe moved across the grab -- this rest shot is not a rest")

# Everything a shot of this change depends on: the container's drawn x, the wall camera's pose, and
# -- because a deal is still landing long after the camera is still -- the board's zoom, its scroll
# offset and every card's pose.
func _probe() -> PackedFloat32Array:
	var camera : Camera2D = _main.wall.get_node(^"%Camera2D")
	var out := PackedFloat32Array([_main.hud_container.position.x, camera.position.x,
			camera.zoom.x])
	var pa := _live_play_area()
	if pa:
		out.append(pa.board_zoom)
		out.append(pa.scroll_container.global_position.x)
		out.append(pa.scroll_container.global_position.y)
		for card : CardVisual in _cards_under(pa):
			out.append(card.global_position.x)
			out.append(card.global_position.y)
			out.append(card.rotation)
	return out

## Float-tolerant, because the question is whether the SHOT moved, not whether a transform's last bit did.
func _probe_same(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size(): return false
	for i : int in a.size():
		if not is_equal_approx(a[i], b[i]): return false
	return true

## The board behind the game picture, or null while no show is attached.
func _live_play_area() -> PlayArea:
	var wp : WallPicture = _main._pictures.get(&"game")
	if not wp or not wp.screen_root: return null
	var view := wp.screen_root as GameView
	return view.play_area if view else null

## Every card visual on the board, so a card still in flight counts as the board still moving.
func _cards_under(root: Node) -> Array[CardVisual]:
	var found : Array[CardVisual] = []
	var card := root as CardVisual
	if card: found.append(card)
	for child : Node in root.get_children():
		found.append_array(_cards_under(child))
	return found

# The window rect a picture is DRAWN into, so a caption can say whether its edges reach the
# window's. ROOT WINDOW space, the same space the container's own rect is in.
func _drawn_rect(id: StringName) -> Rect2:
	var camera : Camera2D = _main.wall.get_node(^"%Camera2D")
	var rect : PictureRect = _main._rects[id]
	var window := get_viewport().get_visible_rect().size
	var zoom := camera.zoom.x
	var drawn := rect.size * zoom
	return Rect2((rect.centre - camera.position) * zoom + window / 2.0 - drawn / 2.0, drawn)

func _shoot(label: String, id: StringName) -> void:
	var container := _main.hud_container
	var pa := _live_play_area()
	print("PROBE ", label, " container x=", container.position.x, " slid=",
			container.slid_fraction(), " visible=", container.visible,
			" published=", container.published_rect().size,
			(" board_zoom=%.4f board x=%.1f" % [pa.board_zoom,
			pa.scroll_container.global_position.x]) if pa else "")
	if id != &"": print("PROBE   picture drawn=", _drawn_rect(id),
			" window=", get_viewport().get_visible_rect().size)
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir.path_join("p12_%s.png" % label))

# The menu's own sidebar: absent at rest, and there only while its picker is describing a card.
func _shoot_the_pickers_description() -> void:
	_main.menu_scene.new_run_button.pressed.emit()
	await get_tree().process_frame
	var picker : DeckPicker = _main.menu_scene.find_child("DeckPicker", true, false) as DeckPicker
	var inspect : Button = (picker.rows.get_child(0) as HBoxContainer).get_child(1) as Button
	inspect.pressed.emit()
	await _await_still()
	await _shoot("menu_with_the_pickers_description", &"start_menu")
	_main.hud_container.dismiss_description()
	picker.queue_free()
	await _await_still()

# THREE FRAMES OF A MOVING SIDEBAR, DELIBERATELY NOT STILL: a still of a slide that never started
# looks exactly like a still of one that did, so these carry no stillness guard and print the x.

# ⚠ THE DEAL IS SETTLED FIRST, then the picture is left and re-entered, so the only thing moving in
# these frames is the slide. Sampled straight after `enter_game()` they were mid-deal, cards still
# tilted in flight and the board still re-centring.
func _shoot_the_slide_into_the_game() -> void:
	_main.enter_game()
	while _main._move_in_flight or _main.hud_container.slid_fraction() < 1.0:
		await get_tree().process_frame
	await _await_still()
	await _main._go_to_wall_view()
	await _await_still()
	_main._focus_picture(&"game")
	while _main._move_in_flight:
		await get_tree().process_frame
	await _shoot("game_landed_pre_slide", &"game")
	while _main.hud_container.slid_fraction() <= 0.0:
		await get_tree().process_frame
	for i : int in 3:
		await RenderingServer.frame_post_draw
		await _shoot("slide_in_%d" % i, &"game")
	while _main.hud_container.slid_fraction() < 1.0:
		await get_tree().process_frame
	await _await_still()
	await _shoot("game_at_rest", &"game")

func _shoot_the_slide_out_of_the_game() -> void:
	_main._go_to_wall_view()
	for i : int in 3:
		await RenderingServer.frame_post_draw
		await _shoot("slide_out_%d" % i, &"game")
	while _main._move_in_flight:
		await get_tree().process_frame
