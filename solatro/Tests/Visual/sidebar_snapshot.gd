extends Node2D
# res://Tests/Visual/sidebar_snapshot.gd
# By-eye diagnostic: boots the REAL `main.tscn`, enters the game screen through
# `Main.enter_game()` -- the same path a save's continue takes -- and screenshots the sidebar HUD.

const MAIN_SCENE := preload("res://Levels/main.tscn")
const FALLBACK_OUT_PATH := "user://sidebar_snapshot/game_hud.png"
const TOP_CASE_OUT_PATH := "user://sidebar_snapshot/game_hud_top.png"
const CROPPED_SIDE_OUT_PATH := "user://sidebar_snapshot/game_hud_cropped_side.png"
const MAP_HUD_OUT_PATH := "user://sidebar_snapshot/map_hud.png"
const MAP_HUD_TOP_OUT_PATH := "user://sidebar_snapshot/map_hud_top.png"
const MAP_POPUP_OUT_PATH := "user://sidebar_snapshot/map_popup.png"
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
const VIEWER_HOVER_OUT_PATH := "user://sidebar_snapshot/viewer_hover_no_x.png"
const VIEWER_STICKY_OUT_PATH := "user://sidebar_snapshot/viewer_sticky_with_x.png"
const VIEWER_CLOSED_OUT_PATH := "user://sidebar_snapshot/viewer_closed_hud.png"
const MAP_CARD_DESCRIPTION_OUT_PATH := "user://sidebar_snapshot/map_card_description.png"
const ENTRANCE_STOCKS_OUT_PATH := "user://sidebar_snapshot/entrance_stocks.png"
const ENTRANCE_FLIP_MID_OUT_PATH := "user://sidebar_snapshot/entrance_flip_mid.png"
# Slow enough that the stagger is a THING YOU CAN SEE in one still: at the shipped 0.15 the whole
# row is over before a frame lands. The still is of the mechanism, not of the shipped pacing.
const FLIP_STILL_DELAY_SEC := 1.0
const FLIP_STILL_STAGGER := 0.5
const FLIP_STILL_FRAMES := 30
const CARD_LIFTED_OUT_PATH := "user://sidebar_snapshot/card_lifted.png"
const CARD_FOLLOWING_OUT_PATH := "user://sidebar_snapshot/card_following.png"
const LIFTED_FOCUS_ELSEWHERE_OUT_PATH := "user://sidebar_snapshot/lifted_focus_elsewhere.png"
const DRAG_RELEASE_DROPPED_OUT_PATH := "user://sidebar_snapshot/drag_release_dropped.png"
const CANCEL_FIRST_PRESS_OUT_PATH := "user://sidebar_snapshot/cancel_first_press.png"
const GOAL_MET_OUT_PATH := "user://sidebar_snapshot/goal_met.png"
const OUTCOME_BUTTONS_OUT_PATH := "user://sidebar_snapshot/outcome_buttons.png"
# Only a placement that COMPLETES A LINE scores, and only a scoring cascade lasts long enough to
# photograph -- so placements repeat until one of them does, and each is watched for that many
# drawn frames before the tool gives up on it.
const CASCADE_PLACEMENT_ATTEMPTS := 24
const CASCADE_WATCH_FRAMES := 180
const TOP_CASE_WINDOW_SIZE := Vector2i(600, 1000)
# 16:10, so the game picture COVERS the window and is cropped left and right while the container
# stays on the SIDE -- the shape the board's region has to clear the container on.
const CROPPED_SIDE_WINDOW_SIZE := Vector2i(1280, 800)
# MEASURED: no card's own text overflows the container at the shipped `container_size_fraction`
# -- a square window's top band is 288 px and a description wraps to 97. So the scroll still
# narrows the band through the same settings override the wall editor uses.
const SCROLL_CASE_WINDOW_SIZE := Vector2i(500, 500)
const SCROLL_CASE_SIZE_FRACTION := 0.1
const SAVE_TAG := "sidebar_snapshot"
# Bound on `_await_deal_settled()`'s poll -- a real hang (not a settle) is a bug the tool should
# surface, not spin on forever.
## The picture's own top-left corner, where the board lays out no cell and no card.
const BARE_BOARD_POINT := Vector2(24.0, 24.0)
const DEAL_SETTLE_TIMEOUT_SEC := 5.0
## How many consecutive frames the board's cells must not move before a shot is taken of it.
const BOARD_STILL_FRAMES := 3

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

	_hover_a_pack_node(main.map_scene)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(MAP_POPUP_OUT_PATH)

	await _describe_a_card_on_the_map(main)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(MAP_CARD_DESCRIPTION_OUT_PATH)
	print("SIDEBAR_SNAPSHOT map_card_description buttons_visible=%s"
			% main.map_scene.selection_buttons.visible)
	if is_instance_valid(DeckViewer._open): DeckViewer._open.free()
	await get_tree().process_frame


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
	_capture(_resolve_out_path())

	await _report_the_entrance_depth(view)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(ENTRANCE_STOCKS_OUT_PATH)

	DisplayServer.window_set_size(TOP_CASE_WINDOW_SIZE)
	await _await_board_settled(view.play_area)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(TOP_CASE_OUT_PATH)
	_report_the_board_geometry(view, "game_hud_top")

	DisplayServer.window_set_size(CROPPED_SIDE_WINDOW_SIZE)
	await _await_board_settled(view.play_area)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(CROPPED_SIDE_OUT_PATH)
	_report_the_board_geometry(view, "game_hud_cropped_side")

	DisplayServer.window_set_size(window_size)
	await get_tree().process_frame
	await get_tree().process_frame

	await _move_the_focus_off_the_lifted_card(main, view)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(LIFTED_FOCUS_ELSEWHERE_OUT_PATH)
