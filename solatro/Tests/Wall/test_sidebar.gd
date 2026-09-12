extends TestSuite
# res://Tests/Wall/test_sidebar.gd
# SIDEBAR: HudContainer and DescriptionPanel as empty shells -- exactly one content
# child visible at a time, HUD by default.

const HUD_CONTAINER_SCENE := preload("res://UI/hud_container.tscn")
const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const MAIN_SCENE := preload("res://Levels/main.tscn")
const MAP_SCENE := preload("res://Levels/map.tscn")
const MENU_SCENE := preload("res://Levels/menu.tscn")

# Measured on the pre-deletion tree (Part A, `%MultScore`/`%Preview` still mounted). The inset
# formula never depended on either retired control, so this is expected to stay unchanged.
const MEASURED_BOARD_CENTRE_PX := 733.808

func suite_name() -> String:
	return "SIDEBAR"

# This suite hosts a real GameView and writes the shared `CardEnvironment.CURRENT`, so it waits
# for every sibling that hosts one too. See TestSuite's DEADLOCK RULE and its ordering chain.
func _ready() -> void:
	await await_siblings_except(["SETTINGS RANGE", "E2E RUN", "LEAK CANARY", "WALL PAUSE"])
	TestLog.line("============ SIDEBAR TEST PASS ============")
	behavior_section("CONTAINER SHOWS EXACTLY ONE CHILD")
	test_default_state_is_the_hud()
	test_show_hud_shows_only_the_hud_stack()
	test_show_description_shows_only_the_description_panel()
	behavior_section("THE GAME SCREEN'S HUD (S2)")
	test_game_hud_holds_exactly_the_eight_members()
	test_no_retired_furniture_nodes_remain()
	test_overlay_buttons_draw_above_the_hud_container()
	await test_every_hud_member_is_visible_and_reachable()
	await test_number_captions_and_values_do_not_overlap()
	await test_game_hud_members_start_below_the_overlay_button_band()
	await test_pressing_end_reaches_the_live_game_views_handler()
	await test_a_second_shows_view_receives_the_press_after_the_first_tears_down()
	await test_the_game_views_hud_container_is_scoped_to_its_own_wall()
	behavior_section("THE CONTAINER'S GEOMETRY")
	await test_game_hud_members_stay_inside_the_container_at_a_side_window()
	test_the_inset_is_394_at_the_pictures_own_aspect()
	test_an_ultrawide_window_clamps_and_narrows()
	test_the_container_moves_to_the_top_when_the_leftover_would_be_taller_than_wide()
	await test_board_centre_after_hud_migration_matches_the_pre_deletion_measurement()
	await test_a_real_resize_moves_the_container_and_republishes_the_inset()
	await test_a_top_case_resize_fits_the_board_under_the_band()
	behavior_section("S4: THE MAP GETS THE SAME CONTAINER")
	test_map_hud_holds_exactly_the_four_members_and_maps_own_ui_is_empty_of_them()
	await test_focus_change_drives_which_hud_stack_child_shows()
	await test_map_deck_button_reaches_the_live_maps_handler_then_disconnects()
	await test_maps_camera_offset_moves_beside_the_container_not_under_it()
	await test_menus_buttons_lie_outside_the_container_and_inside_the_window()
	await test_menus_scale_is_uniform_and_keeps_each_buttons_authored_aspect()
	await test_menus_title_and_button_row_centre_on_the_remaining_space()
	behavior_section("S5: A HIGHLIGHT PUBLISHES AND THE CONTAINER SHOWS")
	await test_a_highlight_opens_the_description()
	await test_the_preview_is_drawn_at_the_boards_own_card_size()
	await test_losing_the_highlight_keeps_the_last_entry()
	await test_leaving_and_returning_restores_the_screens_own_description()
	await test_a_new_entry_frees_the_visual_it_replaces()
	behavior_section("S6: THE LOCK AND THE EXIT X")
	await test_a_click_grabs_the_card_and_locks_its_description()
	await test_locking_a_second_card_replaces_the_first()
	await test_the_locked_card_keeps_its_marking_while_focus_moves_on()
	await test_a_board_rebuild_keeps_the_same_cards_description()
	await test_the_exit_x_reverts_to_the_hud()
	await test_the_exit_x_is_a_touch_target_below_the_button_band()
	await test_a_resize_relays_the_description_to_the_new_width()
	behavior_section("S6: FOLLOW, RETURN AND DISMISS")
	await test_the_description_follows_the_hover_while_locked()
	await test_leaving_everything_returns_to_the_locked_card()
	await test_focus_leaving_the_board_returns_to_the_locked_card()
	await test_cancel_reverts_to_the_hud_and_only_then_is_spent()
	await test_a_press_on_bare_board_reverts_to_the_hud()
	await test_placing_a_card_closes_the_description()
	await test_replacing_a_displaced_lock_frees_its_visual()
	behavior_section("S7: THE PROCESSING RULE")
	test_the_same_entry_published_again_after_processing_still_shows()
	await test_processing_reverts_to_the_hud_and_drops_the_lock()
	await test_a_real_cascade_holds_the_hud_for_its_whole_length()
	await test_a_hover_during_processing_changes_nothing()
	await test_the_hud_holds_after_processing_until_any_focus_event()
	await test_the_maps_container_does_not_swap_on_the_games_processing()
	behavior_section("S8: SCROLL AND MULTI-MODAL REACH")
	test_the_sidebar_scroll_action_binds_the_non_navigation_stick()
	await test_a_long_description_shows_a_scrollbar_and_rests_at_the_top()
	await test_a_short_description_hides_the_scrollbar()
	await test_page_keys_scroll_the_description_by_a_page()
	await test_the_scroll_stick_scrolls_the_description_and_not_the_hud()
	await test_the_arrows_scroll_only_once_the_description_is_locked()
	await test_the_exit_x_joins_navigation_only_while_locked()
	finish()

func _build_container() -> HudContainer:
	var container : HudContainer = HUD_CONTAINER_SCENE.instantiate()
	add_child(container)
	return container

func _visible_content_children(container: HudContainer) -> int:
	var hud_stack : Control = container.get_node(^"%HudStack")
	var description_panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var count := 0
	if hud_stack.visible: count += 1
	if description_panel.visible: count += 1
	return count

## Q170=a: the container shows the HUD by default, with no `Main` and no wall in the tree.
func test_default_state_is_the_hud() -> void:
	var container := _build_container()
	var hud_stack : Control = container.get_node(^"%HudStack")
	var description_panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	check(_visible_content_children(container) == 1,
			"exactly one child is visible before any call", str(_visible_content_children(container)))
	check(hud_stack.visible, "the HUD is what shows by default")
	check(not description_panel.visible, "...and the description does not")
	container.queue_free()

func test_show_hud_shows_only_the_hud_stack() -> void:
	var container := _build_container()
	container.show_description(InfoEntry.new())
	container.show_hud()
	var hud_stack : Control = container.get_node(^"%HudStack")
	var description_panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	check(_visible_content_children(container) == 1,
			"exactly one child is visible after show_hud()", str(_visible_content_children(container)))
	check(hud_stack.visible, "...and it is HudStack")
	check(not description_panel.visible, "...and DescriptionPanel is hidden")
	container.queue_free()

func test_show_description_shows_only_the_description_panel() -> void:
	var container := _build_container()
	container.show_description(InfoEntry.new())
	var hud_stack : Control = container.get_node(^"%HudStack")
	var description_panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	check(_visible_content_children(container) == 1,
			"exactly one child is visible after show_description()",
			str(_visible_content_children(container)))
	check(description_panel.visible, "...and it is DescriptionPanel")
	check(not hud_stack.visible, "...and HudStack is hidden")
	container.queue_free()

# ------------------------------------------------------------------ fixtures (S2)

# Wall._ready() sets get_tree().paused = true GLOBALLY -- undone immediately, same reason every
# other Wall-building suite in this run already documents.
func _build_wall() -> Wall:
	var wall : Wall = WALL_SCENE.instantiate()
	add_child(wall)
	get_tree().paused = false
	return wall

# A real, headless show, parked/restored the same way `_stand_up_grids` (`Tests/UI/test_grid_view.gd`).
# `container` is hand-carried onto the view before it enters the tree, matching how
# `Main.enter_game()` binds a real wall's own `HudContainer` (no `Main` built here).
func _stand_up_view(host: Node, container: HudContainer) -> GameView:
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	view.hud_container = container
	host.add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	CardEnvironment.CURRENT = view.game
	return view

# Leaves the view IN MEMORY, so Godot's own drop-on-free auto-disconnect never fires -- only
# `_exit_tree()`'s explicit loop can be what discriminates a check on a dropped connection.
func _leave_tree_without_freeing(node: Node) -> void:
	remove_child(node)

func _tear_down_view(view: GameView, prev_run: RunState, prev_save_info: RunState) -> void:
	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

func _collect_unique_names(node: Node, owner: Node, out: Array[StringName]) -> void:
	for child : Node in node.get_children():
		if child.owner == owner and child.unique_name_in_owner:
			out.append(child.name)
		_collect_unique_names(child, owner, out)

func _has_named_descendant(node: Node, target: StringName) -> bool:
	if node.name == target: return true
	for child : Node in node.get_children():
		if _has_named_descendant(child, target): return true
	return false

# ------------------------------------------------------------------ the game screen's HUD members

# Read back through the real `wall.tscn`'s own `%Overlay/HudContainer`, never a standalone
# instance, so this fails if the wall stops mounting it.
func test_game_hud_holds_exactly_the_eight_members() -> void:
	var wall := _build_wall()
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var game_hud : Control = container.get_node(^"%GameHud")
	var names : Array[StringName] = []
	_collect_unique_names(game_hud, container, names)
	var expected : Array[StringName] = [
		&"Goal", &"Total", &"Combo", &"Deck", &"Discard", &"Rules", &"Undo", &"Submit"]
	names.sort()
	expected.sort()
	check(names == expected,
			"GameHud holds exactly Deck, Discard, Rules, Goal, Total, Combo, Undo, End (C4)",
			str(names))
	wall.free()

# Checked across BOTH `game_view.tscn` and `wall.tscn` -- the furniture migrated out of the view
# and into the container, so scanning only one would miss a retired node reintroduced in the other.
func test_no_retired_furniture_nodes_remain() -> void:
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	var wall : Wall = WALL_SCENE.instantiate()
	for target : StringName in ([&"MultScore", &"Preview"] as Array[StringName]):
		check(not _has_named_descendant(view, target) and not _has_named_descendant(wall, target),
				"no %%%s node exists anywhere under the game screen" % target)
	view.free()
	wall.free()

# The sidebar draws UNDER the Back/Forward/Wall buttons, which stay on top and stay pressable --
# read as sibling DRAW ORDER inside `%Overlay`, the way the engine decides it.
func test_overlay_buttons_draw_above_the_hud_container() -> void:
	var wall := _build_wall()
	var overlay : CanvasLayer = wall.get_node(^"%Overlay")
	var container : Node = overlay.get_node(^"HudContainer")
	var back_button : Control = overlay.get_node(^"%BackButton")
	var forward_button : Control = overlay.get_node(^"%ForwardButton")
	var wall_button : Control = overlay.get_node(^"%WallButton")
	check(container.get_index() < back_button.get_index()
			and container.get_index() < forward_button.get_index()
			and container.get_index() < wall_button.get_index(),
			"the container sits BEHIND the Back/Forward/Wall buttons in draw order",
			"container=%d back=%d forward=%d wall=%d" % [container.get_index(),
					back_button.get_index(), forward_button.get_index(), wall_button.get_index()])
	wall.free()

# ------------------------------------------------------------------ every control reachable

