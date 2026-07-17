extends TestSuite
# res://Tests/Interaction/test_interaction.gd
# ==============================================================================
# INTERACTIVITY, ALL INPUT MODES: drives the REAL GameView with synthesized
# input events — mouse, touchscreen (touch -> emulated-mouse pipeline),
# keyboard, and controller — and asserts every UI surface responds: card
# selection + cancel, the HUD buttons, undo pressed mid-Submit, and the
# game-over overlay contract (covers ONLY the board; Undo rewinds the outcome;
# no card input of ANY mode leaks through).
#
# Events go through Input.parse_input_event (the full pipeline: mouse
# emulation, hover, focus routing) — never direct handler calls — so a broken
# signal connection or mouse filter fails here exactly like it fails a player.
#
# CATEGORY MAP: all BEHAVIOR — every check is "a player pressed X and saw Y".
#
# Ordering: owns CardEnvironment.CURRENT / Main.save_info / settings + the real
# save, so it serializes with the other whole-app suites: waits for every
# sibling EXCEPT UI PROPS (which itself waits for this suite) and E2E (which
# waits for ALL) — this suite runs third-to-last.
# ==============================================================================

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const WATCHDOG_SECS := 10.0
## Slow enough that a Submit is still mid-animation two frames in (the cancel test
## needs the Undo click to land DURING the resolution).
const SLOW_DELAY := 0.4

const REAL_SETTINGS_PATH := "user://settings.tres"
const REAL_SETTINGS_BAK := "user://settings.tres.interbak"

func suite_name() -> String:
	return "INTERACTION"

var view : GameView
var game : Game
var pa : PlayArea
var prev_run : RunState
var prev_save_info : RunState
## Every data_selected emission from the play area — the "input reached the card
## pipeline" probe (grab LEGALITY is the engine's business, tested elsewhere).
var selections : Array[CardData] = []

func _ready() -> void:
	# Runs before UI PROPS / VISUAL LAYERS / E2E (they wait on this) — exclude them to avoid a
	# deadlock. See TestSuite.await_siblings_except and its DEADLOCK RULE.
	await await_siblings_except(["UI PROPS", "VISUAL LAYERS", "E2E RUN", "LEAK CANARY"])
	TestLog.line("============ INTERACTION TEST PASS ============")
	backup_real_save()
	_backup_settings()
	var prev_delay : float = SettingsManager.settings.base_delay
	SettingsManager.settings.base_delay = TestLog.speed_base_delay
	prev_run = RunManager.run
	prev_save_info = Main.save_info
	await _setup_view()
	behavior_section("CARD SELECTION, EVERY INPUT MODE")
	await test_mouse_click_selects_card()
	await test_mouse_right_click_ungrabs()
	await test_keyboard_select_and_cancel()
	await test_controller_select_and_cancel()
	await test_controller_focus_navigation()
	behavior_section("TOUCHSCREEN (touch -> emulated mouse)")
	await test_touch_taps_next_button()
	behavior_section("UNDO DURING A RESOLVING SUBMIT (the real button)")
	await test_undo_button_cancels_live_submit()
	behavior_section("GAME OVER OVERLAY CONTRACT")
	await test_game_over_interactivity()
	await _teardown_view()
	SettingsManager.settings.base_delay = prev_delay
	_restore_settings()
	finish()

# ==============================================================================
# FIXTURE — one real GameView on a frozen test deck, board dealt by two Nexts.
# ==============================================================================
func _setup_view() -> void:
	var src_cards := TestDecks.seeded_deck()
	var src_rules := TestDecks.standard_rules()
	var run := RunManager.new_run(src_cards, src_rules)
	unlink_cards(src_cards)   # new_run deep-duplicated them; the sources drop here
	unlink_cards(src_rules)
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	view = GAME_VIEW_SCENE.instantiate()
	add_child(view)
	await frames(2)
	game = view.game
	pa = view.play_area
	pa.data_selected.connect(func(d: CardData) -> void: selections.append(d))
	await game.next()
	await game.next()
	pa.flush_rebuild()
	await frames(2)

func _teardown_view() -> void:
	# Teardown discipline (see test_leak_canary.gd): the Game frees with the view and the
	# run doc drops with clear_save — break their CardData<->modifier cycles.
	var doomed_state : GameData = game.state
	var run : RunState = RunManager.run
	view.queue_free()   # frees its Game child too
	await frames(1)
	doomed_state.unlink_modifier_backrefs()
	if run:
		unlink_cards(run.card_datas)
		unlink_cards(run.rule_datas)
	CardEnvironment.CURRENT = null
	# join any in-flight background save BEFORE clearing, then put reality back
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save()
	RunManager.run = prev_run
	Main.save_info = prev_save_info

func _backup_settings() -> void:
	if FileAccess.file_exists(REAL_SETTINGS_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_PATH),
				ProjectSettings.globalize_path(REAL_SETTINGS_BAK))

func _restore_settings() -> void:
	if not FileAccess.file_exists(REAL_SETTINGS_BAK):
		return
	if FileAccess.file_exists(REAL_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_BAK),
			ProjectSettings.globalize_path(REAL_SETTINGS_PATH))