#The click that lifts the card also locks its description, and a lock outlives every hover: the
#stills below are of what a HOVER publishes, so the hand and the lock are emptied before them.
	view.play_area.ungrab_cards()
	view.hud_container.dismiss_description()
	await get_tree().process_frame

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
	var follow_title : Label = view.hud_container.get_node(^"%DescriptionPanel").get_node(^"%Title")
	print("SIDEBAR_SNAPSHOT description_follow locked=%s showing=%s" % [
			view.hud_container.is_locked(), follow_title.text])

	var lifted := await _lift_an_entrance_card(main, view)
	await _await_held_card_settled(view, lifted)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(CARD_LIFTED_OUT_PATH)
	_report_held_lift(view, lifted, "lifted")
	_report_the_drop_map(view, "card_lifted")

	var pointer := await _drag_over_the_board(main, view, lifted)
	await _await_held_card_settled(view, lifted)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(CARD_FOLLOWING_OUT_PATH)
	_report_held_lift(view, lifted, "following", pointer)

	await _release_off_a_cell(main, view, lifted)
	await _await_held_card_settled(view, lifted)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(DRAG_RELEASE_DROPPED_OUT_PATH)
	_report_held_lift(view, lifted, "drag_release_dropped")
	_report_the_drop_map(view, "drag_release_dropped")
	await get_tree().process_frame

	await _click_an_entrance_card(main, view)
	var cancelled := await _cancel_the_held_card_once(main, view)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(CANCEL_FIRST_PRESS_OUT_PATH)
	print("SIDEBAR_SNAPSHOT cancel_first_press held=%d description=%s" % [
			view.play_area.selected_cards.size(), str(cancelled)])

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

	await _shoot_the_sticky_trio(view)

	await _refill_the_whole_entrance(view)
	_capture(ENTRANCE_FLIP_MID_OUT_PATH)

	await _show_the_goal_met(view)
	var shot := await _shoot_a_cascade(main, view)
	print("SIDEBAR_SNAPSHOT cascade_captured=%s total=%d" % [shot, view.game.state.live_total()])

	await _end_the_show(view)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(OUTCOME_BUTTONS_OUT_PATH)
	_report_the_outcome_buttons(main, view)

	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	TestSuite.restore_real_save(SAVE_TAG)
	get_tree().quit()

# THE OUTCOME still: the show is ended the way reaching the goal ends it, once whatever the cascade
# was still running has settled. The goal is dropped to the board's own total, so what is
# photographed is the WIN screen and its buttons.
func _end_the_show(view: GameView) -> void:
	for frame : int in CASCADE_WATCH_FRAMES:
		if not view.game.processing: break
		await RenderingServer.frame_post_draw
	view.game.state.goal = view.game.state.live_total()
	view.game.end_show()
	await get_tree().process_frame