func _assert_visible_and_sized(control: Control, window_size: Vector2i, ctx: String) -> void:
	check(control.is_visible_in_tree(), "%s is visible" % ctx)
	check(control.size.x > 0.0 and control.size.y > 0.0, "%s has non-zero size" % ctx)
	var window_rect := Rect2(Vector2.ZERO, Vector2(window_size))
	check(window_rect.encloses(control.get_global_rect()),
			"%s's rect sits inside the window" % ctx, str(control.get_global_rect()))

# The five interactive members hit-test through a real mouse-motion event routed through the
# viewport, the way the engine decides hover. `Label`'s engine default is `MOUSE_FILTER_IGNORE`
# (no hover at all), so Goal/Total/Combo are proven reachable geometrically instead.
func test_every_hud_member_is_visible_and_reachable() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var wall : Wall = WALL_SCENE.instantiate()
	viewport.add_child(wall)
	get_tree().paused = false
	await get_tree().process_frame
	var overlay : CanvasLayer = wall.get_node(^"%Overlay")
	var container : HudContainer = overlay.get_node(^"HudContainer")

	var clickable : Dictionary = {
		"Deck": container.deck_ui.get_node(^"Button") as Control,
		"Discard": container.discard_ui.get_node(^"Button") as Control,
		"Rules": container.rules_ui.get_node(^"Button") as Control,
		"Undo": container.undo_button as Control,
		"Submit": container.submit_button as Control,
	}
	for ctx : String in clickable:
		var control : Control = clickable[ctx]
		_assert_visible_and_sized(control, viewport.size, ctx)
		var motion := InputEventMouseMotion.new()
		motion.position = control.get_global_rect().get_center()
		viewport.push_input(motion)
		await get_tree().process_frame
		check(viewport.gui_get_hovered_control() == control,
				"%s's rect centre hit-tests to itself" % ctx)

	## Forced visible purely to measure geometry -- Combo's own x1.0 hiding is tested elsewhere.
	container.combo_label.visible = true
	var readable : Dictionary = {
		"Goal": container.goal_label.get_parent() as Control,
		"Total": container.total_label.get_parent() as Control,
		"Combo": container.combo_label as Control,
	}
	for ctx : String in readable:
		_assert_visible_and_sized(readable[ctx] as Control, viewport.size, ctx)

	viewport.free()

# S2d: the caption and value halves of each number sat on top of each other before `Goal`/`Total`
# became `HBoxContainer`s, so a bare rect-intersection check proves the fix without re-reading
# pixels. A real `SubViewport` frame settles the containers' layout before the rects are read.
func test_number_captions_and_values_do_not_overlap() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var wall : Wall = WALL_SCENE.instantiate()
	viewport.add_child(wall)
	get_tree().paused = false
	await get_tree().process_frame
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	container.combo_label.visible = true
	await get_tree().process_frame
	var labels : Array[Control] = [
		container.goal_label.get_parent().get_node(^"Caption") as Control,
		container.goal_label,
		container.total_label.get_parent().get_node(^"Caption") as Control,
		container.total_label,
		container.combo_label,
	]
	for label : Control in labels:
		check(label.size.x > 0.0 and label.size.y > 0.0,
				"%s has non-zero size" % label.name, str(label.size))
	for i : int in labels.size():
		for j : int in range(i + 1, labels.size()):
			check(not labels[i].get_global_rect().intersects(labels[j].get_global_rect()),
					"%s and %s do not overlap" % [labels[i].get_parent().name, labels[j].get_parent().name])
	viewport.free()

# S2d/Q46: the HUD's CONTENT must start below the overlay's Back/Forward/Wall row -- the panel
# itself may still draw under it (draw order is `test_overlay_buttons_draw_above_the_hud_container`).
func test_game_hud_members_start_below_the_overlay_button_band() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var wall : Wall = WALL_SCENE.instantiate()
	viewport.add_child(wall)
	get_tree().paused = false
	await get_tree().process_frame
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var game_hud : Control = container.get_node(^"%GameHud")
	container.combo_label.visible = true
	await get_tree().process_frame
	var band_bottom := overlay.button_band_bottom()
	var names : Array[StringName] = []
	_collect_unique_names(game_hud, container, names)
	for member_name : StringName in names:
		var control : Control = container.get_node(NodePath("%" + member_name)) as Control
		check(control.get_global_rect().position.y >= band_bottom,
				"%s starts below the overlay button band" % member_name, str(control.get_global_rect()))
	viewport.free()

# A same-aspect window reports the project's own base resolution as its logical size under
# `canvas_items`/`expand` stretch -- what a real 1280x720 (16:9) window gives every Control,
# never the raw window pixels. Reading it here keeps the fixture honest about that difference.
func _project_base_window() -> Vector2:
	var w : float = ProjectSettings.get_setting("display/window/size/viewport_width", 1152)
	var h : float = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	return Vector2(w, h)

# Q76=b: the container's contents are laid out to fit whatever it is set to, so no member may
# reach past its own container's rect at a real 1280x720 window.
func test_game_hud_members_stay_inside_the_container_at_a_side_window() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(_project_base_window())
	add_child(viewport)
	var wall : Wall = WALL_SCENE.instantiate()
	viewport.add_child(wall)
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var game_hud : Control = container.get_node(^"%GameHud")
	container.combo_label.visible = true
	await get_tree().process_frame
	check(game_hud.get_combined_minimum_size().x <= container.size.x,
			"the HUD's minimum width never exceeds the container",
			"%.1f vs container %.1f" % [game_hud.get_combined_minimum_size().x, container.size.x])
	var container_rect := Rect2(container.global_position, container.size)
	var names : Array[StringName] = []
	_collect_unique_names(game_hud, container, names)
	for member_name : StringName in names:
		var control : Control = container.get_node(NodePath("%" + member_name)) as Control
		check(container_rect.encloses(control.get_global_rect()),
				"%s's rect sits inside the container" % member_name,
				"%s vs container %s" % [control.get_global_rect(), container_rect])
	_check_button_labels_fit_their_own_minimum(container)
	viewport.free()

# A Button's own TEXT overflows its rect silently (no layout error) once its assigned size is
# squeezed below what the label needs, so this checks each button's OWN minimum, not its
# wrapping Control's.
func _check_button_labels_fit_their_own_minimum(container : HudContainer) -> void:
	var buttons : Dictionary = {
		"Deck": container.deck_ui.get_node(^"Button") as Button,
		"Discard": container.discard_ui.get_node(^"Button") as Button,
		"Rules": container.rules_ui.get_node(^"Button") as Button,
		"Undo": container.undo_button,
		"Submit": container.submit_button,
	}
	for ctx : String in buttons:
		var button : Button = buttons[ctx]
		check(button.get_minimum_size().x <= button.size.x + 0.5,
				"%s's own label fits the space it was given" % ctx,
				"needs %.1f, has %.1f" % [button.get_minimum_size().x, button.size.x])

# ------------------------------------------------------------------ the wiring crosses from a
# per-show GameView to a container node that OUTLIVES it

# Presses the container's own End button via its `pressed` signal and asserts the LIVE
# `GameView`'s own game-side effect -- `end_show()` marking the state ended -- not a test flag.
func test_pressing_end_reaches_the_live_game_views_handler() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var wall := _build_wall()
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var view := await _stand_up_view(self, container)
	check(view.submit_button == container.submit_button,
			"sanity: the live view bound the shared container's own End button")
	check(not view.game.state.show_ended, "sanity: the show has not ended yet")

	container.submit_button.pressed.emit()
	await get_tree().process_frame

	check(view.game.state.show_ended,
			"pressing the container's End button reached the live GameView's own end_show()")
	await _tear_down_view(view, prev_run, prev_save_info)
	wall.free()

# The container OUTLIVES a per-show `GameView`: a first show's view tears down, its connections
# must be gone, and a second view alone receives the next press -- the SAME container, never a
# fresh one.
func test_a_second_shows_view_receives_the_press_after_the_first_tears_down() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var wall := _build_wall()
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")

	var view_one := await _stand_up_view(self, container)
	var connections : Array[Array] = container._screen_connections.duplicate()

	_leave_tree_without_freeing(view_one)
	for pair : Array in connections:
		var sig : Signal = pair[0] as Signal
		var callable : Callable = pair[1] as Callable
		check(not sig.is_connected(callable),
				"the first view's container connection is gone once it leaves the tree")

	container.submit_button.pressed.emit()
	await get_tree().process_frame
	check(not view_one.game.state.show_ended,
			"a press after the first view leaves the tree does not reach its handler")
	view_one.free()

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var view_two : GameView = GAME_VIEW_SCENE.instantiate()
	view_two.hud_container = container
	add_child(view_two)
	await get_tree().process_frame
	await get_tree().process_frame
	CardEnvironment.CURRENT = view_two.game
	check(not view_two.game.state.show_ended, "sanity: the second show's own state starts fresh")

	container.submit_button.pressed.emit()
	await get_tree().process_frame
	check(view_two.game.state.show_ended,
			"one press reaches exactly the second GameView after the first tore down")

	await _tear_down_view(view_two, prev_run, prev_save_info)
	wall.free()

# ------------------------------------------------------------------ scoped to its own wall

# A second, unrelated `Wall`'s `HudContainer` alive FIRST (the shape a concurrent suite's own
# wall takes in the real run) proves the GameView binds to ITS OWN wall's container, never
# whichever one happens to exist first.
func test_the_game_views_hud_container_is_scoped_to_its_own_wall() -> void:
	var other_wall := _build_wall()
	var other_container : HudContainer = other_wall.get_node(^"%Overlay/HudContainer")
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	get_tree().paused = false
	await main.enter_game()
	var game_wp : WallPicture = main._pictures[&"game"]
	var view := game_wp.screen_root as GameView
	CardEnvironment.CURRENT = view.game

	other_container.submit_button.pressed.emit()
	await get_tree().process_frame
	check(not view.game.state.show_ended,
			"a press on an unrelated container does not reach this wall's GameView")

	view.submit_button.pressed.emit()
	await get_tree().process_frame
	check(view.game.state.show_ended,
			"a press on this wall's own container reaches its GameView")

	main.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info
	other_wall.free()

# ------------------------------------------------------------------ the container's geometry

# Converts `rect_for_window`'s window-px container width to picture px through the focused
# picture's own live scale -- the same conversion `GameView._publish_board_inset()` uses.
func _inset_px(rect: Rect2, window: Vector2, settings_res: PlayerSettings) -> float:
	var design := Vector2(PlayArea.game_picture_design_size(settings_res))
	var picture_scale := maxf(window.x / design.x, window.y / design.y)
	return rect.size.x / picture_scale

## At the picture's own aspect the window cancels -- the inset is 394 px at any 16:9 window size.
func test_the_inset_is_394_at_the_pictures_own_aspect() -> void:
	var settings := PlayerSettings.new()
	for window : Vector2 in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(2560.0, 1440.0)]:
		var rect := HudContainer.rect_for_window(window, settings)
		var inset := _inset_px(rect, window, settings)
		check(absf(inset - 394.0) <= 0.5,
				"the inset is 394 px at %s" % window, "%.3f" % inset)

## An ultrawide window clamps the container, flush against the band's inner edge, empty space outboard.
func test_an_ultrawide_window_clamps_and_narrows() -> void:
	var settings := PlayerSettings.new()
	var window := Vector2(3840.0, 1080.0)
	var rect := HudContainer.rect_for_window(window, settings)
	var inset := _inset_px(rect, window, settings)
	check(absf(inset - 262.7) <= 0.5,
			"an ultrawide window clamps and narrows the inset", "%.3f" % inset)
	var inner_edge := settings.container_size_fraction * window.x
	check(is_equal_approx(rect.position.x + rect.size.x, inner_edge),
			"the container's right edge is flush against the band's inner edge")
	check(rect.position.x > 0.0,
			"the empty space from the clamp sits outboard of the container")

