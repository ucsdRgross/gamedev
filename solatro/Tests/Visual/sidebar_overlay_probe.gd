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
	await _shoot_the_map_picking_nodes()

	await _shoot_the_slide_into_the_game()
	await _shoot_the_slide_out_of_the_game()
	await _await_still()
	await _measure_the_re_entry(&"game")
	await _await_still()
	await _measure_the_re_entry(&"map")
	await _go_back_to_wall_view()
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

# WHAT THE MAP SIDEBAR CARRIES AT EACH STEP OF A PICK. The container shows the HUD or the
# description and never both, so a pick's Deck button is a second one on the description side: these
# frames are what says whether all three buttons are actually on screen when they should be.
func _shoot_the_map_picking_nodes() -> void:
	var map := _main.map_scene
	await _pick(_a_node_with_role(MapNodeRoles.ROLE_GAME))
	await _shoot("map_node_picked", &"map")
	_report_buttons("a show node picked")
	map.controller.clear_selection()
	await _await_still()
	await _pick(_a_node_with_role(MapNodeRoles.ROLE_GAME))
	map.selection_deck_button.pressed.emit()
	await _await_still()
	await _shoot("map_deck_over_a_pick", &"map")
	DeckViewer._open._close()
	await _await_still()
	await _shoot("map_deck_closed_back_to_the_pick", &"map")
	_report_buttons("the deck viewer closed")
	map.controller.clear_selection()
	await _await_still()
	await _shoot_the_pack_node()

# A talent pack lists its contents on the FIRST pick and no later one, the sidebar being too narrow
# to read them in; the button beside the description is how they are asked for again.
func _shoot_the_pack_node() -> void:
	var map := _main.map_scene
	var pack := _a_node_with_role(MapNodeRoles.ROLE_BOOSTER)
	await _pick(pack)
	await _shoot("pack_first_pick_lists_its_cards", &"map")
	print("PROBE   viewer open=", is_instance_valid(DeckViewer._open))
	DeckViewer._open._close()
	await _await_still()
	await _shoot("pack_picked_after_closing", &"map")
	_report_buttons("a pack node picked")
	map.controller.clear_selection()
	await _await_still()
	await _pick(pack)
	await _shoot("pack_second_pick_opens_nothing", &"map")
	print("PROBE   viewer open=", is_instance_valid(DeckViewer._open))
	map.possible_cards_button.pressed.emit()
	await _await_still()
	await _shoot("pack_button_reopens_the_list", &"map")
	print("PROBE   viewer open=", is_instance_valid(DeckViewer._open))
	DeckViewer._open._close()
	map.controller.clear_selection()
	await _await_still()
	await _shoot_the_pack_chooser(pack)

# The pack the player actually keeps: a click picks one card, in an ink of its own, and the moving
# focus takes the rim back for as long as it is on that card. Take is live either way.
func _shoot_the_pack_chooser(pack: WorldGraphNode) -> void:
	var booster : BoosterTemplate = pack.meta.get(MapNodeRoles.BOOSTER_KEY)
	var viewer : ChoiceViewer = await booster.on_map_picked(_main.map_scene.ui_layer)
	_main.hud_container.host_viewer(viewer, _main.map_scene.wall_picture,
			_main.map_scene.info_hovered, HudContainer.MAP_SCREEN)
	await _await_still()
	await _shoot("chooser_nothing_picked", &"map")
	print("PROBE   take disabled=", viewer.confirm_button.disabled)
	var card : ControlCard = viewer._cards.controls[1]
	viewer.cards().stick_to(card.child.data)
	viewer.confirm_button.grab_focus()
	await _await_still()
	await _shoot("chooser_card_picked", &"map")
	card.grab_focus()
	await _await_still()
	await _shoot("chooser_focus_over_the_pick", &"map")
	print("PROBE   take disabled=", viewer.confirm_button.disabled,
			" picked=", viewer.cards().sticky != null)
	viewer.queue_free()
	await get_tree().process_frame

## Stands the token beside `node` when the map would refuse the pick, then picks it the way a player does.
func _pick(node: WorldGraphNode) -> void:
	var controller := _main.map_scene.controller
	if node not in controller.next_nodes_of(controller._current):
		for n : WorldGraphNode in controller.map.overlay().nodes():
			if node in controller.next_nodes_of(n):
				controller._current = n
				break
		controller.refresh_visuals()
	controller.select_node(node)
	await _await_still()

func _a_node_with_role(role: String) -> WorldGraphNode:
	for node : WorldGraphNode in _main.map_scene.controller.map.overlay().nodes():
		if node.meta.get(MapNodeRoles.ROLE_KEY, "") == role: return node
	return null

func _report_buttons(what: String) -> void:
	var map := _main.map_scene
	print("PROBE   ", what, ": hud deck=", _main.hud_container.map_deck_button.is_visible_in_tree(),
			" travel=", map.travel_button.is_visible_in_tree(),
			" pick deck=", map.selection_deck_button.is_visible_in_tree(),
			" possible cards=", map.possible_cards_button.is_visible_in_tree())

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

# EVERY FRAME of a re-entry from wall view: the picture's render target, its screen sprite's scale
# and what the texture reports -- the quantities a picture drawn at the wrong size shows up in.
# Photographs the landing frame and the few after it, where a wrong one is visible.
func _measure_the_re_entry(id: StringName) -> void:
	var wp : WallPicture = _main._pictures[id]
	print("PROBE REENTRY ", id, " design=", wp._design_size, " rect=", wp.rect.size,
			" wall_view viewport=", wp.viewport.size, " override=", wp.viewport.size_2d_override,
			" stretch=", wp.viewport.size_2d_override_stretch, " screen scale=", wp._screen.scale)
	_main._focus_picture(id)
	var frame := 0
	var after_focus := 0
	while _main._move_in_flight or after_focus < 6:
		await RenderingServer.frame_post_draw
		frame += 1
		if wp.is_focused: after_focus += 1
		var tex : Texture2D = wp._screen.texture
		var pa := _live_play_area()
		print("PROBE   f%d focused=%s viewport=%s override=%s stretch=%s scale=%s tex=%s drawn=%s cam_zoom=%.4f%s"
				% [frame, wp.is_focused, wp.viewport.size, wp.viewport.size_2d_override,
				wp.viewport.size_2d_override_stretch, wp._screen.scale, tex.get_size(),
				tex.get_size() * wp._screen.scale,
				(_main.wall.get_node(^"%Camera2D") as Camera2D).zoom.x,
				(" board_zoom=%.4f scroll_scale=%.4f scroll_pos=%s slide=%s p2w=%.4f vis=%s" % [
				pa.board_zoom, pa.scroll_container.scale.x, pa.scroll_container.global_position,
				pa.board_slide_offset, pa.picture_to_window_scale,
				wp.viewport.get_visible_rect().size]) if pa else ""])
		if wp.is_focused and after_focus <= 4:
			var img := get_viewport().get_texture().get_image()
			img.save_png(_out_dir.path_join("p24_%s_reentry_%d.png" % [id, after_focus]))

# Leaves whatever is focused, so the next measurement starts from wall view.
func _go_back_to_wall_view() -> void:
	await _main._go_to_wall_view()
	await _await_still()

func _shoot_the_slide_out_of_the_game() -> void:
	_main._go_to_wall_view()
	for i : int in 3:
		await RenderingServer.frame_post_draw
		await _shoot("slide_out_%d" % i, &"game")
	while _main._move_in_flight:
		await get_tree().process_frame