# What the outcome is OFFERING, in the PIXELS of the capture: the window is stretched
# (`canvas_items`, `expand`), so canvas units are carried to the PNG through the root viewport's
# own final transform -- the same map the engine draws with, never a factor typed here.
func _report_the_outcome_buttons(main: Main, view: GameView) -> void:
	var screen : Label = view.win_screen if view.win_screen.visible else view.lose_screen
	var root : Viewport = view.hud_container.get_viewport()
	var window := root.get_visible_rect().size
	var to_pixels := root.get_final_transform()
	var design := Vector2(PlayArea.game_picture_design_size(PlayArea.settings()))
	var scale := WallPicture.cover_scale(design, window)
	var drawn : Array[String] = []
	for button : Button in screen.find_children("*", "Button", true, false):
		var span := _drawn_span_x(button, view.play_area.board_visible_crop, scale)
		drawn.append("%s=%.1f..%.1f" % [button.text, (to_pixels * Vector2(span.x, 0.0)).x,
				(to_pixels * Vector2(span.y, 0.0)).x])
	var focused : Control = (main._pictures[&"game"].viewport as SubViewport).gui_get_focus_owner()
	var focus_label := "none"
	if focused is Button: focus_label = (focused as Button).text
	print(("SIDEBAR_SNAPSHOT outcome_buttons won=%s drawn_x=[%s] container_right=%.1f focus=%s "
			+ "hud_undo_up=%s") % [view.win_screen.visible, ", ".join(drawn),
			(to_pixels * view.hud_container.container_rect().end).x, focus_label,
			view.undo_button.is_visible_in_tree()])

# The Goal wears its met state the instant the total reaches it, one beat before the show ends --
# too short to photograph from a real placement, so the goal is dropped TO the settled board's
# total instead. End stays hidden: there are still cards to draw and empty tiles to fill.
func _show_the_goal_met(view: GameView) -> void:
	var was := view.game.state.goal
	view.hud_container.show_hud()
	view.game.state.goal = view.game.state.live_total()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(GOAL_MET_OUT_PATH)
	print("SIDEBAR_SNAPSHOT goal_met total=%d goal=%d end_visible=%s" % [
			view.game.state.live_total(), view.game.state.goal,
			str(view.submit_button.visible)])
	view.game.state.goal = was

# THE SHOT'S NUMBERS IN THE IMAGE'S OWN SPACE, so it can be checked rather than admired: the
# board's left edge against the container's right edge, and the grid's and the Entrance's drawn
# centres against the centre of the space left beside the container.
func _report_the_board_geometry(view: GameView, shot: String) -> void:
	var window := view.hud_container.get_viewport().get_visible_rect().size
	var design := Vector2(PlayArea.game_picture_design_size(PlayArea.settings()))
	var pa := view.play_area
	var scale := WallPicture.cover_scale(design, window)
	var origin := pa.board_visible_crop
	var board := _drawn_span_x(pa.scroll_container, origin, scale)
	var block := _drawn_span_x(pa._cells_root(pa.grid_container.get_child(0) as Control), origin, scale)
	var entrance := _drawn_span_x(pa.upper_zone_right, origin, scale)
	print(("SIDEBAR_SNAPSHOT %s window=%s grids=%d zoom=%.3f inset_picture_px=%.1f "
			+ "crop_picture_px=%.1f container_right=%.1f board=%.1f..%.1f cells=%.1f..%.1f "
			+ "entrance=%.1f..%.1f") % [shot, window, view.game.state.grids.size(), pa.board_zoom,
			pa.board_inset_left, origin.x, view.hud_container.container_rect().end.x,
			board.x, board.y, block.x, block.y, entrance.x, entrance.y])

## A control's DRAWN horizontal span as `(left, right)` in the root viewport's canvas units: its own transform carries every scale above it, and the picture's crop and cover scale carry it out to the wall.
func _drawn_span_x(c: Control, crop: Vector2, scale: float) -> Vector2:
	var t := c.get_global_transform()
	var left := (t.origin.x - crop.x) * scale
	return Vector2(left, left + t.get_scale().x * c.size.x * scale)

# WHAT THE FACE-DOWN CARD COSTS THE BOARD, measured rather than argued: the Entrance is row -1, so
# its real depth is what the board's floor has to clear, and a deeper row pushes everything above
# it up. Reported with the face-down card and again with the stocks set aside.
func _report_the_entrance_depth(view: GameView) -> void:
	var pa := view.play_area
	_print_the_entrance_depth(pa, "face_down")
	var parked : Array[Array] = []
	for stock : ArrayCardData in view.game.state.entrance_stocks():
		parked.append(stock.datas.duplicate())
		stock.datas.clear()
	pa.set_card_zones()
	await get_tree().process_frame
	await get_tree().process_frame
	_print_the_entrance_depth(pa, "exhausted")
	var stocks := view.game.state.entrance_stocks()
	for i : int in parked.size():
		stocks[i].datas.assign(parked[i])
	pa.set_card_zones()
	await get_tree().process_frame
	await get_tree().process_frame