## The container moves to the top band once the leftover play area would be taller than wide.
func test_the_container_moves_to_the_top_when_the_leftover_would_be_taller_than_wide() -> void:
	var settings := PlayerSettings.new()
	var window := Vector2(600.0, 1000.0)
	check(HudContainer.container_is_top(window, settings),
			"a portrait window puts the container on the top band")
	var rect := HudContainer.rect_for_window(window, settings)
	check(is_equal_approx(rect.size.x, window.x),
			"the top container spans the window's full width", "%.3f vs %.3f" % [rect.size.x, window.x])
	check(rect.size.y > 0.0 and rect.size.y < window.y,
			"the top container's height is the fractional/clamped container_px", "%.3f" % rect.size.y)

# ------------------------------------------------------------------ the board's centre after S2

func _settle_scroll_x(pa: PlayArea) -> void:
	var last := INF
	var waited := 0.0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if is_equal_approx(pa.scroll_container.position.x, last): return
		last = pa.scroll_container.position.x

# `board_inset_left` was always `container_size_fraction * design`, independent of which furniture was
# widest, so deleting the retired controls does NOT re-centre the board. A real `Main`/
# `enter_game()` matches Part A's own measurement context: fixed design resolution, not the window.
func test_board_centre_after_hud_migration_matches_the_pre_deletion_measurement() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	get_tree().paused = false
	await main.enter_game()
	var game_wp : WallPicture = main._pictures[&"game"]
	var view := game_wp.screen_root as GameView
	CardEnvironment.CURRENT = view.game
	var pa := view.play_area
	pa.flush_rebuild()
	await _settle_scroll_x(pa)

	check(not _has_named_descendant(view, &"MultScore")
			and not _has_named_descendant(view, &"Preview"),
			"sanity: MultScore/Preview are really gone from this show")
	var centre := pa.scroll_container.position.x + pa.scroll_container.size.x * 0.5
	check(absf(centre - MEASURED_BOARD_CENTRE_PX) <= 0.5,
			"the board's centre is unchanged (within 0.5px) after the retired controls' removal",
			"%.3f vs %.3f" % [centre, MEASURED_BOARD_CENTRE_PX])

	main.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# ------------------------------------------------------------------ the geometry's own wiring

## A real resize (private `SubViewport`) moves the container and re-publishes `board_inset_left`.
func test_a_real_resize_moves_the_container_and_republishes_the_inset() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var main : Main = MAIN_SCENE.instantiate()
	viewport.add_child(main)
	get_tree().paused = false
	await main.enter_game()
	var game_wp : WallPicture = main._pictures[&"game"]
	var view := game_wp.screen_root as GameView
	CardEnvironment.CURRENT = view.game

	viewport.size = Vector2i(1920, 1080)
	await get_tree().process_frame
	await get_tree().process_frame

	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var window := Vector2(viewport.size)
	var expected_rect := HudContainer.rect_for_window(window, PlayArea.settings())
	check(Rect2(container.position, container.size).is_equal_approx(expected_rect),
			"the container's own rect follows a real resize",
			"%s vs %s" % [Rect2(container.position, container.size), expected_rect])
	var design := Vector2(PlayArea.game_picture_design_size(SettingsManager.settings))
	var picture_scale := maxf(window.x / design.x, window.y / design.y)
	check(absf(view.play_area.board_inset_left - expected_rect.size.x / picture_scale) <= 0.5,
			"board_inset_left is re-published for the new size")

	await _check_board_inset_left_on_ultrawide_resize(viewport, view, design)

	main.queue_free()
	await get_tree().process_frame
	viewport.queue_free()
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# An aspect off 16:9 is what tells `min` and `max` apart in `picture_scale`, unlike the earlier
# 1920x1080 resize, which shares the picture's own aspect where the two agree.
func _check_board_inset_left_on_ultrawide_resize(viewport : SubViewport, view : GameView, design : Vector2) -> void:
	viewport.size = Vector2i(3840, 1080)
	await get_tree().process_frame
	await get_tree().process_frame
	var ultrawide := Vector2(viewport.size)
	var ultrawide_rect := HudContainer.rect_for_window(ultrawide, PlayArea.settings())
	var ultrawide_scale := maxf(ultrawide.x / design.x, ultrawide.y / design.y)
	check(absf(view.play_area.board_inset_left - ultrawide_rect.size.x / ultrawide_scale) <= 0.5,
			"board_inset_left uses the covering picture_scale off an ultrawide resize",
			"%.3f vs %.3f" % [view.play_area.board_inset_left, ultrawide_rect.size.x / ultrawide_scale])

# The top case fits the board to the height LEFT UNDER the band, the same way the side case fits
# it to the width left beside the container -- a board sized off the whole height spills up under
# the band instead.
func test_a_top_case_resize_fits_the_board_under_the_band() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600, 1000)
	add_child(viewport)
	var main : Main = MAIN_SCENE.instantiate()
	viewport.add_child(main)
	get_tree().paused = false
	await main.enter_game()
	var game_wp : WallPicture = main._pictures[&"game"]
	var view := game_wp.screen_root as GameView
	CardEnvironment.CURRENT = view.game
	var pa := view.play_area
	await _settle_scroll_x(pa)
	check(view.game.state.grids.size() > 0,
			"a fresh show deals at least one grid for the Entrance to sit beside")

	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var window := Vector2(viewport.size)
	check(HudContainer.container_is_top(window, PlayArea.settings()),
			"sanity: this window puts the container on the top band")
	var band := container.container_rect()
	var design := Vector2(PlayArea.game_picture_design_size(SettingsManager.settings))
	var picture_scale := maxf(window.x / design.x, window.y / design.y)
	check(is_equal_approx(pa.board_inset_top, band.size.y / picture_scale),
			"board_inset_top equals the band's height converted to picture px",
			"%.3f vs %.3f" % [pa.board_inset_top, band.size.y / picture_scale])
	check(is_equal_approx(pa.board_inset_left, 0.0),
			"board_inset_left stays zero in the top case")

	var grid_rect := _sidebar_screen_rect(pa._cells_root(pa.grid_container.get_child(0) as Control))
	check(grid_rect.position.y >= band.end.y,
			"the grid's top edge sits below the band", "%s vs band bottom %.3f" % [grid_rect, band.end.y])
	var strip_rect := _sidebar_screen_rect(pa.upper_zone_right)
	check(strip_rect.position.y >= band.end.y,
			"the Entrance strip's top edge sits below the band",
			"%s vs band bottom %.3f" % [strip_rect, band.end.y])

	main.queue_free()
	await get_tree().process_frame
	viewport.queue_free()
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

## A control's rect as drawn -- carries every scale above it, since `global_position` alone drops the board's zoom.
func _sidebar_screen_rect(c: Control) -> Rect2:
	var t := c.get_global_transform()
	return Rect2(t.origin, t.get_scale() * c.size)

# ------------------------------------------------------------------ S4: the map's own container

# (a) `MapHud` holds exactly Fame, Lap, Luck, Deck, and none of them remain on `map.tscn`'s own
# `$UI` -- the second check reads the packed scene structurally, so it needs no `_ready()`.
func test_map_hud_holds_exactly_the_four_members_and_maps_own_ui_is_empty_of_them() -> void:
	var wall := _build_wall()
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var map_hud : Control = container.get_node(^"%MapHud")
	var names : Array[StringName] = []
	_collect_unique_names(map_hud, container, names)
	var expected : Array[StringName] = [&"FameLabel", &"LapLabel", &"LuckLabel", &"MapDeckButton"]
	names.sort()
	expected.sort()
	check(names == expected, "MapHud holds exactly Fame, Lap, Luck, Deck (C13)", str(names))
	var map := MAP_SCENE.instantiate()
	for target : StringName in ([&"FameLabel", &"LapLabel", &"LuckLabel", &"DeckButton"] as Array[StringName]):
		check(not _has_named_descendant(map, target),
				"no %%%s node remains under map.tscn's own $UI" % target)
	map.free()
	wall.free()

## (b) The real focus change drives which `HudStack` child shows, for all four screens.
func test_focus_change_drives_which_hud_stack_child_shows() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var main : Main = MAIN_SCENE.instantiate()
	add_child(main)
	get_tree().paused = false
	await get_tree().process_frame
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var game_hud : Control = container.get_node(^"%GameHud")
	var map_hud : Control = container.get_node(^"%MapHud")

	check(container.visible, "start menu: the container itself is visible (Q22=b)")
	check(not game_hud.visible and not map_hud.visible,
			"start menu: neither GameHud nor MapHud shows")

	main.map_scene.start_run(run)
	await main._focus_picture(&"map")
	check(container.visible, "map: the container is visible")
	check(map_hud.visible and not game_hud.visible, "map: MapHud shows, GameHud hidden")

	await main.enter_game()
	check(container.visible, "game: the container is visible")
	check(game_hud.visible and not map_hud.visible, "game: GameHud shows, MapHud hidden")
	CardEnvironment.CURRENT = (main._pictures[&"game"].screen_root as GameView).game

	await main._go_to_wall_view()
	check(not container.visible, "wall overview: no container at all (Q21=b)")

	main.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# (c) The container's Deck button reaches the live map's own handler, and the connection is gone
# once the map leaves the tree -- `remove_child` first, so free-time auto-disconnect cannot mask it.
func test_map_deck_button_reaches_the_live_maps_handler_then_disconnects() -> void:
	var wall := _build_wall()
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var map := MAP_SCENE.instantiate() as Map
	map.hud_container = container
	add_child(map)
	await get_tree().process_frame
	check(container.map_deck_button.pressed.is_connected(map._on_deck_clicked),
			"the container's Deck button reaches the live map's own handler")
	var connections : Array[Array] = container._screen_connections.duplicate()
	_leave_tree_without_freeing(map)
	for pair : Array in connections:
		var sig : Signal = pair[0] as Signal
		var callable : Callable = pair[1] as Callable
		check(not sig.is_connected(callable),
				"the map's container connection is gone once it leaves the tree")
	map.free()
	wall.free()

# Camera2D recomputes its own cached canvas transform on the idle frames AFTER `offset` is
# assigned, never the same one -- two extra frames is what it measures as settled here.
func _await_camera_transform_settled() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

# (d) The map's token (the camera follows it) renders at the centre of the space left over beside
# `container_rect()`, converted through the map's own `WallPicture` cover scale and `Camera2D`
# zoom, never window px unconverted. Boots the real `Main`: a side window, a top window, a zoom.
func test_maps_camera_offset_moves_beside_the_container_not_under_it() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	for size : Vector2i in ([Vector2i(1280, 720), Vector2i(600, 1000)] as Array[Vector2i]):
		var booted := await _boot_main_at(size)
		var viewport : SubViewport = booted[0]
		var main : Main = booted[1]
		await _focus_map(main, run)
		_check_map_token_centred(main, str(size))
		await _free_booted_main(viewport, main)

	var zoom_booted := await _boot_main_at(Vector2i(1280, 720))
	var zoom_viewport : SubViewport = zoom_booted[0]
	var zoom_main : Main = zoom_booted[1]
	await _focus_map(zoom_main, run)
	for _i in range(5):
		zoom_main.wall._unhandled_input(_wheel_event())
	await _await_camera_transform_settled()
	check(zoom_main.map_scene.controller.camera.zoom.x > 1.9,
			"5 real wheel-up notches zoom the map to ~2x",
			"%.3f" % zoom_main.map_scene.controller.camera.zoom.x)
	_check_map_token_centred(zoom_main, "1280x720 after zooming to ~2x")
	await _free_booted_main(zoom_viewport, zoom_main)

	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# Focuses the map with `run`, waiting for both its generation and the settled camera transform
# `Camera2D` needs before its offset/zoom read back correctly.
func _focus_map(main: Main, run: RunState) -> void:
	main.map_scene.start_run(run)
	await main._focus_picture(&"map")
	if not main.map_scene.controller.is_generated():
		await main.map_scene.controller.map_ready
	await _await_camera_transform_settled()

