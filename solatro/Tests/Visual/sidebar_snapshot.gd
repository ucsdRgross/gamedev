extends Node2D
# res://Tests/Visual/sidebar_snapshot.gd
# By-eye diagnostic: boots the REAL `main.tscn`, enters the game screen through
# `Main.enter_game()` -- the same path a save's continue takes -- and screenshots the sidebar HUD.

const MAIN_SCENE := preload("res://Levels/main.tscn")
const FALLBACK_OUT_PATH := "user://sidebar_snapshot/game_hud.png"
const TOP_CASE_OUT_PATH := "user://sidebar_snapshot/game_hud_top.png"
const MAP_HUD_OUT_PATH := "user://sidebar_snapshot/map_hud.png"
const MAP_HUD_TOP_OUT_PATH := "user://sidebar_snapshot/map_hud_top.png"
const MENU_OUT_PATH := "user://sidebar_snapshot/menu.png"
const MENU_TOP_OUT_PATH := "user://sidebar_snapshot/menu_top.png"
const MENU_INSPECT_OUT_PATH := "user://sidebar_snapshot/menu_inspect.png"
const DESCRIPTION_OUT_PATH := "user://sidebar_snapshot/description.png"
const DESCRIPTION_LOCKED_OUT_PATH := "user://sidebar_snapshot/description_locked.png"
const DESCRIPTION_FOLLOW_OUT_PATH := "user://sidebar_snapshot/description_follow.png"
const DESCRIPTION_PROCESSING_OUT_PATH := "user://sidebar_snapshot/description_processing.png"
const DESCRIPTION_SCROLL_OUT_PATH := "user://sidebar_snapshot/description_scroll.png"
const VIEWER_DESCRIPTION_OUT_PATH := "user://sidebar_snapshot/viewer_description.png"
const VIEWER_DESCRIPTION_TOP_OUT_PATH := "user://sidebar_snapshot/viewer_description_top.png"
const CHOICE_VIEWER_OUT_PATH := "user://sidebar_snapshot/choice_viewer_description.png"
const CARD_LIFTED_OUT_PATH := "user://sidebar_snapshot/card_lifted.png"
const CARD_FOLLOWING_OUT_PATH := "user://sidebar_snapshot/card_following.png"
const ARMED_FOCUS_ELSEWHERE_OUT_PATH := "user://sidebar_snapshot/armed_focus_elsewhere.png"
# Only a placement that COMPLETES A LINE scores, and only a scoring cascade lasts long enough to
# photograph -- so placements repeat until one of them does, and each is watched for that many
# drawn frames before the tool gives up on it.
const CASCADE_PLACEMENT_ATTEMPTS := 24
const CASCADE_WATCH_FRAMES := 180
const TOP_CASE_WINDOW_SIZE := Vector2i(600, 1000)
# MEASURED: no card's own text overflows the container at the shipped `container_size_fraction`
# -- a square window's top band is 288 px and a description wraps to 97. So the scroll still
# narrows the band through the same settings override the wall editor uses.
const SCROLL_CASE_WINDOW_SIZE := Vector2i(500, 500)
const SCROLL_CASE_SIZE_FRACTION := 0.1
const SAVE_TAG := "sidebar_snapshot"
# Bound on `_await_deal_settled()`'s poll -- a real hang (not a settle) is a bug the tool should
# surface, not spin on forever.
const DEAL_SETTLE_TIMEOUT_SEC := 5.0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("sidebar_snapshot needs a REAL renderer. Re-run WITHOUT --headless.")
		get_tree().quit(1)
		return
	TestSuite.backup_real_save(SAVE_TAG)
	var window_size := _resolve_window_size()
	DisplayServer.window_set_size(window_size)
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture(MENU_OUT_PATH)

	DisplayServer.window_set_size(TOP_CASE_WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture(MENU_TOP_OUT_PATH)
	DisplayServer.window_set_size(window_size)
	await get_tree().process_frame
	await get_tree().process_frame

	var picker := await _open_the_pickers_viewer(main)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(MENU_INSPECT_OUT_PATH)
	if picker: picker.free()
	await get_tree().process_frame

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	main.map_scene.start_run(run)
	await main._focus_picture(&"map")
	await _await_map_generated(main.map_scene.controller)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture(MAP_HUD_OUT_PATH)

	DisplayServer.window_set_size(TOP_CASE_WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture(MAP_HUD_TOP_OUT_PATH)
	DisplayServer.window_set_size(window_size)
	await get_tree().process_frame
	await get_tree().process_frame

	await _open_a_booster_pack(main)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(CHOICE_VIEWER_OUT_PATH)
	var pack := _open_choice_viewer(main)
	if pack: pack.free()
	await get_tree().process_frame

	await main.enter_game()
	var view := (main._pictures[&"game"].screen_root as GameView)
	CardEnvironment.CURRENT = view.game
	await _await_deal_settled(view)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	await _await_held_card_settled(view, view.play_area.selected_cards[0])
	await RenderingServer.frame_post_draw
	_capture(_resolve_out_path())

	DisplayServer.window_set_size(TOP_CASE_WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(TOP_CASE_OUT_PATH)

	DisplayServer.window_set_size(window_size)
	await get_tree().process_frame
	await get_tree().process_frame

	await _move_the_focus_off_the_armed_card(main, view)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(ARMED_FOCUS_ELSEWHERE_OUT_PATH)

	_hover_a_board_card(main, view)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(DESCRIPTION_OUT_PATH)

	_hover_the_wordiest_board_card(main, view)
	await get_tree().process_frame
	var shipped_settings := WallPicture.editor_settings
	WallPicture.editor_settings = SettingsManager.settings.duplicate() as PlayerSettings
	WallPicture.editor_settings.container_size_fraction = SCROLL_CASE_SIZE_FRACTION
	DisplayServer.window_set_size(SCROLL_CASE_WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(DESCRIPTION_SCROLL_OUT_PATH)
	_report_overflow(main)
	WallPicture.editor_settings = shipped_settings
	DisplayServer.window_set_size(window_size)
	await get_tree().process_frame
	await get_tree().process_frame

	await _click_an_entrance_card(main, view)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(DESCRIPTION_LOCKED_OUT_PATH)

	await _hover_another_entrance_card(main, view)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(DESCRIPTION_FOLLOW_OUT_PATH)

	var armed := _arm_an_entrance_card(main, view)
	await _await_held_card_settled(view, armed)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(CARD_LIFTED_OUT_PATH)
	_report_held_lift(view, armed, "lifted")

	var pointer := _point_over_the_board(main, view)
	await _await_held_card_settled(view, armed)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(CARD_FOLLOWING_OUT_PATH)
	_report_held_lift(view, armed, "following", pointer)
	view.play_area.ungrab_cards()
	await get_tree().process_frame

	await _open_the_deck_viewer(view)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(VIEWER_DESCRIPTION_OUT_PATH)

	DisplayServer.window_set_size(TOP_CASE_WINDOW_SIZE)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(VIEWER_DESCRIPTION_TOP_OUT_PATH)
	DisplayServer.window_set_size(window_size)
	await get_tree().process_frame
	await get_tree().process_frame

	DeckViewer._open.free()
	await get_tree().process_frame

	var shot := await _shoot_a_cascade(main, view)
	print("SIDEBAR_SNAPSHOT cascade_captured=%s total=%d" % [shot, view.game.state.live_total()])

	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

# Waits for every Entrance card's own move tween to stop running -- the deal's spawn animation --
# so the still is never caught mid-flight. Bounded, not a fixed sleep: it returns the instant the
# board is actually settled.
func _await_deal_settled(view: GameView) -> void:
	var waited := 0.0
	while waited < DEAL_SETTLE_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if _deal_is_settled(view.play_area): return

# The deal spawns its `CardVisual`s deferred, one frame behind `enter_game()`'s own await, so
# "no tween running yet" is a false settle until at least one card has actually arrived.
func _deal_is_settled(pa: PlayArea) -> bool:
	if pa.data_card.is_empty() or not pa.visuals_ready(): return false
	for visual : CardVisual in pa.data_card.values():
		if visual.move_tween and visual.move_tween.is_running():
			return false
	return true

# The description's own still: a REAL pointer on a real board card, pushed into the game picture's
# own SubViewport, which is the space the board's controls are laid out in.
func _hover_a_board_card(main: Main, view: GameView) -> void:
	var viewport : SubViewport = main._pictures[&"game"].viewport
	var rect := Rect2(Vector2.ZERO, Vector2(viewport.size))
	for control : Control in view.play_area.ui_data:
		if not rect.encloses(control.get_global_rect()): continue
		_push_pointer(viewport, control.get_global_rect().get_center())
		return

# The SCROLL still: the board's WORDIEST card, which is the longest description the game screen can
# publish, READ FIRST and then squeezed -- the resize is what re-lays the description it already
# has, so the still never depends on a second hover landing on a second control.
func _hover_the_wordiest_board_card(main: Main, view: GameView) -> void:
	var viewport : SubViewport = main._pictures[&"game"].viewport
	var rect := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var wordiest : Control = null
	var longest := 0
	for control : Control in view.play_area.ui_data:
		if not rect.encloses(control.get_global_rect()): continue
		var words := ControlCard.describe_card(view.play_area.ui_data[control]).length()
		if words > longest:
			longest = words
			wordiest = control
	if wordiest: _push_pointer(viewport, wordiest.get_global_rect().get_center())

# The scroll still is worth looking at only if the body really overflows, which the window decides:
# printed so the by-eye pass reads a number instead of squinting at a thin scrollbar.
func _report_overflow(main: Main) -> void:
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var scroll : ScrollContainer = panel.get_node(^"%Scroll")
	print("SIDEBAR_SNAPSHOT window=%s scrollbar_visible=%s content=%.0f page=%.0f scroll=%d" % [
			get_viewport().get_visible_rect().size, scroll.get_v_scroll_bar().visible,
			scroll.get_v_scroll_bar().max_value, scroll.size.y, scroll.scroll_vertical])

# The FOLLOW still: a second card READ while the first stays locked, so the shot carries the
# hovered card's description beside the locked card's own marking. Walked until the board itself
# reports the pointer landed -- a control's centre is not always hit-testable, since cards overlap.
func _hover_another_entrance_card(main: Main, view: GameView) -> void:
	var viewport : SubViewport = main._pictures[&"game"].viewport
	for control : Control in _entrance_controls(view, viewport):
		if view.play_area.ui_data[control] == view.play_area.locked_data: continue
		_push_pointer(viewport, control.get_global_rect().get_center())
		await get_tree().process_frame
		if view.play_area.moused_hovered_control == control: return

# The LOCKED still: a real click on an Entrance card, which is where a click also GRABS, so the shot
# carries the exit X, the lifted and marked card and its description at once. Walked until the BOARD
# reports the grab -- cards overlap, so a control's own centre is not always hit-testable.
func _click_an_entrance_card(main: Main, view: GameView) -> void:
	var viewport : SubViewport = main._pictures[&"game"].viewport
	for control : Control in _entrance_controls(view, viewport):
		var at := control.get_global_rect().get_center()
		_push_pointer(viewport, at)
		await get_tree().process_frame
		_push_pointer(viewport, at)
		await get_tree().process_frame
		_push_click(viewport, at, true)
		await get_tree().process_frame
		_push_click(viewport, at, false)
		await get_tree().process_frame
		await get_tree().process_frame
		if not view.play_area.selected_cards.is_empty(): return

# The Entrance row's own controls: selectable, whole inside the picture's viewport (the space
# their rects are measured in), and backed by a visual on the Entrance layer. That row is where a
# click grabs, and it reads legibly in a still.
func _entrance_controls(view: GameView, viewport: SubViewport) -> Array[Control]:
	var rect := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var out : Array[Control] = []
	for control : Control in view.play_area.ui_data:
		if control.focus_mode == Control.FOCUS_NONE: continue
		if not rect.encloses(control.get_global_rect()): continue
		var data : CardData = view.play_area.ui_data[control]
		if not view.play_area.data_card.has(data): continue
		if view.play_area.data_card[data].get_parent() != view.play_area.entrance_card_layer:
			continue
		out.append(control)
	return out

# The PROCESSING still: a REAL placement, photographed while the cascade it started is still
# running. The placement also locks the description to the card it lands on, so what the shot
# proves is that the HUD -- whose numbers are what the cascade animates -- takes the container back.
func _shoot_a_cascade(main: Main, view: GameView) -> bool:
	for attempt : int in CASCADE_PLACEMENT_ATTEMPTS:
		if view.play_area.selected_cards.is_empty(): await _click_an_entrance_card(main, view)
		var held : Array[CardData] = view.play_area.selected_cards.duplicate()
		if held.is_empty(): continue
		var target := await _legal_target(view, held)
		if target == null: continue
		view.play_area.data_selected.emit(target)
		if await _capture_while_processing(view): return true
	return false

# Captured on the frame AFTER the board reports itself busy, so the still carries what was drawn
# while the cascade ran rather than the last frame before it started. Only a placement that
# COMPLETES A LINE scores, and only a scoring cascade lasts long enough to photograph.
func _capture_while_processing(view: GameView) -> bool:
	for frame : int in CASCADE_WATCH_FRAMES:
		await RenderingServer.frame_post_draw
		if view.game.processing:
			await RenderingServer.frame_post_draw
			_capture(DESCRIPTION_PROCESSING_OUT_PATH)
			return true
	return false

# A GRID landing the board itself accepts, asked through the same `on_can_place_stack` dispatch
# `try_place` uses, so no placement rule is spelled out in this tool. Only a grid cell runs the
# mutation pass that scores; stacking inside the Entrance is a legal move that cascades nothing.
func _legal_target(view: GameView, held: Array[CardData]) -> CardData:
	var candidates : Array[CardData] = []
	for control : Control in view.play_area.ui_data:
		var data : CardData = view.play_area.ui_data[control]
		if data in held: continue
		if not view.game.state.cell_type_coord(data).is_nowhere(): candidates.append(data)
	for data : CardData in candidates:
		var accepted : Array[CardData] = await view.game.return_first_data_array_result(
				&"on_can_place_stack", held, data)
		if not accepted.is_empty(): return data
	return null

func _push_pointer(viewport: SubViewport, at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion)

func _push_click(viewport: SubViewport, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	viewport.push_input(event)

# The map area shows only its loading text until generation finishes -- wait for that state
# rather than a fixed sleep, so the still is never caught mid-generation.
func _await_map_generated(controller: WorldMapController) -> void:
	if controller.is_generated(): return
	await controller.map_ready

func _capture(out_path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var dir := out_path.get_base_dir()
	if dir.begins_with("user://"): DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(out_path)
	print("SIDEBAR_SNAPSHOT wrote=", ProjectSettings.globalize_path(out_path))

func _resolve_out_path() -> String:
	var env := OS.get_environment("OUT_PATH")
	if not env.is_empty(): return env
	return FALLBACK_OUT_PATH

## WINDOW_W/WINDOW_H from the environment, else a 16:9 1280x720 window.
func _resolve_window_size() -> Vector2i:
	var w := OS.get_environment("WINDOW_W")
	var h := OS.get_environment("WINDOW_H")
	if w.is_empty() or h.is_empty(): return Vector2i(1280, 720)
	return Vector2i(int(w), int(h))

# The VIEWER still: the deck viewer opened through the container's own Deck button, with one of its
# listed cards under the key/pad highlight. The description then sits BESIDE the viewer's cards,
# which is the whole point of the inset the viewer takes.
func _open_the_deck_viewer(view: GameView) -> void:
	var button := view.deck_ui.get_node(^"Button") as Button
	button.grab_focus()
	await get_tree().process_frame
	button.pressed.emit()
	await get_tree().process_frame
	var cards := _listed_cards(DeckViewer._open.flow_container)
	if cards.size() >= 2: cards[1].grab_focus()
	await get_tree().process_frame

# The CHOICE still: a real booster node opened through the map's own handler, one pack card under
# the highlight -- the second viewer the sidebar took over from.
func _open_a_booster_pack(main: Main) -> void:
	var node := WorldGraphNode.new()
	node.meta[MapNodeRoles.ROLE_KEY] = MapNodeRoles.ROLE_BOOSTER
	node.meta[MapNodeRoles.BOOSTER_KEY] = TypeBoosterBasic.new()
	await main.map_scene._open_booster(node)
	node.free()
	await get_tree().process_frame
	var viewer := _open_choice_viewer(main)
	if viewer == null: return
	var cards := _listed_cards(viewer.flex_container)
	if not cards.is_empty(): cards[0].grab_focus()
	await get_tree().process_frame

# The MENU still with a viewer up: New Run opens the deck picker, the first deck's Inspect opens a
# viewer over the menu. That viewer is inset beside the container like every other, so the menu's
# own sidebar is never drawn over its listed cards. Returns the picker, to free the pair by.
func _open_the_pickers_viewer(main: Main) -> DeckPicker:
	main.menu_scene.new_run_button.pressed.emit()
	await get_tree().process_frame
	var picker : DeckPicker = main.menu_scene.find_child("DeckPicker", true, false) as DeckPicker
	if picker == null: return null
	((picker.rows.get_child(0) as HBoxContainer).get_child(1) as Button).pressed.emit()
	await get_tree().process_frame
	return picker

func _open_choice_viewer(main: Main) -> ChoiceViewer:
	for child : Node in main.map_scene.ui_layer.get_children():
		var viewer := child as ChoiceViewer
		if viewer: return viewer
	return null

func _listed_cards(container: Node) -> Array[ControlCard]:
	var cards : Array[ControlCard] = []
	for child : Node in container.get_children():
		var card := child as ControlCard
		if card: cards.append(card)
	return cards

# The LIFTED still: a pickup from somewhere that is NOT a click, so the card is held with nothing
# yet having told it to follow -- it rests on its own slot, raised by the lift.
func _arm_an_entrance_card(main: Main, view: GameView) -> CardData:
	var viewport : SubViewport = main._pictures[&"game"].viewport
	var data : CardData = view.play_area.ui_data[_entrance_controls(view, viewport)[0]]
	view.play_area.grab_cards([data] as Array[CardData])
	return data

# The FOCUS-ELSEWHERE still: the ARM gives the lift and the GLOW stays with the focus, so the two
# end up on different cards. The focus is moved the way a pad moves it, an arrow into the board's
# own viewport, and what actually happened is printed beside the still.
func _move_the_focus_off_the_armed_card(main: Main, view: GameView) -> void:
	var viewport : SubViewport = main._pictures[&"game"].viewport
	_point_over_the_board(main, view)
	await _await_held_card_settled(view, view.play_area.selected_cards[0])
	var key := InputEventKey.new()
	key.keycode = KEY_UP
	key.pressed = true
	viewport.push_input(key)
	await get_tree().process_frame
	var armed : CardData = view.play_area.selected_cards[0]
	var visual : CardVisual = view.play_area.data_card[armed]
	print("SIDEBAR_SNAPSHOT armed_focus_elsewhere focus_is_the_arm=%s held=%d glow=%s following=%s"
			% [viewport.gui_get_focus_owner() == view.play_area.data_ui[armed], visual.held,
					visual.focused, visual.following])

# The FOLLOWING still: the pointer is put over the middle of the board, which both starts the
# following and is where the card is then carried to.
func _point_over_the_board(main: Main, view: GameView) -> Vector2:
	var viewport : SubViewport = main._pictures[&"game"].viewport
	var at := Vector2(viewport.size) * 0.5
	_push_pointer(viewport, at)
	return at

# A held card EASES toward its target rather than snapping, so a still taken on the next frame
# catches it mid-flight. The grab's own rebuild can hand the card a DIFFERENT visual, so the live
# one is re-read every frame rather than held. Bounded: a card that never settles is a bug to see.
func _await_held_card_settled(view: GameView, data: CardData) -> void:
	var last := Vector2.INF
	var waited := 0.0
	while waited < DEAL_SETTLE_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var visual : CardVisual = view.play_area.data_card.get(data)
		if not visual: continue
		if visual.global_position.distance_to(last) < 0.05: return
		last = visual.global_position

# The by-eye question is whether the lift is the SAME height in both held states, so the number is
# printed beside the still: how far the card sits above what it aims at, slot or cursor.
func _report_held_lift(view: GameView, data: CardData, state: String,
		pointer := Vector2.INF) -> void:
	var visual : CardVisual = view.play_area.data_card[data]
	var aim := visual.get_card_control_center(visual.control_anchor)
	if pointer != Vector2.INF: aim = pointer + visual.cursor_ride_offset()
	print("SIDEBAR_SNAPSHOT %s following=%s lift=%.1f expected=%.1f" % [
			state, visual.following, aim.y - visual.global_position.y, visual.held_lift_px()])