# ==============================================================================
# INPUT SYNTHESIS — everything through Input.parse_input_event + flush, so the
# full pipeline (emulation, hover, focus routing) runs like a real device.
#
# COORDINATES: parse_input_event takes WINDOW coordinates, but every rect we
# measure (get_global_rect) is in CANVAS coordinates. In a desktop window the
# two coincide, so raw positions happen to work — but headless the window is
# 0x0 (Godot clamps the root to 100x100) while canvas_items stretch keeps the
# canvas at 1152 wide, so the window->canvas inverse transform blows raw canvas
# positions ~11x past every control and no positioned click ever lands (all 10
# position-based checks failed headless, 2026-07-16). to_window() maps canvas ->
# window via the root's final transform; identity in a normal window, so this
# is correct everywhere, not a headless special case.
# ==============================================================================
func frames(n: int) -> void:
	for _i : int in n:
		await get_tree().process_frame

func wait_until(pred: Callable) -> bool:
	var waited := 0.0
	while not (pred.call() as bool) and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return pred.call() as bool

func send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame

## Canvas -> window coordinates (see COORDINATES above). All the positioned
## event builders below take canvas positions and convert here.
func to_window(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos

func mouse_move_to(pos: Vector2) -> void:
	var wpos := to_window(pos)
	var mm := InputEventMouseMotion.new()
	mm.position = wpos
	mm.global_position = wpos
	await send(mm)

func mouse_click(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await mouse_move_to(pos)   # hover first: selection requires the hovered control
	var wpos := to_window(pos)
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

func key_tap(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	await send(down)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	await send(up)

func joy_tap(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button
	down.pressed = true
	await send(down)
	var up := InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	await send(up)

func touch_tap(pos: Vector2) -> void:
	var wpos := to_window(pos)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = wpos
	down.pressed = true
	await send(down)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = wpos
	up.pressed = false
	await send(up)

## Any focusable board control (card or empty-column header) — the selection probe target.
func a_card_control() -> Control:
	pa.flush_rebuild()
	for control : Control in pa.ui_data:
		if control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			return control
	return null

func center_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

func prop_visual_count() -> int:
	var n := 0
	for child in pa.prop_layer.get_children():
		if child is PropVisual and not (child as PropVisual).is_queued_for_deletion():
			n += 1
	return n

# ==============================================================================
# MODALITY TESTS
# ==============================================================================
func test_mouse_click_selects_card() -> void:
	var control := a_card_control()
	check(control != null, "a dealt board offers a focusable card control")
	if not control: return
	selections.clear()
	await mouse_click(center_of(control))
	check(selections.size() >= 1 and selections[0] == pa.ui_data[control],
			"a mouse click over a card emits its selection", str(selections.size()))
	pa.ungrab_cards()

func test_mouse_right_click_ungrabs() -> void:
	var control := a_card_control()
	check(control != null, "board control available for the grab")
	if not control: return
	var data : CardData = pa.ui_data[control]
	pa.grab_cards([data] as Array[CardData])
	check(not pa.selected_cards.is_empty(), "precondition: cards are held")
	await mouse_click(center_of(control), MOUSE_BUTTON_RIGHT)
	check(pa.selected_cards.is_empty(), "right-click cancels the held grab")

func test_keyboard_select_and_cancel() -> void:
	var control := a_card_control()
	check(control != null, "board control available for keyboard focus")
	if not control: return
	selections.clear()
	control.grab_focus()
	await frames(1)
	await key_tap(KEY_ENTER)
	check(selections.size() >= 1, "ui_accept (Enter) on the focused card emits its selection")
	pa.grab_cards([pa.ui_data[control]] as Array[CardData])
	control.grab_focus()   # key events route through the focused control's gui_input chain
	await frames(1)
	await key_tap(KEY_ESCAPE)
	check(pa.selected_cards.is_empty(), "ui_cancel (Escape) drops the held cards")
	pa.ungrab_cards()   # hermetic: a failure above must not leak a held grab downstream

func test_controller_select_and_cancel() -> void:
	var control := a_card_control()
	check(control != null, "board control available for controller focus")
	if not control: return
	selections.clear()
	control.grab_focus()
	await frames(1)
	await joy_tap(JOY_BUTTON_A)
	check(selections.size() >= 1, "ui_accept (joypad A) on the focused card emits its selection")
	pa.grab_cards([pa.ui_data[control]] as Array[CardData])
	control.grab_focus()
	await frames(1)
	await joy_tap(JOY_BUTTON_B)
	check(pa.selected_cards.is_empty(), "ui_cancel (joypad B) drops the held cards")
	pa.ungrab_cards()   # hermetic: a failure above must not leak a held grab downstream

func test_controller_focus_navigation() -> void:
	var control := a_card_control()
	check(control != null, "board control available for dpad navigation")
	if not control: return
	control.grab_focus()
	await frames(1)
	var before : Control = get_viewport().gui_get_focus_owner()
	await joy_tap(JOY_BUTTON_DPAD_RIGHT)
	if get_viewport().gui_get_focus_owner() == before:
		await joy_tap(JOY_BUTTON_DPAD_DOWN)   # edge column: no right neighbor — go down
	var after : Control = get_viewport().gui_get_focus_owner()
	check(after != null and after != before,
			"the dpad moves focus off the first control (controller navigation lives)")

func test_touch_taps_next_button() -> void:
	var deck_before : int = game.state.draw_deck.size()
	await touch_tap(center_of(view.next_button))
	var acted := await wait_until(func() -> bool:
			return not game.processing and game.state.draw_deck.size() != deck_before)
	check(acted, "a touchscreen tap on Next deals cards (touch -> emulated mouse -> button)",
			"deck %d -> %d" % [deck_before, game.state.draw_deck.size()])
	pa.flush_rebuild()
	await frames(1)

# ==============================================================================
# UNDO DURING A RESOLVING SUBMIT — through the real button, real animations. The
# exact cancel semantics are pinned headless (test_game_headless); this asserts
# the BUTTON path: pressable mid-act, never hangs, ends in the pre-submit state.
# ==============================================================================
var _submit_finished : Array[bool] = [false]
func _submit_in_background() -> void:
	await game.submit()
	_submit_finished[0] = true

func test_undo_button_cancels_live_submit() -> void:
	pa.ungrab_cards()   # held cards would make _on_undo_pressed swallow the click
	SettingsManager.settings.base_delay = SLOW_DELAY
	var submits_before : int = game.submits_used
	var history_before : int = game.save_history.size()
	var score_before : int = game.state.total_score
	_submit_finished[0] = false
	_submit_in_background()
	await frames(2)
	check(game.processing, "precondition: the submit is still resolving two frames in")
	check(not view.undo_button.disabled, "the Undo button stays enabled while resolving")
	await mouse_click(center_of(view.undo_button))
	var done := await wait_until(func() -> bool:
			return _submit_finished[0] and not game.processing)
	check(done, "the cancelled submit hands input back (never hangs)")
	check(game.submits_used == submits_before, "no act was consumed", str(game.submits_used))
	check(game.save_history.size() == history_before,
			"nothing was committed by the cancelled submit")
	check(game.state.total_score == score_before, "no act score was applied")
	SettingsManager.settings.base_delay = TestLog.speed_base_delay
	# abort_all frees the visuals; queue_free lands end-of-frame — wait, don't count blind
	var cleared := await wait_until(func() -> bool: return prop_visual_count() == 0)
	check(cleared, "no prop visual is stranded after the cancel", str(prop_visual_count()))

# ==============================================================================
# GAME OVER — the overlay covers exactly the board; Undo rewinds the outcome;
# no input mode reaches the covered cards; the HUD keeps working.
# ==============================================================================
func test_game_over_interactivity() -> void:
	pa.ungrab_cards()   # held cards would make _on_undo_pressed swallow the outcome undo
	var resolved : Array[bool] = [false]
	game.show_resolved.connect(func(_w: bool, _s: int, _g: int) -> void: resolved[0] = true)
	while game.submits_used < Game.MAX_SUBMITS:
		await game.submit()
	check(resolved[0], "the final act resolves the show")
	await frames(2)
	var screen : Label = view.win_screen if view.win_screen.visible else view.lose_screen
	check(screen.visible, "an outcome screen is showing")
	var pa_rect := pa.get_global_rect()
	var s_rect := screen.get_global_rect()
	check(s_rect.grow(8.0).encloses(pa_rect) and pa_rect.grow(8.0).encloses(s_rect),
			"the outcome screen covers the play area and nothing else",
			"screen %s vs board %s" % [s_rect, pa_rect])
	check(view.submit_button.disabled and view.next_button.disabled,
			"Submit and Next are disabled at game over")
	check(not view.undo_button.disabled, "Undo stays pressable at game over")
	var any_focusable := false
	for control : Control in pa.ui_data:
		if control.focus_mode != Control.FOCUS_NONE:
			any_focusable = true
	check(not any_focusable,
			"no covered card control is keyboard/controller focusable at game over")
	check(get_viewport().gui_get_focus_owner() == view._continue_button,
			"the Continue button holds focus for keyboard/controller")
	selections.clear()
	await mouse_click(pa_rect.get_center())
	check(selections.is_empty(), "a click on the covered board selects nothing")
	# Undo at the outcome screen: overlay drops, the final Submit rewinds, play resumes.
	var submits_at_over : int = game.submits_used
	await mouse_click(center_of(view.undo_button))
	await frames(2)
	check(not view.win_screen.visible and not view.lose_screen.visible,
			"Undo dismisses the outcome overlay")
	check(game.submits_used == submits_at_over - 1, "Undo rewinds the final Submit's act")
	check(not game.processing, "play resumes after the outcome undo")
	check(not view.submit_button.disabled and not view.next_button.disabled,
			"Submit and Next come back with play")
	check(a_card_control() != null, "the rebuilt board is focusable again")
