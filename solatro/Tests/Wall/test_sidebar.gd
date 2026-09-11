extends TestSuite
# res://Tests/Wall/test_sidebar.gd
# SIDEBAR: HudContainer and DescriptionPanel as empty shells -- exactly one content
# child visible at a time, HUD by default.

const HUD_CONTAINER_SCENE := preload("res://UI/hud_container.tscn")
const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const MAIN_SCENE := preload("res://Levels/main.tscn")

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
	await test_the_entrance_stays_at_the_same_offset_from_the_grid_across_window_sizes()
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
	var connections : Array[Array] = view_one._container_connections.duplicate()

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

## A control's rect as drawn -- carries every scale above it, since `global_position` alone drops the board's zoom.
func _sidebar_screen_rect(c: Control) -> Rect2:
	var t := c.get_global_transform()
	return Rect2(t.origin, t.get_scale() * c.size)

## The Entrance is board content and stays put relative to the grid, whatever the container's own width does at a different window size.
func test_the_entrance_stays_at_the_same_offset_from_the_grid_across_window_sizes() -> void:
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
	var pa := view.play_area
	await _settle_scroll_x(pa)
	check(view.game.state.grids.size() > 0,
			"a fresh show deals at least one grid for the Entrance to sit beside")

	var grid_a := _sidebar_screen_rect(pa._cells_root(pa.grid_container.get_child(0) as Control))
	var strip_a := _sidebar_screen_rect(pa.upper_zone_right)
	var offset_a := strip_a.position.x - grid_a.position.x

	viewport.size = Vector2i(1920, 1080)
	await get_tree().process_frame
	await get_tree().process_frame
	await _settle_scroll_x(pa)

	var grid_b := _sidebar_screen_rect(pa._cells_root(pa.grid_container.get_child(0) as Control))
	var strip_b := _sidebar_screen_rect(pa.upper_zone_right)
	var offset_b := strip_b.position.x - grid_b.position.x

	check(absf(offset_a - offset_b) <= 1.0,
			"the Entrance sits at the same offset from the grid at both window sizes",
			"%.2f at 1280x720 vs %.2f at 1920x1080" % [offset_a, offset_b])

	main.queue_free()
	await get_tree().process_frame
	viewport.queue_free()
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

