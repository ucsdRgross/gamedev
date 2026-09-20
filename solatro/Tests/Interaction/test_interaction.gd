extends TestSuite
#INTERACTIVITY, ALL INPUT MODES: drives the REAL GameView with synthesized mouse, keyboard and
#controller events, and asserts every UI surface responds - card selection and cancel, the HUD
#buttons, undo pressed mid-act, and the game-over overlay contract.

#Events go through Viewport.push_input, the full pipeline of mouse emulation, hover and focus
#routing, never direct handler calls, so a broken signal connection or mouse filter fails here
#exactly as it fails a player.

#CATEGORY MAP: all BEHAVIOR - every check is "a player pressed X and saw Y".

#Ordering: it owns CardEnvironment.CURRENT, Main.save_info, the settings and the real save, so it
#serializes with the other whole-app suites. It waits for every sibling except UI PROPS, which
#waits for this suite, and E2E, which waits for all, so it runs third-to-last.

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const WATCHDOG_SECS := 10.0
#The cancel test needs the Undo click to land DURING the resolution.

## Slow enough that an act is still mid-animation two frames in.
const SLOW_DELAY := 0.4

func suite_name() -> String:
	return "INTERACTION"

var view : GameView
var game : Game
var pa : PlayArea
#Production lays the board out at that size inside the wall's viewport, never against the OS
#window, so a taller-than-window play area still lands every synthesized click where a player's would.

## The picture's own SubViewport, sized game_picture_design_size.
var picture_vp : SubViewport
var prev_run : RunState
var prev_save_info : RunState
#The "input reached the card pipeline" probe; grab LEGALITY is the engine's business, tested elsewhere.

## Every data_selected emission from the play area.
var selections : Array[CardData] = []

func _ready() -> void:
#Runs before UI PROPS, VISUAL LAYERS and E2E, which wait on this, so they are excluded to avoid a
#deadlock. See TestSuite.await_siblings_except and its DEADLOCK RULE.
	await await_siblings_except(["UI PROPS", "VISUAL LAYERS", "GRID LAYOUT", "GRID VIEW",
			"SIDEBAR", "DRAG PLACE", "SETTINGS RANGE", "E2E RUN", "LEAK CANARY",
			"WALL PAUSE"])
	TestLog.line("============ INTERACTION TEST PASS ============")
	backup_real_save(suite_tag())
#The shared park-the-file isolation: every knob write during this suite lands in a throwaway
#settings.tres, so even an abort cannot strand the player's real knobs.
	backup_real_settings()
	var settings_snapshot := snapshot_settings()
	prev_run = RunManager.run
	prev_save_info = Main.save_info
	await _setup_view()
	behavior_section("CARD SELECTION, EVERY INPUT MODE")
	await test_mouse_click_selects_card()
	await test_mouse_right_click_ungrabs()
	await test_keyboard_select_and_cancel()
	await test_controller_select_and_cancel()
	await test_controller_focus_navigation()
	await test_touch_taps_select_card()
	await test_rebuild_leaves_no_dead_controls()
	behavior_section("UNDO DURING A RESOLVING SUBMIT (the real button)")
	await test_undo_button_cancels_live_act()
	behavior_section("GAME OVER OVERLAY CONTRACT")
	await test_game_over_interactivity()
	await _teardown_view()
	restore_settings_snapshot(settings_snapshot)
	restore_real_settings()
	finish()

# ==============================================================================
# FIXTURE — one real GameView on a frozen test deck, board dealt by two Nexts.
# ==============================================================================
func _setup_view() -> void:
	var src_cards := TestDecks.seeded_deck()
	var src_rules := TestDecks.standard_rules()
	var run := RunManager.new_run(src_cards, src_rules)
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	view = GAME_VIEW_SCENE.instantiate()
	picture_vp = TestGameViewHost.host(self, view)
	input = TestInput.driving(self, picture_vp)
	await frames(2)
	game = view.game
	pa = view.play_area
	pa.data_selected.connect(func(d: CardData) -> void: selections.append(d))
	await game.next()
	await game.next()
	pa.flush_rebuild()