# The map's token renders at the centre of the space left over beside the container, measured in
# the map's OWN `WallPicture` local space -- `local_rect_beside()` converts the container's window
# px into that same space, the one owned conversion, so both sides of the check share it.
func _check_map_token_centred(main: Main, label: String) -> void:
	var wp : WallPicture = main._pictures[&"map"]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var window : Vector2 = container.get_viewport().get_visible_rect().size
	var rect := container.container_rect()
	var top := HudContainer.container_is_top(window, SettingsManager.settings)
	var expected := wp.local_rect_beside(window, rect, top).get_center()
	var token_local : Vector2 = wp.viewport.get_canvas_transform() \
			* main.map_scene.controller.token.position
	check(token_local.distance_to(expected) <= 2.0,
			"the map's token centres in the space left over beside the container at %s" % label,
			"%s vs %s" % [token_local, expected])

func _wheel_event() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	return event

const _MENU_BUTTON_NAMES : Array[StringName] = [
	&"Profile", &"Play", &"Options", &"Quit", &"Collection", &"Language",
]

# Both a portrait (top-case) and an ultrawide (side-case) window, plus the project's own 16:9
# target where the menu's picture and the window coincide 1:1 (`picture_scale` 1.0, no crop).
const _MENU_TEST_WINDOW_SIZES : Array[Vector2i] = [
	Vector2i(600, 1000), Vector2i(1920, 1200), Vector2i(1280, 720),
]

func _menu_buttons(main_menu: Menu) -> Array[Button]:
	var buttons : Array[Button] = []
	for button_name : StringName in _MENU_BUTTON_NAMES:
		buttons.append(main_menu.get_node(NodePath("Main/%s" % button_name)) as Button)
	return buttons

# Boots a real `Main` inside a `SubViewport` sized to `size`; returns `[viewport, main]` so the
# caller can free both once its own checks are done.
func _boot_main_at(size: Vector2i) -> Array:
	var viewport := SubViewport.new()
	viewport.size = size
	add_child(viewport)
	var main : Main = MAIN_SCENE.instantiate()
	viewport.add_child(main)
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	return [viewport, main]

func _free_booted_main(viewport: SubViewport, main: Main) -> void:
	main.queue_free()
	await get_tree().process_frame
	viewport.queue_free()

# (e) The start menu's buttons lie outside the reserved container band and inside the window, at
# every window shape -- compared in ONE space (this menu's own picture space) via the single owned
# conversion, `WallPicture.local_rect_beside()`, rather than mixing picture px with window px.
func test_menus_buttons_lie_outside_the_container_and_inside_the_window() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	for size : Vector2i in _MENU_TEST_WINDOW_SIZES:
		var booted := await _boot_main_at(size)
		var viewport : SubViewport = booted[0]
		var main : Main = booted[1]
		var wp : WallPicture = main._pictures[&"start_menu"]
		var container : HudContainer = main.wall.get_node(^"%HudContainer")
		var window : Vector2 = container.get_viewport().get_visible_rect().size
		var band_screen : Rect2 = container.container_rect()
		var top := HudContainer.container_is_top(window, SettingsManager.settings)
		var window_local := wp.local_rect_beside(window, Rect2(), top)
		var remaining := wp.local_rect_beside(window, band_screen, top)
		var band_local := Rect2(window_local.position.x, window_local.position.y,
					window_local.size.x, window_local.size.y - remaining.size.y) if top \
				else Rect2(window_local.position.x, window_local.position.y,
					window_local.size.x - remaining.size.x, window_local.size.y)
		for button : Button in _menu_buttons(main.menu_scene):
			var button_rect := button.get_global_rect()
			check(not button_rect.intersects(band_local),
					"%s lies outside the reserved container band at %s" % [button.name, size],
					str(button_rect))
			check(window_local.encloses(button_rect),
					"%s lies inside the window at %s" % [button.name, size], str(button_rect))
		await _free_booted_main(viewport, main)
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# Any inset scale is UNIFORM (one factor on both axes): a button never stretches or squashes
# relative to its own authored shape, so its lettering is never condensed.
func test_menus_scale_is_uniform_and_keeps_each_buttons_authored_aspect() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var main : Main = MAIN_SCENE.instantiate()
	viewport.add_child(main)
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	var main_menu : Menu = main.menu_scene
	var authored_menu : Menu = MENU_SCENE.instantiate()
	for button_name : StringName in _MENU_BUTTON_NAMES:
		var live := main_menu.get_node(NodePath("Main/%s" % button_name)) as Button
		var authored := authored_menu.get_node(NodePath("Main/%s" % button_name)) as Button
		var authored_aspect := authored.size.aspect()
		var live_aspect := live.get_global_rect().size.aspect()
		check(is_equal_approx(live_aspect, authored_aspect) \
					or absf(live_aspect - authored_aspect) <= 0.01 * authored_aspect,
				"%s keeps its authored aspect (uniform scale)" % button_name,
				"authored %.4f live %.4f" % [authored_aspect, live_aspect])
	authored_menu.free()
	main.queue_free()
	await get_tree().process_frame
	viewport.queue_free()
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# Q27: the picture is centred in the space beside the container, not merely inset from one edge --
# the title moves with the rest of the menu. The container narrows one axis (x on the side case, y
# on the top case); that is the only axis its centring is testable on, so that is the one checked.
func test_menus_title_and_button_row_centre_on_the_remaining_space() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	for size : Vector2i in _MENU_TEST_WINDOW_SIZES:
		var booted := await _boot_main_at(size)
		var viewport : SubViewport = booted[0]
		var main : Main = booted[1]
		var wp : WallPicture = main._pictures[&"start_menu"]
		var container : HudContainer = main.wall.get_node(^"%HudContainer")
		var window : Vector2 = container.get_viewport().get_visible_rect().size
		var band : Rect2 = container.container_rect()
		var top := HudContainer.container_is_top(window, SettingsManager.settings)
		var remaining := wp.local_rect_beside(window, band, top)
		var remaining_centre := remaining.get_center()
		var main_menu : Menu = main.menu_scene
		var title : Label = main_menu.get_node(^"Label")
		var buttons := _menu_buttons(main_menu)
		var content := title.get_global_rect()
		for button : Button in buttons: content = content.merge(button.get_global_rect())
		var content_centre := content.get_center()
		var axis := content_centre.y if top else content_centre.x
		var expected := remaining_centre.y if top else remaining_centre.x
		check(absf(axis - expected) <= 2.0,
				"the menu's content centres on the remaining space at %s" % size,
				"%.2f vs %.2f" % [axis, expected])
		await _free_booted_main(viewport, main)
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info


# ------------------------------------------------------------------ S5: publish and show

# The deal spawns its card controls a frame behind `enter_game()`, so the board is waited FOR
# rather than slept on. Bounded: a real hang is a bug to surface, not one to spin on.
const CARD_CONTROL_TIMEOUT_SEC := 5.0

var _prev_run : RunState = null
var _prev_save_info : RunState = null
## The live fixture the S5 tests share, so four tests do not each re-derive the same five nodes.
var _main : Main = null
var _container : HudContainer = null
var _panel : DescriptionPanel = null
var _play_area : PlayArea = null
var _game_viewport : SubViewport = null
var _booted_viewport : SubViewport = null

# A real `Main` on a dealt game screen: the only fixture that proves the WHOLE route -- the board's
# focus, `GameView`'s relay, `Main`'s handler and the container's swap -- with nothing stubbed.
func _start_game_fixture() -> void:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var booted := await _boot_main_at(Vector2i(1280, 720))
	_booted_viewport = booted[0]
	_main = booted[1]
	await _focus_map(_main, run)
	await _main.enter_game()
	var view := _main._pictures[&"game"].screen_root as GameView
	CardEnvironment.CURRENT = view.game
	_play_area = view.play_area
	_game_viewport = _main._pictures[&"game"].viewport
	_container = _main.wall.get_node(^"%HudContainer")
	_panel = _container.get_node(^"%DescriptionPanel")

func _end_game_fixture() -> void:
	await _free_booted_main(_booted_viewport, _main)
	_booted_viewport = null
	_main = null
	_container = null
	_panel = null
	_play_area = null
	_game_viewport = null
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = _prev_run
	Main.save_info = _prev_save_info

# Card controls the pointer can genuinely land ON: alive, on screen, wholly inside the game
# picture's own viewport (the space a board control's global rect is measured in), and with a
# centre no other control covers -- board cards overlap in a stack, so the two must be distinct.
func _hoverable_card_controls() -> Array[Control]:
	var rect := Rect2(Vector2.ZERO, Vector2(_game_viewport.size))
	var waited := 0.0
	var out : Array[Control] = []
	while waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
		_play_area.flush_rebuild()
		var every : Array[Control] = []
		for control : Control in _play_area.ui_data:
			if is_instance_valid(control): every.append(control)
		out.clear()
		for control : Control in every:
			if not control.is_visible_in_tree(): continue
			if rect.encloses(control.get_global_rect()) and not _is_covered(control, every):
				out.append(control)
		if out.size() >= 2: break
	return out

func _is_covered(control: Control, others: Array[Control]) -> bool:
	var centre := control.get_global_rect().get_center()
	for other : Control in others:
		if other != control and other.get_global_rect().has_point(centre): return true
	return false