func _print_the_entrance_depth(pa: PlayArea, label: String) -> void:
	print("SIDEBAR_SNAPSHOT entrance_depth %s strip_full=%.2f row=%.2f card0_y=%.2f cell0_y=%.2f" % [
			label, pa._entrance_strip_full_height(), pa._entrance_row_height(),
			pa.slot_center_global(BoardCoord.new(0, 0, BoardCoord.ENTRANCE_ROW, 0)).y,
			pa.slot_center_global(BoardCoord.new(0, 0, 0, 0)).y])

# THE FLIP, CAUGHT PARTWAY ACROSS THE ROW: every slot is emptied into the discard and refilled
# through the game's own refill, so the still is of the product's own staggered turn-over.
func _refill_the_whole_entrance(view: GameView) -> void:
	var settings := SettingsManager.settings
	var old_delay := settings.base_delay
	var old_stagger := settings.entrance_flip_stagger
	settings.base_delay = FLIP_STILL_DELAY_SEC
	settings.entrance_flip_stagger = FLIP_STILL_STAGGER
	view.play_area.ungrab_cards()
	for column : ArrayCardData in Board.zone(view.game.state, 0):
		view.game.state.discard_deck.append_array(column.datas)
		column.datas.clear()
	view.game.state.revision += 1
	view.play_area.set_card_zones()
	await get_tree().process_frame
	await view.game.refill_entrance_if_due()
	view.play_area.flush_rebuild()
	for frame : int in FLIP_STILL_FRAMES:
		await RenderingServer.frame_post_draw
	settings.base_delay = old_delay
	settings.entrance_flip_stagger = old_stagger

# ⚠ THE BOARD MOVES OVER SEVERAL FRAMES, both on a deal's spawn tweens and on a resize, where the
# scroller reaches its new resting x a layout pass at a time -- a shot two frames after either
# photographs a transient. Bounded, not a fixed sleep: it returns the instant the board is settled.
func _await_board_settled(pa: PlayArea) -> void:
	var last := INF
	var still := 0
	var waited := 0.0
	while waited < DEAL_SETTLE_TIMEOUT_SEC and still < BOARD_STILL_FRAMES:
		await get_tree().physics_frame
		await get_tree().process_frame
		waited += get_process_delta_time()
		var now := pa._cells_root(pa.grid_container.get_child(0) as Control).global_position.x
		still = still + 1 if is_equal_approx(now, last) else 0
		last = now

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

# The SCROLL still: the board's WORDIEST card, READ FIRST and then squeezed so the resize re-lays it.
# The held card goes back first: a held card's pointer crossing out of its own cell is a dismissal,
# which would leave the still showing the HUD instead of the description it is named for.
func _hover_the_wordiest_board_card(main: Main, view: GameView) -> void:
	view.play_area.ungrab_cards()
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

# The FOLLOW still: the lock kept but the card set down first, since a click there also grabs and a
# held card leaving its cell dismisses the lock. Walked until the board reports the pointer landed:
# cards overlap, so a control's centre is not always hit-testable.
func _hover_another_entrance_card(main: Main, view: GameView) -> void:
	view.play_area.ungrab_cards()
	await get_tree().process_frame
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
		var legal := await view.game.legal_cells_for(held, view.game.state.grids)
		if legal.is_empty(): continue
		view.play_area.data_selected.emit(legal[0])
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

func _push_pointer(viewport: SubViewport, at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion)

# ONE press of the cancel button on a held card: the by-eye question is whether the card goes back
# to its slot while the description it was read against stays up, so the answer is printed too.
func _cancel_the_held_card_once(main: Main, view: GameView) -> bool:
	var viewport : SubViewport = main._pictures[&"game"].viewport
	var data : CardData = view.play_area.selected_cards[0]
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = view.play_area.data_ui[data].get_global_rect().get_center()
	event.global_position = event.position
	viewport.push_input(event)
	await _await_held_card_settled(view, data)
	return view.hud_container.showing_description()