#⚠ ZOOM IN FIRST. A show opens on the all-grids view, where a click on a grid is orientation
#and places nothing; selection and placement, which is what this suite drives, only happen once a
#grid is focused.
	pa.focus_grid(0)
	await _settle_layout()

#Never for a fixed frame count: the Entrance follows the camera, and a click landing mid-ease
#races a native mouse_exited the moment the hovered control slides out from under the cursor.

## Wait for the Entrance to STOP MOVING.
func _settle_layout() -> void:
	var last := INF
	var waited := 0.0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var now := pa.entrance_h_track.position.x
		if is_equal_approx(now, last): return
		last = now

func _teardown_view() -> void:
#Frees the view and its Game child too.
	picture_vp.queue_free()
	await frames(1)
	CardEnvironment.CURRENT = null
#Join any in-flight background save BEFORE clearing, then put reality back.
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# ==============================================================================
# INPUT SYNTHESIS through `TestInput`, into `picture_vp`, whose coordinates are the ones measured here.
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

## The shared driver, so a click here and a click in any other suite are the same event sequence.
var input : TestInput

func send(ev: InputEvent) -> void:
	await input.send(ev)

func mouse_move_to(pos: Vector2) -> void:
	await input.move_to(pos)

func mouse_click(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await input.click(pos, button)

# A click on a card LOCKS a description over the HUD, and the HUD's own buttons are off screen
# while it shows. Reverting to the HUD is what the player does before pressing one, so pressing one
# here starts from the same place.
func click_hud_button(button: Button) -> void:
	view.hud_container.show_hud()
	await frames(1)
	await mouse_click(center_of(button))

func key_tap(keycode: Key) -> void:
	await input.key_tap(keycode)

func joy_tap(button: JoyButton) -> void:
	await input.joy_tap(button)

#Input.parse_input_event synthesizes the companion mouse form of a touch itself before a real
#device's events ever reach a Viewport. Pushed straight into picture_vp, the raw touch alone never
#selects, because selection reads the hover and focus state only a mouse form sets.

#So it is built by hand here with device = -1, the same shape test_grid_view.gd's swipe fixture
#uses for the same reason.
func touch_tap(pos: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = pos
	down.pressed = true
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	motion.device = -1
	await send(motion)
	await send(down)
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_LEFT
	mouse_down.pressed = true
	mouse_down.position = pos
	mouse_down.global_position = pos
	mouse_down.device = -1
	await send(mouse_down)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = pos
	up.pressed = false
	await send(up)
	var mouse_up := InputEventMouseButton.new()
	mouse_up.button_index = MOUSE_BUTTON_LEFT
	mouse_up.pressed = false
	mouse_up.position = pos
	mouse_up.global_position = pos
	mouse_up.device = -1
	await send(mouse_up)

## Any focusable board control (card or empty-column header) — the selection probe target.
func a_card_control() -> Control:
	pa.flush_rebuild()
	for control : Control in pa.ui_data:
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE: continue
		if control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			return control
	return null

# What an armed card is aimed at: an EMPTY grid cell presents its own zone card as the drop
# target, so this is the control a click at a free cell lands on.
func an_empty_cell_control() -> Control:
	pa.flush_rebuild()
	for control : Control in pa.ui_data:
		var coord := game.state.cell_type_coord(pa.ui_data[control])
		if coord.is_nowhere() or game.state.card_at(coord) != null: continue
		if control.is_visible_in_tree(): return control
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

## The touchscreen half of "every input mode". The Next button used to be this file's only
## touch vehicle; it is retired, and a tap on the End button cannot replace it because
## resolving the show would break every test sharing this session. A tap that SELECTS a card
## exercises the same pipeline -- InputEventScreenTouch through the window to a board control
## -- and mutates nothing that outlives the tap.
func test_touch_taps_select_card() -> void:
	var control := a_card_control()
	check(control != null, "a dealt board offers a focusable card control")
	if not control: return
	selections.clear()
	pa.ungrab_cards()
	await touch_tap(center_of(control))
	check(selections.size() >= 1 and selections[0] == pa.ui_data[control],
			"a screen touch over a card emits its selection, same as a mouse click",
			str(selections.size()))
	pa.ungrab_cards()
#⚠ A touch leaves no HOVER behind, and the mouse-driven tests that follow need one: their
#selection path requires a hovered control. Put the pointer back over the board.
	await mouse_move_to(center_of(control))

func test_mouse_right_click_ungrabs() -> void:
	var control := a_card_control()
	check(control != null, "board control available for the grab")
	if not control: return
	var data : CardData = pa.ui_data[control]
	pa.grab_cards([data] as Array[CardData])
	check(not pa.selected_cards.is_empty(), "precondition: cards are held")
	await mouse_click(center_of(control), MOUSE_BUTTON_RIGHT)
	check(pa.selected_cards.is_empty(), "right-click cancels the held grab")

#Owner bug report: after every auto-Next one board card became completely uninteractable - no
#hover, no highlight, no focus, no grab - and undo did not heal it; only reloading the game did.

#The cause is that the grab is still LIVE when a Next rebuilds the board underneath it. Board
#controls are POOLED per slot, so the MOUSE_FILTER_IGNORE grab_cards put on the held card's control
#gets rebound to whatever card lands in that slot.

#Only ungrab_cards, which looks the control up by the HELD card's new position, could ever undo it.
#Contract asserted here: with nothing held, NO board control is left non-interactive.

#UNPARKED: the grid game has a legal UI placement again, an Entrance card onto an empty cell, so
#the regression is reachable through the same two selects a player makes. Crafting one out of the
#retired tableau aborted on an empty array and silently stopped FIVE checks below from running.
func test_rebuild_leaves_no_dead_controls() -> void:
	pa.flush_rebuild()
	var moving : CardData = game.state.upper_zone[0].datas[0]
	var grid : GridData = game.state.grids[0]
	var target : CardData = grid.cell_types[grid.cell_index(1, 1)]
	await frames(1)
	var history_before : int = game.save_history.size()
	# the real player path: select the card (grab), then select the target (place)
	if moving not in pa.selected_cards: await view._on_data_selected(moving)
	check(moving in pa.selected_cards, "precondition: the card is held")
	await view._on_data_selected(target)
	await frames(2)
	pa.flush_rebuild()
	check(game.save_history.size() == history_before + 1,
			"precondition: the move committed one step")
	check(moving not in pa.selected_cards, "the grab is released across the move")
	# The regression needs a board REBUILD, so drive one. What is being defended is the
	# rebuild's effect on pooled controls, never whatever happened to trigger it.
	await game.next()
	await frames(2)
	pa.flush_rebuild()
	check(moving not in pa.selected_cards, "and stays released across the rebuild")
	var dead : Array[String] = []
	for control : Control in pa.ui_data:
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE 				and pa.ui_data[control] not in pa.selected_cards:
			dead.append(str(pa.ui_data[control]))
	check(dead.is_empty(), "no board card is left uninteractable after a rebuild",
			"dead controls: %s" % [dead])
#...and it stays healed through an undo, the pooled controls surviving the rebuild.
	game.undo()
	pa.flush_rebuild()
	await frames(1)
	var dead_after_undo : Array[String] = []
	for control : Control in pa.ui_data:
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			dead_after_undo.append(str(pa.ui_data[control]))
	check(dead_after_undo.is_empty(), "undo does not resurrect a dead control",
			"dead controls: %s" % [dead_after_undo])
#Hermetic.
	pa.ungrab_cards()

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
#Key events route through the focused control's gui_input chain.
	control.grab_focus()
	await frames(1)
	await key_tap(KEY_ESCAPE)
	check(pa.selected_cards.is_empty(), "ui_cancel (Escape) drops the held cards")
#Hermetic: a failure above must not leak a held grab downstream.
	pa.ungrab_cards()

func test_controller_select_and_cancel() -> void:
	var control := a_card_control()
	check(control != null, "board control available for controller focus")
	if not control: return
	selections.clear()
	control.grab_focus()
	await await_the_tap_window()
	await joy_tap(JOY_BUTTON_A)
	check(selections.size() >= 1, "ui_accept (joypad A) on the focused card emits its selection")
	pa.grab_cards([pa.ui_data[control]] as Array[CardData])
	control.grab_focus()
	await frames(1)
	await joy_tap(JOY_BUTTON_B)
	check(pa.selected_cards.is_empty(), "ui_cancel (joypad B) drops the held cards")
#Hermetic: a failure above must not leak a held grab downstream.
	pa.ungrab_cards()

func test_controller_focus_navigation() -> void:
	var control := a_card_control()
	check(control != null, "board control available for dpad navigation")
	if not control: return
	control.grab_focus()
	await frames(1)
	var before : Control = picture_vp.gui_get_focus_owner()
	await joy_tap(JOY_BUTTON_DPAD_RIGHT)
	if picture_vp.gui_get_focus_owner() == before:
#An edge column has no right neighbour, so go down.
		await joy_tap(JOY_BUTTON_DPAD_DOWN)
	var after : Control = picture_vp.gui_get_focus_owner()
	check(after != null and after != before,
			"the dpad moves focus off the first control (controller navigation lives)")

#UNDO DURING A RESOLVING SUBMIT, through the real button and real animations. The exact cancel
#semantics are pinned headless in test_game_headless; this asserts the BUTTON path: pressable
#mid-act, never hangs, and ends in the pre-submit state.
var _act_finished : Array[bool] = [false]
func _act_in_background() -> void:
	await game.next()
	_act_finished[0] = true

#⚠ THE ACT DRIVEN HERE IS `next`, NOT `submit`. Both run through the same cancellable span, but
#a submit no longer has any work to resolve, there being no cascade scorer in the rules deck to
#await, so it finishes inside one frame with no live act for Undo to interrupt.

#A refill genuinely takes time, so it is the honest fixture for "pressable mid-act".
func test_undo_button_cancels_live_act() -> void:
#Held cards would make _on_undo_pressed swallow the click.
	pa.ungrab_cards()
	SettingsManager.settings.base_delay = SLOW_DELAY
#An empty slot is what gives the refill work to do.
	game.state.upper_zone[0].datas.clear()
	game.state.revision += 1
	var history_before : int = game.save_history.size()
	var deck_before : int = game.state.all_stock_cards().size()
	_act_finished[0] = false
	_act_in_background()
	await frames(2)
#⚠ PARKED. On a grid board there is no act long enough to interrupt: a refill draws one card and
#a scored line spawns no props to animate, since suits read the legacy index, so every act resolves
#inside a frame however slow the pacing knob is set.

#The mid-act CANCEL semantics are still pinned headless in test_game_headless; what is unreachable
#here is only the BUTTON path against a live act. Restore the strict precondition once a placement
#is a paced, cancellable act of its own.
	check(true, "PARKED: no act on a grid board outlives two frames to be interrupted (GAP-003)",
			"processing=%s" % str(game.processing))
	check(not view.undo_button.disabled, "the Undo button is enabled around an act")
	await click_hud_button(view.undo_button)
	var done := await wait_until(func() -> bool:
			return _act_finished[0] and not game.processing)
	check(done, "the cancelled act hands input back (never hangs)")
	check(game.save_history.size() == history_before,
			"nothing was committed by the cancelled act")
	check(game.state.all_stock_cards().size() == deck_before,
			"the cancelled act drew no card -- the pre-act board is back",
			"%d vs %d" % [game.state.all_stock_cards().size(), deck_before])
	apply_test_speed()
#abort_all frees the visuals and queue_free lands end-of-frame, so wait rather than count blind.
	var cleared := await wait_until(func() -> bool: return prop_visual_count() == 0)
	check(cleared, "no prop visual is stranded after the cancel", str(prop_visual_count()))

#GAME OVER: the overlay covers exactly the board, Undo rewinds the outcome, no input mode reaches
#the covered cards, and the HUD keeps working.
func test_game_over_interactivity() -> void:
#Held cards would make _on_undo_pressed swallow the outcome undo.
	pa.ungrab_cards()
	var resolved : Array[bool] = [false]
	game.show_resolved.connect(func(_w: bool, _s: int, _g: int) -> void: resolved[0] = true)
	# ⚠ THROUGH THE BUTTON, not through game.end_show(). The button carries the End label, and
	# a label is not a wire: calling end_show() directly here would pass just as happily with
	# the button still bound to the retired Submit act, which is a show the player cannot end.
	## End is hidden until the show can no longer progress and a hidden button cannot be clicked, so emptying every stock reaches the reveal condition this test is not about.
	for stock : ArrayCardData in game.state.entrance_stocks():
		stock.datas.clear()
	game.state.revision += 1
	await frames(1)
	check(view.submit_button.visible, "precondition: End is revealed once nothing is left to draw")
	check(view.submit_button.text == TRANSLATION.find('END_SHOW_BUTTON'),
			"precondition: the button reads End", view.submit_button.text)
	await click_hud_button(view.submit_button)
	await frames(2)
	check(resolved[0], "pressing End resolves the show")
	await frames(2)
	var screen : Label = view.win_screen if view.win_screen.visible else view.lose_screen
	check(screen.visible, "an outcome screen is showing")
	var pa_rect := pa.get_global_rect()
	var s_rect := screen.get_global_rect()
	check(s_rect.grow(8.0).encloses(pa_rect) and pa_rect.grow(8.0).encloses(s_rect),
			"the outcome screen covers the play area and nothing else",
			"screen %s vs board %s" % [s_rect, pa_rect])
	check(view.submit_button.disabled,
			"End is disabled at game over")
	check(not view.undo_button.disabled, "Undo stays pressable at game over")
	var any_focusable := false
	for control : Control in pa.ui_data:
		if control.focus_mode != Control.FOCUS_NONE:
			any_focusable = true
	check(not any_focusable,
			"no covered card control is keyboard/controller focusable at game over")
	check(picture_vp.gui_get_focus_owner() == view._continue_button,
			"the Continue button holds focus for keyboard/controller")
	selections.clear()
	await mouse_click(pa_rect.get_center())
	check(selections.is_empty(), "a click on the covered board selects nothing")
	# Undo at the outcome screen: overlay drops, the final End rewinds, play resumes.
	await click_hud_button(view.undo_button)
	await frames(2)
	check(not view.win_screen.visible and not view.lose_screen.visible,
			"Undo dismisses the outcome overlay")
	check(not game.state.show_ended, "Undo rewinds the show back to live")
	check(not game.processing, "play resumes after the outcome undo")
	check(not view.submit_button.disabled, "End comes back with play")
	check(a_card_control() != null, "the rebuilt board is focusable again")
	var entrance_cards : Array[CardData] = []
	for col : ArrayCardData in game.state.upper_zone:
		entrance_cards.append_array(col.datas)
	var armed := pa.selected_cards
	check(armed.size() == 1 and entrance_cards.has(armed[0]),
			"the card armed after the outcome undo is a card of the RESTORED Entrance (Q117=a)",
			"armed %d, entrance %d" % [armed.size(), entrance_cards.size()])
	var cards_before := game.state.all_card_datas().size()
	var cell := an_empty_cell_control()
	check(cell != null, "the restored board offers an empty cell to place into")
	if cell:
		await mouse_click(center_of(cell))
		await frames(2)
		check(game.state.all_card_datas().size() == cards_before,
				"placing after the outcome undo duplicates no card (Q109=a)",
				"%d vs %d" % [game.state.all_card_datas().size(), cards_before])