# A REAL pointer, pushed into the game picture's own SubViewport where the board's controls live,
# so the route under test is the product's own: mouse_entered grabs focus, and focus publishes.
func _hover(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	_game_viewport.push_input(motion)

# The pointer is walked across the candidates until the BOARD ITSELF reports a different card
# under it. Which control a point hits is the engine's answer, not the test's: cards overlap in a
# stack and the strips clip, so a rect's own centre is not always hit-testable.
func _hover_another_card(controls: Array[Control], avoid: Control) -> Control:
	for control : Control in controls:
		if control == avoid: continue
		_hover(control.get_global_rect().get_center())
		await get_tree().process_frame
		var hovered : Control = _play_area.moused_hovered_control
		if hovered != null and hovered != avoid and _play_area.ui_data.has(hovered):
			return hovered
	return null

## Off the picture entirely: no control can be under the pointer there, whatever a re-lay-out moves.
func _off_the_board_point() -> Vector2:
	return Vector2(-100.0, -100.0)

# Bare board: a point belonging to no card control, so the pointer leaving everything is a real
# mouse exit rather than the test merely declining to publish.
func _bare_board_point(controls: Array[Control]) -> Vector2:
	var board := Vector2(_game_viewport.size)
	for step : int in 20:
		var candidate := Vector2(board.x - 4.0, 4.0 + step * board.y / 20.0)
		var covered := false
		for control : Control in controls:
			if control.get_global_rect().has_point(candidate): covered = true
		if not covered: return candidate
	return Vector2(board.x - 4.0, 4.0)

# The text the board publishes for a card, split the way `PlayArea.card_info()` splits it: the
# first line is the card's name, the rest is its description.
func _expected_text(data: CardData) -> PackedStringArray:
	return ControlCard.describe_card(data).split("\n", false, 1)

func _preview_card(node: Node) -> ControlCard:
	var card := node as ControlCard
	if card: return card
	for child : Node in node.get_children():
		var found := _preview_card(child)
		if found: return found
	return null

## 1.2/B1/B2: a highlight -- key/pad focus or a real mouse hover -- swaps the container to that card's description.
func test_a_highlight_opens_the_description() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var title : Label = _panel.get_node(^"%Title")
	var body : Label = _panel.get_node(^"%Body")
	var slot : Control = _panel.get_node(^"%VisualSlot")

	var spelled := InfoEntry.new()
	spelled.title = "A"
	spelled.body = "B"
	_container.show_description(spelled)
	check(_panel.visible and not hud_stack.visible,
			"the description replaces the HUD, never both and never neither (B2)")
	check(title.text == "A", "...and the title reads the entry's name", title.text)
	check(body.text == "B", "...and the body reads its description", body.text)

	var controls := await _hoverable_card_controls()
	check(controls.size() >= 2, "the dealt board offers two reachable card controls",
			str(controls.size()))
	if controls.size() >= 2:
		_container.show_hud()
		controls[0].grab_focus()
		await get_tree().process_frame
		check(_panel.visible and not hud_stack.visible,
				"key/pad selection onto a card opens the description (B1)")
		check(title.text == _expected_text(_play_area.ui_data[controls[0]])[0],
				"...and the title reads that card's own name", title.text)
		check(not body.text.is_empty(), "...and the body carries its description", body.text)
		var overlay : WallOverlay = _main.wall.get_node(^"%Overlay")
		check(title.get_global_rect().position.y >= overlay.button_band_bottom(),
				"the name starts below the overlay's own button row, as the HUD does (Q46)",
				"%.1f vs %.1f" % [title.get_global_rect().position.y, overlay.button_band_bottom()])
		var entry : InfoEntry = _panel.current_entry
		check(entry != null and entry.visual != null and entry.visual.get_parent() == slot,
				"the card's own visual is mounted in the panel (Q33=c)")
		if entry != null and entry.visual != null:
			var preview := _preview_card(entry.visual)
			check(preview != null and preview.child != null, "...and it is a real preview card")
			if preview != null and preview.child != null:
				check(not preview.child.floating, "...frozen rather than idling (Q35=b)")
				check(preview.focus_mode == Control.FOCUS_NONE
						and preview.mouse_filter == Control.MOUSE_FILTER_IGNORE,
						"...and inert: it takes no pad focus and swallows no click")
		var hovered := await _hover_another_card(controls, controls[0])
		check(hovered != null, "the pointer can land on a card other than the pad's own")
		check(_panel.visible and not hud_stack.visible,
				"a real mouse hover opens it by the same rule as the pad (B1)")
		if hovered != null:
			check(title.text == _expected_text(_play_area.ui_data[hovered])[0],
					"...and the title follows the card the pointer is on", title.text)
	await _end_game_fixture()

## How near the preview's drawn width must land on the board card's own -- a pixel of layout rounding on each side.
const PREVIEW_WIDTH_TOLERANCE_PX := 2.0

# What a card ACTUALLY DRAWS AT, not the box it was allocated: every scale above it, times its own
# face. The two differ -- `CardVisual._ready()` re-runs `recalculate_size()`, so a card can sit in a
# correctly sized slot drawing at the wrong size, which is exactly the defect this test exists for.
func _card_drawn_width(card: CardVisual) -> float:
	return CardVisual.CARD_SIZE.x * card.get_global_transform_with_canvas().get_scale().x

# A board card's width as the player SEES it: its drawn width inside the game picture's viewport,
# times the scale the wall draws that viewport at. Read off the picture's own screen sprite, so the
# live camera zoom is already in it rather than modelled a second time here.
func _board_card_window_width(card: CardVisual) -> float:
	var picture : WallPicture = _main._pictures[&"game"]
	var sprite : Sprite2D = picture.get_node(^"%Screen")
	var design := Vector2(PlayArea.game_picture_design_size(PlayArea.settings()))
	var texel := float(picture.viewport.size.x) / design.x
	return _card_drawn_width(card) * texel * sprite.get_global_transform_with_canvas().get_scale().x

## Q34=b/Q33=c: the description's card is drawn at the size that same card has on the board, with the name beside it.
func test_the_preview_is_drawn_at_the_boards_own_card_size() -> void:
	await _start_game_fixture()
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		var hovered := await _hover_another_card(controls, null)
		check(hovered != null, "the pointer landed on a board card")
		if hovered != null and _play_area.data_card.has(_play_area.ui_data[hovered]):
			await get_tree().process_frame
			var board_card : CardVisual = _play_area.data_card[_play_area.ui_data[hovered]]
			var board_px := _board_card_window_width(board_card)
			var preview := _preview_card(_panel.current_entry.visual)
			check(preview != null, "the description mounted a preview card")
			if preview != null and preview.child != null:
				var preview_px := _card_drawn_width(preview.child)
				var preview_rect := _sidebar_screen_rect(preview)
				check(absf(preview_px - board_px) <= PREVIEW_WIDTH_TOLERANCE_PX,
						"the preview is drawn at the board card's own screen width (Q34=b)",
						"preview %.1f px vs board %.1f px at board zoom %.3f"
						% [preview_px, board_px, _play_area.board_zoom])
				check(absf(preview_rect.size.x - preview_px) <= PREVIEW_WIDTH_TOLERANCE_PX,
						"...and the slot it was given is that same width, so the name clears it",
						"slot %.1f px vs card %.1f px" % [preview_rect.size.x, preview_px])
				var title_rect := _sidebar_screen_rect(_panel.get_node(^"%Title") as Label)
				check(title_rect.position.x >= preview_rect.end.x - PREVIEW_WIDTH_TOLERANCE_PX,
						"the name starts to the RIGHT of the visual (Q33=c)",
						"name at %.1f vs visual ending %.1f"
						% [title_rect.position.x, preview_rect.end.x])
				check(title_rect.position.y < preview_rect.end.y
						and title_rect.end.y > preview_rect.position.y,
						"...and beside it, not under it (Q33=c)",
						"name %s vs visual %s" % [title_rect, preview_rect])
	await _end_game_fixture()

## 1.3/B4/Q32=a: the pointer leaving every card publishes nothing, so the description keeps its last entry.
func test_losing_the_highlight_keeps_the_last_entry() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var title : Label = _panel.get_node(^"%Title")
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		var shown : InfoEntry = _panel.current_entry
		check(shown != null, "hovering a card opened the description")
		_hover(_bare_board_point(controls))
		await get_tree().process_frame
		await get_tree().process_frame
		check(_panel.visible and not hud_stack.visible,
				"the description STAYS when the pointer leaves every card (B4)")
		check(shown != null and _panel.current_entry == shown,
				"...still the very same entry, by identity (Q32=a)")
		check(title.text == _expected_text(_play_area.ui_data[controls[0]])[0],
				"...still reading the card the pointer left", title.text)
	await _end_game_fixture()

## 1.14/B15/B16/Q19=c/Q20=b: each screen remembers its own last description and gets it back on return.
func test_leaving_and_returning_restores_the_screens_own_description() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var slot : Control = _panel.get_node(^"%VisualSlot")
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		var shown : InfoEntry = _panel.current_entry
		check(shown != null, "the game screen has a description to remember")

		await _main._focus_picture(&"map")
		check(hud_stack.visible and not _panel.visible,
				"the map has read nothing of its own, so it shows its own HUD (B15)")

		await _main._focus_picture(&"game")
		check(_panel.visible and not hud_stack.visible,
				"coming back re-shows the game's description immediately (B16, Q20=b)")
		check(shown != null and _panel.current_entry == shown,
				"...and it is the very entry that screen was left on (Q19=c)")
		check(shown != null and shown.visual != null and shown.visual.get_parent() == slot,
				"...with its own visual back in the panel")
	await _end_game_fixture()

## The panel OWNS the mounted visual: the next entry frees the last, so reading along a row of cards leaks no preview.
func test_a_new_entry_frees_the_visual_it_replaces() -> void:
	await _start_game_fixture()
	var slot : Control = _panel.get_node(^"%VisualSlot")
	var controls := await _hoverable_card_controls()
	check(controls.size() >= 2, "the dealt board offers two reachable card controls",
			str(controls.size()))
	if controls.size() >= 2:
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		var shown_on : Control = _play_area.moused_hovered_control
		var first : Node = _panel.current_entry.visual if _panel.current_entry else null
		check(first != null, "the first hover mounted a visual")
		var hovered := await _hover_another_card(controls, shown_on)
		await get_tree().process_frame
		check(hovered != null, "the pointer moved onto a different card")
		check(not is_instance_valid(first),
				"the replaced entry's visual is freed, not orphaned",
				"%d visual(s) left in the slot" % slot.get_child_count())
		check(_panel.current_entry != null and _panel.current_entry.visual != first,
				"...and the panel shows the next card's own visual")
	await _end_game_fixture()

# ------------------------------------------------------------------ S6: the lock and the exit X

# A real click, pushed where the hover already is: press and release at the same point, one frame
# apart, so `_on_gui_input` sees the hovered control still focused under the button.
func _click(at: Vector2, viewport: SubViewport) -> void:
	_push_mouse_button(at, viewport, true)
	await get_tree().process_frame
	_push_mouse_button(at, viewport, false)
	await get_tree().process_frame

func _push_mouse_button(at: Vector2, viewport: SubViewport, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	viewport.push_input(event)

# Entrance cards are the ones a click can GRAB, so Q56's "the click still performs its game action"
# is only testable on those -- a grid card's click has no pickup to prove.
func _entrance_card_controls() -> Array[Control]:
	var out : Array[Control] = []
	for control : Control in await _hoverable_card_controls():
		if _play_area.upper_zone_right.is_ancestor_of(control) and _is_selectable(control):
			out.append(control)
	return out

# A slot's own zone control sits in `ui_data` but is left FOCUS_NONE and zero-height once a card
# covers it (`_size_stack_slot`), so neither a click nor a key can land on it.
func _is_selectable(control: Control) -> bool:
	return control.focus_mode != Control.FOCUS_NONE

# Clicks a board card the way a player does -- hover first (the board selects what the pointer is
# on), then press and release -- and waits out `try_grab`'s own await.
func _click_card(control: Control) -> void:
	_hover(control.get_global_rect().get_center())
	await get_tree().process_frame
	_hover(control.get_global_rect().get_center())
	await get_tree().process_frame
	await _click(control.get_global_rect().get_center(), _game_viewport)
	await get_tree().process_frame
	await get_tree().process_frame

# WHICH CARD A CLICK LANDED ON IS THE BOARD'S OWN ANSWER: a grab rebuilds the board and the slot
# controls are POOLED, so a mapping read either side of the click can name a different card.
func _watch_clicks() -> Array[CardData]:
	var clicked : Array[CardData] = []
	_play_area.data_selected.connect(func(data: CardData) -> void: clicked.append(data))
	return clicked

# Why an input did not land: every state that decides whether the board acts on one, in the order
# `_on_gui_input` and `grab_focus()` consult them.
func _board_input_state(control: Control) -> String:
	var game := CardEnvironment.get_current_game()
	return ("processing %s, paused %s, held %d, in ui_data %s, visible %s, focus_mode %d, "
			+ "hovered %s, focused %s, owner %s") % [
			game.processing, get_tree().paused, _play_area.selected_cards.size(),
			_play_area.ui_data.has(control), control.is_visible_in_tree(), control.focus_mode,
			_play_area.moused_hovered_control == control, _play_area.focused_control == control,
			control.get_viewport().gui_get_focus_owner()]

func _exit_button() -> Button:
	return _container.get_node(^"%ExitX") as Button

## A hoverable card control whose card is not `avoid`, so the board focus can be moved off it.
func _another_card_control(controls: Array[Control], avoid: CardData) -> Control:
	for control : Control in controls:
		if _play_area.ui_data[control] != avoid and _is_selectable(control): return control
	return null

## Q56=a/Q57=a/B5: one click both grabs the card and locks the sidebar to it -- there is no inspect-only mode.
func test_a_click_grabs_the_card_and_locks_its_description() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var clicked := _watch_clicks()
		await _click_card(entrance[0])
		check(clicked.size() == 1, "the click reached the board's own selection",
				str(clicked.size()))
		check(not _play_area.selected_cards.is_empty(),
				"the click still performs its game action: the card is grabbed (Q57=a)",
				str(_play_area.selected_cards.size()))
		check(_container.is_locked(), "...and the same click locks the description (B5, Q56=a)")
		if clicked.size() == 1:
			check(_play_area.locked_data == clicked[0], "...to the card that was clicked")
			var title : Label = _panel.get_node(^"%Title")
			check(title.text == _expected_text(clicked[0])[0],
					"...and the sidebar shows that card's own name", title.text)
	await _end_game_fixture()

## 1.6/B8/Q61=a: only one lock exists, so locking a second card replaces the first.
func test_locking_a_second_card_replaces_the_first() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(entrance.size() >= 2, "the dealt board offers two clickable Entrance cards",
			str(entrance.size()))
	if entrance.size() >= 2:
		var clicked := _watch_clicks()
		var first : CardData = _play_area.ui_data[entrance[0]]
		await _click_card(entrance[0])
		check(_play_area.locked_data == first, "the first click locked the first card")
		_play_area.ungrab_cards()
		var next_control := _another_card_control(await _entrance_card_controls(), first)
		check(next_control != null, "a second Entrance card is reachable for the next click")
		if next_control != null:
			await _click_card(next_control)
			check(clicked.size() == 2, "both clicks reached the board", _board_input_state(next_control))
			check(_container.is_locked(), "the second click leaves the sidebar locked")
			if clicked.size() == 2:
				check(clicked[1] != clicked[0], "the two clicks landed on different cards")
				check(_play_area.locked_data == clicked[1],
						"...to the SECOND card: locking a second replaces the first (B8)")
				_hover(_bare_board_point(entrance))
				await get_tree().process_frame
				check(_container.is_locked() and _play_area.locked_data == clicked[1],
						"...and leaving every card keeps that same lock")
				var title : Label = _panel.get_node(^"%Title")
				check(title.text == _expected_text(clicked[1])[0],
						"...with the second card's own description showing", title.text)
	await _end_game_fixture()

## Q58=c: the locked card keeps the marking a focused card gets, even once the focus has moved on.
func test_the_locked_card_keeps_its_marking_while_focus_moves_on() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the board offers a lockable card", str(entrance.size()))
	if not entrance.is_empty():
		var locked : CardData = _play_area.ui_data[entrance[0]]
		await _click_card(entrance[0])
		var others := await _hoverable_card_controls()
		_hover(_off_the_board_point())
		await get_tree().process_frame
		var elsewhere := _another_card_control(others, locked)
		check(elsewhere != null, "a second card can take the focus")
		if elsewhere != null:
			elsewhere.grab_focus()
			await get_tree().process_frame
			await get_tree().process_frame
			var moved : CardData = _play_area.ui_data[_play_area.focused_control]
			check(_play_area.focused_control == elsewhere,
					"the key/pad focus landed on that second card",
					_board_input_state(elsewhere))
			var title : Label = _panel.get_node(^"%Title")
			check(title.text == _expected_text(moved)[0],
					"the description follows the new highlight (B1)", title.text)
			check(_play_area.data_card[locked].focused,
					"...and the LOCKED card keeps the focus marking behind it (Q58=c)")
			check(_play_area.data_card[moved].focused,
					"...while the newly focused card is marked as well")
	await _end_game_fixture()

## 1.13/B13/Q65=a: a board rebuild keeps the same CardData's description and its marking, whichever control now represents it.
func test_a_board_rebuild_keeps_the_same_cards_description() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var data : CardData = _play_area.ui_data[entrance[0]]
		await _click_card(entrance[0])
		var title : Label = _panel.get_node(^"%Title")
		var before := _play_area.locked_data
		_play_area.queue_rebuild()
		await get_tree().process_frame
		_play_area.flush_rebuild()
		await get_tree().process_frame
		check(_container.is_locked() and _play_area.locked_data == data,
				"the lock survives a board rebuild")
		check(_play_area.locked_data == before and title.text == _expected_text(data)[0],
				"...and the sidebar still shows that same card's description", title.text)
		check(_play_area.data_ui.has(data), "...the card has a control again after the rebuild")
		check(_play_area.data_card.has(data) and _play_area.data_card[data].focused,
				"...and the marking is on whichever visual now represents it (B13)")
	await _end_game_fixture()

## 1.7/C16/Q179=a/Q180=a: pressing the exit X reverts the container to the HUD and drops the lock.
func test_the_exit_x_reverts_to_the_hud() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _click_card(entrance[0])
		var dismissals : Array[int] = []
		_container.description_dismissed.connect(func() -> void: dismissals.append(1))
		var hud_stack : Control = _container.get_node(^"%HudStack")
		check(not hud_stack.visible and _container.is_locked(),
				"the description is up and locked before the press")
		await _click(_exit_button().get_global_rect().get_center(), _booted_viewport)
		check(hud_stack.visible and not _panel.visible,
				"the exit X reverts the container to the HUD (B10, Q179=a)")
		check(not _container.is_locked(), "...and the lock is gone (B10)")
		check(dismissals.size() == 1, "...announced exactly once", str(dismissals.size()))
		check(_play_area.locked_data == null, "...so the board drops the locked card's marking")
	await _end_game_fixture()

## C16/Q47=a: the exit X is a full touch target in the container's top-right, below the overlay's own button band, and only while the description shows.
func test_the_exit_x_is_a_touch_target_below_the_button_band() -> void:
	await _start_game_fixture()
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		var button := _exit_button()
		var target := WallInput.touch_target_px(DisplayServer.screen_get_dpi(),
				PlayArea.settings())
		check(button.is_visible_in_tree(), "the exit X shows while the description does")
		check(button.size.x >= target - 0.5 and button.size.y >= target - 0.5,
				"...at the same touch target every overlay control is grown to (Q47=a)",
				"%s vs %.1f" % [button.size, target])
		var rect := button.get_global_rect()
		var bounds := _container.container_rect()
		check(bounds.encloses(rect), "...inside the container's own rect",
				"%s vs %s" % [rect, bounds])
		var overlay : WallOverlay = _main.wall.get_node(^"%Overlay")
		check(rect.position.y >= overlay.button_band_bottom(),
				"...below the overlay's button band, never under it (D12)",
				"%.1f vs %.1f" % [rect.position.y, overlay.button_band_bottom()])
		check(absf(rect.end.x - bounds.end.x) <= 1.0,
				"...and in the top-right corner (C16)",
				"%.1f vs %.1f" % [rect.end.x, bounds.end.x])
		_container.show_hud()
		await get_tree().process_frame
		check(not button.is_visible_in_tree(),
				"the HUD hides it again: it belongs to the description")
	await _end_game_fixture()

## A resize re-lays the description that is already up, so its content follows the container's new width rather than keeping the old one.
func test_a_resize_relays_the_description_to_the_new_width() -> void:
	await _start_game_fixture()
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		check(_panel.visible, "the description is up before the resize")
		_booted_viewport.size = Vector2i(1920, 1080)
		await get_tree().process_frame
		await get_tree().process_frame
		var width := _container.container_rect().size.x
		var content : VBoxContainer = _panel.get_node(^"%Content")
		check(absf(_panel.size.x - width) <= 1.0,
				"the panel follows the container's new width",
				"%.1f vs %.1f" % [_panel.size.x, width])
		check(absf(content.size.x - width) <= 1.0,
				"...and so does the content it lays out",
				"%.1f vs %.1f" % [content.size.x, width])
		var carried := content.custom_minimum_size.y
		_panel.resize_to(Vector2(width, _panel.size.y))
		check(absf(content.custom_minimum_size.y - carried) <= 0.5,
				"...and the height it scrolls to is the new width's, not the old one's",
				"%.1f carried vs %.1f fresh" % [carried, content.custom_minimum_size.y])
	await _end_game_fixture()

# ------------------------------------------------------------------ S6: follow, return, dismiss

## The keyboard Back the wall reads, built the way `test_wall_input` builds it.
func _cancel_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event

# Clicks an Entrance card and leaves NOTHING held, so a later cancel cannot be spent on the ungrab
# instead of on the description.
func _lock_without_holding(control: Control) -> void:
	await _click_card(control)
	_play_area.ungrab_cards()
	await get_tree().process_frame

## 1.4/B7/Q60=c: a locked description FOLLOWS the hover onto another card, and the lock stays where it was.
func test_the_description_follows_the_hover_while_locked() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var locked : CardData = _play_area.ui_data[entrance[0]]
		await _click_card(entrance[0])
		var title : Label = _panel.get_node(^"%Title")
		check(_container.is_locked() and _play_area.locked_data == locked,
				"the click locked the description to the card it landed on")
		var controls := await _hoverable_card_controls()
		var elsewhere := await _hover_another_card(controls, _play_area.moused_hovered_control)
		check(elsewhere != null, "the pointer landed on a second card")
		if elsewhere != null:
			var hovered : CardData = _play_area.ui_data[elsewhere]
			check(hovered != locked, "...a different card from the locked one")
			check(title.text == _expected_text(hovered)[0],
					"the description FOLLOWS the hover while locked (B7, Q60=c)", title.text)
			check(_container.is_locked() and _play_area.locked_data == locked,
					"...and the lock is still on the first card (B8)")
			check(_play_area.data_card[locked].focused,
					"...which keeps its marking behind the hover (Q58=c)")
	await _end_game_fixture()

## 1.5/B7/B4: the pointer leaving everything returns to the LOCKED card, and with no lock keeps the last entry.
func test_leaving_everything_returns_to_the_locked_card() -> void:
	await _start_game_fixture()
	var slot : Control = _panel.get_node(^"%VisualSlot")
	var title : Label = _panel.get_node(^"%Title")
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var locked : CardData = _play_area.ui_data[entrance[0]]
		await _click_card(entrance[0])
		var locked_visual : Node = _panel.current_entry.visual
		var controls := await _hoverable_card_controls()
		var elsewhere := await _hover_another_card(controls, _play_area.moused_hovered_control)
		check(elsewhere != null, "the pointer landed on a second card")
		_hover(_bare_board_point(controls))
		await get_tree().process_frame
		await get_tree().process_frame
		check(title.text == _expected_text(locked)[0],
				"the pointer leaving every card returns to the LOCKED card (B7, Q60=c)", title.text)
		var back : InfoEntry = _panel.current_entry
		check(is_instance_valid(locked_visual) and back != null and back.visual == locked_visual
				and locked_visual.get_parent() == slot,
				"...the very visual the lock was shown with, handed back rather than freed")
		_hover(_off_the_board_point())
		await get_tree().process_frame
		await get_tree().process_frame
		check(title.text == _expected_text(locked)[0],
				"...and leaving the board entirely keeps it there", title.text)

		_container.show_hud()
		var first := await _hover_another_card(controls, null)
		var second := await _hover_another_card(controls, first)
		check(second != null, "two cards can be read in turn with nothing locked")
		if second != null:
			_hover(_bare_board_point(controls))
			await get_tree().process_frame
			await get_tree().process_frame
			check(not _container.is_locked(), "nothing is locked once the container went back")
			check(title.text == _expected_text(_play_area.ui_data[second])[0],
					"...so leaving everything STAYS on the last card read (B4)", title.text)
	await _end_game_fixture()

## B7 for the pad: the board focus landing on a HUD control leaves no card highlighted, so the locked card comes back.
func test_focus_leaving_the_board_returns_to_the_locked_card() -> void:
	await _start_game_fixture()
	var title : Label = _panel.get_node(^"%Title")
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var locked : CardData = _play_area.ui_data[entrance[0]]
		await _click_card(entrance[0])
		_hover(_off_the_board_point())
		await get_tree().process_frame
		var elsewhere := _another_card_control(await _hoverable_card_controls(), locked)
		check(elsewhere != null, "a second card can take the board focus")
		if elsewhere != null:
			elsewhere.grab_focus()
			await get_tree().process_frame
			await get_tree().process_frame
			var moved : CardData = _play_area.ui_data[elsewhere]
			check(title.text == _expected_text(moved)[0],
					"the pad's own highlight moved the description with it (B1)", title.text)
			_container.submit_button.grab_focus()
			await get_tree().process_frame
			await get_tree().process_frame
			check(_play_area.get_viewport().gui_get_focus_owner() == null,
					"the board has no focused control left once the HUD took the focus",
					str(_play_area.get_viewport().gui_get_focus_owner()))
			check(title.text == _expected_text(locked)[0],
					"...so the description returns to the locked card (B7, Q60=c)", title.text)
	await _end_game_fixture()

## 1.7/B9/B10/Q64=a: cancel with nothing held reverts to the HUD and is spent doing it; with nothing showing it still reaches the wall's Back.
func test_cancel_reverts_to_the_hud_and_only_then_is_spent() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		var dismissals : Array[int] = []
		_container.description_dismissed.connect(func() -> void: dismissals.append(1))
		var went_back : Array[bool] = [false]
		_main.wall.back_requested.connect(func() -> void: went_back[0] = true)
		check(_container.showing_description() and _play_area.selected_cards.is_empty(),
				"the description is up and nothing is held before the cancel")

		_main.wall._unhandled_input(_cancel_event())
		await get_tree().process_frame
		check(hud_stack.visible and not _panel.visible,
				"cancel with nothing held reverts the container to the HUD (B9, B10)")
		check(not _container.is_locked(), "...and the lock is gone with it")
		check(dismissals.size() == 1, "...announced exactly once", str(dismissals.size()))
		check(not went_back[0],
				"...and that cancel is SPENT on the dismissal, never reaching the wall's own Back")

		_main.wall._unhandled_input(_cancel_event())
		await get_tree().process_frame
		check(went_back[0],
				"a cancel with NOTHING showing falls through to the wall's Back, exactly as before")
	await _end_game_fixture()

## 1.7/B9/B10: a real press on bare board reverts the container to the HUD.
func test_a_press_on_bare_board_reverts_to_the_hud() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		var read := await _hover_another_card(controls, null)
		check(read != null, "the pointer read a card first")
		var dismissals : Array[int] = []
		_container.description_dismissed.connect(func() -> void: dismissals.append(1))
		check(_container.showing_description(), "the description is up before the press")
		var bare := _bare_board_point(controls)
		_hover(bare)
		await get_tree().process_frame
		await _click(bare, _game_viewport)
		check(hud_stack.visible and not _panel.visible,
				"a press on bare board reverts the container to the HUD (B9, B10)")
		check(dismissals.size() == 1, "...announced exactly once", str(dismissals.size()))
	await _end_game_fixture()

# A landing for `held` the board itself accepts or refuses, asked through the SAME
# `on_can_place_stack` dispatch `try_place` uses, so no placement rule is spelled out here.
func _placement_target(controls: Array[Control], held: Array[CardData], legal: bool) -> Control:
	var game := CardEnvironment.get_current_game()
	for control : Control in controls:
		if not _is_selectable(control): continue
		var data : CardData = _play_area.ui_data[control]
		if data in held: continue
		var accepted : Array[CardData] = await game.return_first_data_array_result(
				&"on_can_place_stack", held, data)
		if accepted.is_empty() != legal: return control
	return null

## Clicks an Entrance card and hands back what the board grabbed -- the shared opening of every placement test.
func _grab_a_card_to_place() -> Array[CardData]:
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a grabbable Entrance card",
			str(entrance.size()))
	if entrance.is_empty(): return []
	await _click_card(entrance[0])
	var held : Array[CardData] = _play_area.selected_cards.duplicate()
	check(not held.is_empty(), "the click grabbed a card to place", str(held.size()))
	return held

## B12/Q63=a: placing the held card finishes the interaction, so the description closes -- a refused place leaves it up.
func test_placing_a_card_closes_the_description() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var held := await _grab_a_card_to_place()
	if not held.is_empty():
		var controls := await _hoverable_card_controls()
		var refused := await _placement_target(controls, held, false)
		check(refused != null, "the board offers a cell this card may NOT land on")
		if refused != null:
			await _click_card(refused)
			check(_panel.visible and not hud_stack.visible,
					"a refused place leaves the description up: the choice is not finished")
			check(not _play_area.selected_cards.is_empty(), "...and the card is still held")
		var legal := await _placement_target(await _hoverable_card_controls(), held, true)
		check(legal != null, "the board offers a cell this card MAY land on")
		if legal != null:
			await _click_card(legal)
			await get_tree().process_frame
			check(_play_area.selected_cards.is_empty(), "the card was placed",
					str(_play_area.selected_cards.size()))
			check(hud_stack.visible and not _panel.visible,
					"placing the card closes the description (B12, Q63=a)")
			check(not _container.is_locked(), "...and the lock goes with it")
	await _end_game_fixture()

## A leak is no check failure, so the one path that can orphan a visual -- a lock replaced while a hover holds the panel -- is checked here.
func test_replacing_a_displaced_lock_frees_its_visual() -> void:
	var container := _build_container()
	var locked := InfoEntry.new()
	locked.visual = Control.new()
	container.lock_to(locked, CardData.new())
	container.show_description(InfoEntry.new())
	check(is_instance_valid(locked.visual) and locked.visual.get_parent() == null,
			"a hover takes the locked visual OUT of the panel rather than freeing it")
	container.lock_to(InfoEntry.new(), CardData.new())
	await get_tree().process_frame
	check(not is_instance_valid(locked.visual),
			"...and the NEXT lock frees the displaced one, which nothing holds any more")
	container.queue_free()


# ------------------------------------------------------------------ S7: the processing rule

## Exactly one content child ever shows, so "the HUD is what is up" is one question both ways.
func _hud_is_up() -> bool:
	return (_container.get_node(^"%HudStack") as Control).visible and not _panel.visible

## The control the board presents `data` on NOW -- a grab rebuilds the board and its slot controls are POOLED, so one read before a rebuild can name a different card after it.
func _control_for(data: CardData) -> Control:
	for control : Control in _play_area.ui_data:
		if _play_area.ui_data[control] == data: return control
	return null

# A real placement, watched two ways at once: the flip itself (a cascade shorter than a frame is
# still a cascade) and then every frame it runs for. Returns [flips, flips with the HUD up,
# busy frames, busy frames with the HUD up].
func _place_and_watch_the_cascade(target: Control) -> Array[int]:
	var game := CardEnvironment.get_current_game()
	var counts : Array[int] = [0, 0, 0, 0]
	var watcher := func(busy: bool) -> void:
		if not busy: return
		counts[0] += 1
		if _hud_is_up(): counts[1] += 1
	game.processing_changed.connect(watcher)
	var at := target.get_global_rect().get_center()
	_hover(at)
	await get_tree().process_frame
	_push_mouse_button(at, _game_viewport, true)
	_push_mouse_button(at, _game_viewport, false)
	var waited := 0.0
	while waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if game.processing:
			counts[2] += 1
			if _hud_is_up(): counts[3] += 1
		elif counts[0] > 0:
			break
	game.processing_changed.disconnect(watcher)
	return counts

## 1.9/B17/B18/C8/Q255=a/Q256=a: `processing` going true reverts to the HUD whatever was showing, and the lock is gone for good.
func test_processing_reverts_to_the_hud_and_drops_the_lock() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var dismissals : Array[bool] = []
		_container.description_dismissed.connect(func() -> void: dismissals.append(true))
		await _lock_without_holding(entrance[0])
		check(_container.is_locked() and not _hud_is_up(),
				"a LOCKED description is what shows before the cascade")
		dismissals.clear()
		var game := CardEnvironment.get_current_game()
		game.processing = true
		check(_hud_is_up(), "processing reverts the container to the HUD, lock and all (B17, Q255=a)")
		check(not _container.is_locked(), "...and the lock is gone (B18, Q256=a)")
		check(_play_area.locked_data == null, "...so the board drops that card's marking too")
		check(dismissals.size() == 1, "...announced exactly once", str(dismissals.size()))
		dismissals.clear()
		game.processing = false
		check(_hud_is_up(), "the lock is NOT restored when processing ends (B18)")
		check(dismissals.is_empty(), "...and nothing is announced for a HUD that was already up",
				str(dismissals.size()))
	await _end_game_fixture()

## 1.9/C8/Q259b=b: a REAL placement -- the HUD is what the whole cascade is watched in, from the flip to the last frame.
func test_a_real_cascade_holds_the_hud_for_its_whole_length() -> void:
	await _start_game_fixture()
	var held := await _grab_a_card_to_place()
	if not held.is_empty():
		var legal := await _placement_target(await _hoverable_card_controls(), held, true)
		check(legal != null, "the board offers a cell this card MAY land on")
		if legal != null:
			var counts := await _place_and_watch_the_cascade(legal)
			check(counts[0] >= 1, "the placement really started a cascade", str(counts[0]))
			check(counts[1] == counts[0],
					"the HUD was up the instant processing began (B17, C8)",
					"%d of %d flips" % [counts[1], counts[0]])
			check(counts[3] == counts[2],
					"...and for every frame the cascade ran (C8, Q259b=b)",
					"%d of %d frames" % [counts[3], counts[2]])
			check(_hud_is_up(), "...and it is still up once the cascade has finished (B20)")
			check(not _container.is_locked(), "...with no lock left behind (B18)")
	await _end_game_fixture()

## 1.10/B19/Q258=a: a hover DURING the cascade is ignored entirely, so a resting pointer cannot swap the HUD straight back out.
func test_a_hover_during_processing_changes_nothing() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		var game := CardEnvironment.get_current_game()
		game.processing = true
		check(_hud_is_up(), "the cascade put the HUD up")
		var elsewhere := await _hover_another_card(await _hoverable_card_controls(),
				_play_area.moused_hovered_control)
		check(elsewhere != null, "the pointer landed on another card mid-cascade")
		check(_hud_is_up(), "...and the HUD is still what shows: the hover is ignored (B19, Q258=a)")
		check(not _container.is_locked(), "...with no lock taken from it either")
		game.processing = false
	await _end_game_fixture()

## 1.11/B20/C9/Q257=b: once the cascade ends the HUD holds until ANY focus event -- landing back on the card it was already on counts.
func test_the_hud_holds_after_processing_until_any_focus_event() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var read : CardData = _play_area.ui_data[entrance[0]]
		await _lock_without_holding(entrance[0])
		var game := CardEnvironment.get_current_game()
		game.processing = true
		var elsewhere := await _hover_another_card(await _hoverable_card_controls(),
				_control_for(read))
		check(elsewhere != null and _play_area.ui_data[elsewhere] != read,
				"the pointer landed on a DIFFERENT card mid-cascade")
		game.processing = false
		await get_tree().process_frame
		check(_hud_is_up(), "processing ended and the HUD HOLDS with no focus event (B20, C9)")
		var back := _control_for(read)
		check(back != null, "the card that was being read before the cascade is still on the board")
		if back != null:
			check(_game_viewport.gui_get_focus_owner() != back,
					"...and the board focus is elsewhere, so landing on it again is a real focus event")
			back.grab_focus()
			await get_tree().process_frame
			var title : Label = _panel.get_node(^"%Title")
			check(not _hud_is_up(),
					"one focus event onto the SAME card opens the description again (Q257=b)")
			check(title.text == _expected_text(read)[0], "...that card's own description", title.text)
			var other := await _hover_another_card(await _hoverable_card_controls(), back)
			check(other != null, "a real hover reaches a different card")
			if other != null:
				check(title.text == _expected_text(_play_area.ui_data[other])[0],
						"...and the ordinary hover route is live again", title.text)
	await _end_game_fixture()

## 1.12/C10/Q260b=b: the processing rule is the GAME screen only -- the map has no cascade worth watching, so its container never swaps on one.
func test_the_maps_container_does_not_swap_on_the_games_processing() -> void:
	await _start_game_fixture()
	await _main._focus_picture(&"map")
	check((_container.get_node(^"%MapHud") as Control).visible, "the map is the focused screen")
	var nodes := _main.map_scene.controller.map.overlay().nodes()
	check(not nodes.is_empty(), "the generated map offers a node to hover", str(nodes.size()))
	if not nodes.is_empty():
		var node : WorldGraphNode = nodes[0]
		_main.map_scene.controller.node_hovered.emit(node)
		check(_container.showing_description(), "a map hover fills the sidebar")
		var game := CardEnvironment.get_current_game()
		game.processing = true
		check(_container.showing_description(),
				"the game's processing leaves the map's description up (C10, Q260b=b)")
		_main.map_scene.controller.node_hovered.emit(node)
		check(_container.showing_description(),
				"...and the map's own publications still reach it mid-cascade")
		game.processing = false
	await _end_game_fixture()

## B20/C9/Q257=b: nothing is de-duplicated away -- the very entry that was up when the cascade started re-shows when it is published again.
func test_the_same_entry_published_again_after_processing_still_shows() -> void:
	var container := _build_container()
	container.set_active_screen(&"game")
	var entry := InfoEntry.new()
	container.show_description(entry)
	check(container.showing_description(), "the entry is what shows before the cascade")
	container.set_processing(true)
	check(not container.showing_description(), "processing put the HUD up (B17)")
	container.set_processing(false)
	check(not container.showing_description(), "...and the HUD holds once processing ends (B20)")
	container.show_description(entry)
	check(container.showing_description(),
			"the SAME entry published again re-shows it: nothing is swallowed (Q257=b)")
	container.queue_free()

# ------------------------------------------------------------------ S8: scroll and multi-modal reach

## How many lines the scroll fixtures' body carries -- a real card's own text is three lines and fits every window this suite builds, which would leave every scroll assertion trivially true.
const LONG_BODY_LINES := 80

## Frames a pushed stick is held for before the scroll it drives is read -- the stick reports once and the container integrates it per frame.
const STICK_HELD_FRAMES := 10

func _long_entry() -> InfoEntry:
	var entry := InfoEntry.new()
	entry.title = "Scrolling"
	var lines : Array[String] = []
	for line : int in LONG_BODY_LINES:
		lines.append("line %d of a description far longer than the container is tall" % line)
	entry.body = "\n".join(lines)
	return entry

func _short_entry() -> InfoEntry:
	var entry := InfoEntry.new()
	entry.title = "Short"
	entry.body = "One line."
	return entry

func _panel_scroll(panel: DescriptionPanel) -> ScrollContainer:
	return panel.get_node(^"%Scroll") as ScrollContainer

# The axis the InputMap actually binds, never a constant of this suite's own: Q102=a makes every
# action rebindable, and pinning one here would turn a rebind into a failure.
func _scroll_stick_axis() -> int:
	if not InputMap.has_action(&"sidebar_scroll"): return -1
	for event : InputEvent in InputMap.action_get_events(&"sidebar_scroll"):
		var motion := event as InputEventJoypadMotion
		if motion: return motion.axis
	return -1

func _push_scroll_stick(viewport: Viewport, axis_value: float) -> void:
	var axis := _scroll_stick_axis()
	if axis < 0: return
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis as JoyAxis
	motion.axis_value = axis_value
	viewport.push_input(motion)

func _push_key(viewport: Viewport, keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	viewport.push_input(event)

## Q42=a: `sidebar_scroll` is a real action, on an axis Godot's own navigation does not already steer with.
func test_the_sidebar_scroll_action_binds_the_non_navigation_stick() -> void:
	check(InputMap.has_action(&"sidebar_scroll"), "the InputMap registers sidebar_scroll")
	if not InputMap.has_action(&"sidebar_scroll"): return
	var events := InputMap.action_get_events(&"sidebar_scroll")
	check(not events.is_empty(), "sidebar_scroll has at least one real binding",
			"events=%d" % events.size())
	var axes : Array[int] = []
	var directions : Array[float] = []
	for event : InputEvent in events:
		var motion := event as InputEventJoypadMotion
		check(motion != null, "every sidebar_scroll binding is a joypad axis (Q42=a)")
		if motion == null: continue
		if not axes.has(motion.axis): axes.append(motion.axis)
		if not directions.has(signf(motion.axis_value)): directions.append(signf(motion.axis_value))
	check(axes.size() == 1, "...all of them the same axis, so one stick scrolls", str(axes))
	check(directions.size() == 2, "...bound both ways, so the stick scrolls up AND down",
			str(directions))
	var navigation_axes : Array[int] = []
	for action : StringName in ([&"ui_up", &"ui_down"] as Array[StringName]):
		for event : InputEvent in InputMap.action_get_events(action):
			var motion := event as InputEventJoypadMotion
			if motion and not navigation_axes.has(motion.axis):
				navigation_axes.append(motion.axis)
	check(not axes.is_empty() and not navigation_axes.has(axes[0]),
			"...and it is NOT the stick ui_up/ui_down already navigate with (Q42=a)",
			"scroll=%s navigation=%s" % [str(axes), str(navigation_axes)])

## Q40=b/Q41=a: an overflowing description shows the scrollbar and opens at the top, however far the last one was scrolled.
func test_a_long_description_shows_a_scrollbar_and_rests_at_the_top() -> void:
	var container := _build_container()
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var scroll := _panel_scroll(panel)
	container.show_description(_long_entry())
	await get_tree().process_frame
	await get_tree().process_frame
	check(scroll.get_v_scroll_bar().visible,
			"a description taller than the container shows the scrollbar (Q40=b)")
	check(scroll.scroll_vertical == 0, "...and opens at the top (Q41=a)",
			str(scroll.scroll_vertical))
	_push_key(get_viewport(), KEY_PAGEDOWN, true)
	await get_tree().process_frame
	check(scroll.scroll_vertical > 0, "a page down really moved it", str(scroll.scroll_vertical))
	container.show_description(_long_entry())
	await get_tree().process_frame
	check(scroll.scroll_vertical == 0, "...and the next description rests at the top again (Q41=a)",
			str(scroll.scroll_vertical))
	container.queue_free()

## Q40=b: the other half of the rule -- content that fits carries no scrollbar at all.
func test_a_short_description_hides_the_scrollbar() -> void:
	var container := _build_container()
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var scroll := _panel_scroll(panel)
	container.show_description(_short_entry())
	await get_tree().process_frame
	await get_tree().process_frame
	check(not scroll.get_v_scroll_bar().visible,
			"a description that fits shows no scrollbar (Q40=b)")
	container.queue_free()

## Q43=b: Page Down and Page Up move the description a page, whenever it is what shows.
func test_page_keys_scroll_the_description_by_a_page() -> void:
	var container := _build_container()
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var scroll := _panel_scroll(panel)
	container.show_description(_long_entry())
	await get_tree().process_frame
	await get_tree().process_frame
	_push_key(get_viewport(), KEY_PAGEDOWN, true)
	await get_tree().process_frame
	var page := scroll.size.y
	check(absf(float(scroll.scroll_vertical) - page) <= 1.0,
			"Page Down scrolls exactly one page of the description (Q43=b)",
			"%d vs %.1f" % [scroll.scroll_vertical, page])
	_push_key(get_viewport(), KEY_PAGEUP, true)
	await get_tree().process_frame
	check(scroll.scroll_vertical == 0, "...and Page Up brings it back",
			str(scroll.scroll_vertical))
	container.queue_free()

## Q42=a: the stick scrolls whatever description is showing, and does nothing at all behind the HUD.
func test_the_scroll_stick_scrolls_the_description_and_not_the_hud() -> void:
	var container := _build_container()
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var scroll := _panel_scroll(panel)
	container.show_description(_long_entry())
	await get_tree().process_frame
	await get_tree().process_frame
	_push_scroll_stick(get_viewport(), 1.0)
	for frame : int in STICK_HELD_FRAMES: await get_tree().process_frame
	var scrolled := scroll.scroll_vertical
	check(scrolled > 0, "the stick scrolls the description while it shows (Q42=a)", str(scrolled))
	_push_scroll_stick(get_viewport(), 0.0)
	await get_tree().process_frame
	var rested := scroll.scroll_vertical
	for frame : int in STICK_HELD_FRAMES: await get_tree().process_frame
	check(scroll.scroll_vertical == rested, "...and stops the moment it centres",
			"%d vs %d" % [scroll.scroll_vertical, rested])
	container.show_hud()
	_push_scroll_stick(get_viewport(), 1.0)
	for frame : int in STICK_HELD_FRAMES: await get_tree().process_frame
	check(scroll.scroll_vertical == rested, "...and moves nothing while the HUD shows",
			"%d vs %d" % [scroll.scroll_vertical, rested])
	_push_scroll_stick(get_viewport(), 0.0)
	container.queue_free()

## Q43=b: the arrows are the sidebar's only once it is LOCKED; unlocked they stay the board's own.
func test_the_arrows_scroll_only_once_the_description_is_locked() -> void:
	await _start_game_fixture()
	var scroll := _panel_scroll(_panel)
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to read",
			str(controls.size()))
	if not controls.is_empty():
		controls[0].grab_focus()
		await get_tree().process_frame
		var focused_before := _game_viewport.gui_get_focus_owner()
		check(focused_before == controls[0],
				"a board card holds the key/pad focus before any arrow is pushed")
		_container.show_description(_long_entry())
		await get_tree().process_frame
		await get_tree().process_frame
		_push_key(_booted_viewport, KEY_DOWN, true)
		var handled_unlocked := _booted_viewport.is_input_handled()
		await get_tree().process_frame
		check(scroll.scroll_vertical == 0,
				"an UNLOCKED description does not take the arrow (Q43=b)",
				str(scroll.scroll_vertical))
		check(not handled_unlocked, "...so the board still gets it")
		_container.lock_to(_long_entry(), _play_area.ui_data[controls[0]])
		await get_tree().process_frame
		await get_tree().process_frame
		_push_key(_booted_viewport, KEY_DOWN, true)
		var handled_locked := _booted_viewport.is_input_handled()
		await get_tree().process_frame
		check(scroll.scroll_vertical > 0, "a LOCKED description scrolls on the arrow (Q43=b)",
				str(scroll.scroll_vertical))
		check(handled_locked, "...spending the event before the board can see it")
		check(_game_viewport.gui_get_focus_owner() == focused_before,
				"...so the board's own selection does not move with it")
	await _end_game_fixture()

## Q68=b/C16: the exit X joins keyboard/pad navigation only while the sidebar is locked, and accept on it dismisses.
func test_the_exit_x_joins_navigation_only_while_locked() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to read",
			str(controls.size()))
	if not controls.is_empty():
		_container.show_description(_long_entry())
		await get_tree().process_frame
		check(_exit_button().focus_mode == Control.FOCUS_NONE,
				"an unlocked description keeps the X out of the navigation path (Q68=b)",
				str(_exit_button().focus_mode))
		_container.lock_to(_long_entry(), _play_area.ui_data[controls[0]])
		await get_tree().process_frame
		check(_exit_button().focus_mode == Control.FOCUS_ALL,
				"...and locking puts it in (Q68=b, C16)", str(_exit_button().focus_mode))
		_exit_button().grab_focus()
		await get_tree().process_frame
		check(_exit_button().has_focus(), "...where navigation can land on it")
		_push_key(_booted_viewport, KEY_ENTER, true)
		_push_key(_booted_viewport, KEY_ENTER, false)
		await get_tree().process_frame
		check(hud_stack.visible and not _panel.visible,
				"...and accept on it dismisses the description (C16)")
		check(not _container.is_locked(), "...taking the lock with it")
	await _end_game_fixture()