func _push_click(viewport: SubViewport, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	viewport.push_input(event)

# The MAP still: a talent-pack node hovered, so the one frame carries both halves of the map's
# answer -- the name at the dot, and the pack's whole preview grid in the sidebar beside it.
func _hover_a_pack_node(map: Map) -> void:
	for node : WorldGraphNode in map.controller.map.overlay().nodes():
		if node.meta.get(MapNodeRoles.ROLE_KEY, "") == MapNodeRoles.ROLE_BOOSTER:
			map._on_node_hovered(node)
			return

# The map area shows only its loading text until generation finishes -- wait for that state
# rather than a fixed sleep, so the still is never caught mid-generation.
func _await_map_generated(controller: WorldMapController) -> void:
	if controller._accepting_input: return
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

# THE THREE STATES A VIEWER CARD PASSES THROUGH, in one still each: hovered with no exit X, clicked
# and sticky with one, and the HUD the close comes back to.
func _shoot_the_sticky_trio(view: GameView) -> void:
	var cards := _listed_cards(DeckViewer._open.flow_container)
	if cards.size() < 2: return
	var card := cards[1]
	card.grab_focus()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(VIEWER_HOVER_OUT_PATH)
	print("SIDEBAR_SNAPSHOT viewer_hover sticky=%s exit_x_visible=%s"
			% [DeckViewer._open.cards().sticky, (view.hud_container.get_node(^"%ExitX") as Control).visible])
	DeckViewer._open.cards().stick_to(card.child.data)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(VIEWER_STICKY_OUT_PATH)
	print("SIDEBAR_SNAPSHOT viewer_sticky sticky=%s exit_x_visible=%s"
			% [DeckViewer._open.cards().sticky, (view.hud_container.get_node(^"%ExitX") as Control).visible])
	DeckViewer._open._close()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_capture(VIEWER_CLOSED_OUT_PATH)
	print("SIDEBAR_SNAPSHOT viewer_closed description=%s"
			% view.hud_container.showing_description())

# ⚠ EVERY WAIT HERE IS ON A STATE, NOT A FRAME COUNT: the wall camera is still easing into the
# picture, an unreachable pack refuses the pick outright, and the preview cards come from a
# coroutine -- a fixed number of frames photographed a half-travelled map with no viewer.
func _describe_a_card_on_the_map(main: Main) -> void:
	var map := main.map_scene
	var pack := _the_pack_node(map)
	if pack == null: return
	await _await_the_wall_camera_still(main)
	_make_the_node_reachable(map.controller, pack)
	map.controller.select_node(pack)
	await _await_a_viewer()
# A PACK LISTS WHAT IT COULD ROLL, which is mostly PART of a card and describes as nothing. The
# still is of a card DESCRIPTION, so the pack's own viewer gives way to the run deck's.
	if is_instance_valid(DeckViewer._open): DeckViewer._open._close()
	await get_tree().process_frame
	map.selection_deck_button.pressed.emit()
	await _await_a_viewer()
	if not is_instance_valid(DeckViewer._open): return
	var told := _the_most_described_card(_listed_cards(DeckViewer._open.flow_container))
	if told: told.grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	print("SIDEBAR_SNAPSHOT map_card_description title=%s"
			% (ControlCard.describe_card(told.child.data) if told else "<none>"))

# A PACK LISTS WHAT IT COULD ROLL, which is mostly PART of a card -- a bare rank, a bare suit. The
# still is of a description, so the card with the most to say is the one put under the highlight.
func _the_most_described_card(cards: Array[ControlCard]) -> ControlCard:
	var best : ControlCard = null
	var longest := 0
	for card : ControlCard in cards:
		var length := ControlCard.describe_card(card.child.data).length()
		if length > longest:
			longest = length
			best = card
	return best

## Waits for a viewer to actually be up: a pack's preview cards and the run deck alike come through a coroutine.
func _await_a_viewer() -> void:
	for frame : int in CASCADE_WATCH_FRAMES:
		if is_instance_valid(DeckViewer._open) 				and not DeckViewer._open.is_queued_for_deletion(): return
		await get_tree().process_frame

## Puts the token one step before `node`, since the map refuses a pick it cannot reach from where the token stands.
func _make_the_node_reachable(controller: WorldMapController, node: WorldGraphNode) -> void:
	if node in controller.next_nodes_of(controller._current): return
	for n : WorldGraphNode in controller.map.overlay().nodes():
		if node in controller.next_nodes_of(n):
			controller._current = n
			controller.refresh_visuals()
			return

## The wall camera has stopped easing into the picture: a still taken before it has is of a picture half off the window.
func _await_the_wall_camera_still(main: Main) -> void:
	var camera : Camera2D = main.wall.get_node(^"%Camera2D")
	var last := Transform2D()
	var still := 0
	for frame : int in CASCADE_WATCH_FRAMES:
		var now := camera.get_global_transform()
		still = still + 1 if frame > 0 and now == last else 0
		if still >= BOARD_STILL_FRAMES: return
		last = now
		await RenderingServer.frame_post_draw

## The generated map's first talent-pack node, whose pick opens a viewer of its possible cards.
func _the_pack_node(map: Map) -> WorldGraphNode:
	for node : WorldGraphNode in map.controller.map.overlay().nodes():
		if node.meta.get(MapNodeRoles.ROLE_KEY, "") == MapNodeRoles.ROLE_BOOSTER: return node
	return null

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

# The LIFTED still: a real CLICK on an Entrance card, which holds it raised in its own slot with
# nothing having told it to follow. The hand is emptied first so the click really lands.
func _lift_an_entrance_card(main: Main, view: GameView) -> CardData:
	view.play_area.ungrab_cards()
	await _click_an_entrance_card(main, view)
	return view.play_area.selected_cards[0]

# The FOCUS-ELSEWHERE still: a card RESTING in its slot at its lift, taken up by the CLICK that is
# the only route to that state. The focus then moves by ARROW ALONE, and what actually happened is
# printed beside the still.
func _move_the_focus_off_the_lifted_card(main: Main, view: GameView) -> void:
	var viewport : SubViewport = main._pictures[&"game"].viewport
	var data := await _lift_an_entrance_card(main, view)
	await _await_held_card_settled(view, data)
	var key := InputEventKey.new()
	key.keycode = KEY_UP
	key.pressed = true
	viewport.push_input(key)
	await get_tree().process_frame
	var visual : CardVisual = view.play_area.data_card[data]
	print("SIDEBAR_SNAPSHOT lifted_focus_elsewhere focus_is_the_card=%s held=%d glow=%s following=%s"
			% [viewport.gui_get_focus_owner() == view.play_area.data_ui[data], visual.held,
					visual.focused, visual.following])

# The FOLLOWING still: a real press on the lifted card, carried out to the middle of the board with
# the button still down, which is both what starts the chase and where the card is carried to.
func _drag_over_the_board(main: Main, view: GameView, data: CardData) -> Vector2:
	var viewport : SubViewport = main._pictures[&"game"].viewport
	var from : Vector2 = view.play_area.data_ui[data].get_global_rect().get_center()
	_push_pointer(viewport, from)
	await get_tree().process_frame
	_push_click(viewport, from, true)
	await get_tree().process_frame
	var at := Vector2(viewport.size) * 0.5
	_push_pointer(viewport, at)
	await get_tree().process_frame
	return at

# THE FAILED DRAG's still: a real press on the held card, carried out over the board and released
# where there is no cell to land on -- not a placeable spot -- so the card goes back to its slot
# with nothing holding it, and the pointer is left where it let go.
func _release_off_a_cell(main: Main, view: GameView, data: CardData) -> void:
	var viewport : SubViewport = main._pictures[&"game"].viewport
	var from : Vector2 = view.play_area.data_ui[data].get_global_rect().get_center()
	_push_pointer(viewport, from)
	await get_tree().process_frame
	_push_click(viewport, from, true)
	await get_tree().process_frame
	_push_pointer(viewport, BARE_BOARD_POINT)
	await get_tree().process_frame
	_push_click(viewport, BARE_BOARD_POINT, false)
	await get_tree().process_frame

# The drop map is a brightening, so the still is checked against a COUNT: how many of the board's
# cells the sweep marked legal for the card in hand, read back off the visuals that are drawing it.
func _report_the_drop_map(view: GameView, shot: String) -> void:
	var cells := 0
	for grid : GridData in view.game.state.grids:
		cells += grid.cells.size()
	print("SIDEBAR_SNAPSHOT %s legal_cells=%d of=%d glow=%.3f held=%d" % [
			shot, TestGridFixtures.lit_cell_count(view.play_area), cells,
			PlayArea.settings().highlight_glow, view.play_area.selected_cards.size()])

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
