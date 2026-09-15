extends TestSuite
# res://Tests/Interaction/test_drag_place.gd

# DRAG PLACE: press, drag, release. One gesture model for mouse and finger, on a
# REAL Main -- the wall, its one HudContainer and the game picture -- with every
# event pushed through a real viewport, never a handler call.

# Which gesture a press became is decided at the RELEASE, by how far it travelled.
# CATEGORY MAP: all BEHAVIOR -- every check is "a player pressed, moved, let go,
# and saw Y".

# Ordering: hosts a real Main and writes CardEnvironment.CURRENT / Main.save_info
# / the real save, so it waits for every sibling that hosts one too. It sits
# directly after SIDEBAR in TestSuite's ordering chain; see its DEADLOCK RULE.
const FIXTURE_WINDOW := Vector2i(1280, 720)
## TEST_PLAN 5.1's press-to-release distance: inside any card's own threshold.
const SUB_THRESHOLD_TRAVEL_PX := 10.0
const DEAL_TIMEOUT_SECS := 5.0
## A window wide enough for a PUSHED pair: the frames one spans cost more wall clock than a player.
const PUSHED_PAIR_WINDOW_MS := 2000.0

var _viewport : SubViewport = null
var _main : Main = null
var _view : GameView = null
var _game : Game = null
var _pa : PlayArea = null
var _picture_viewport : SubViewport = null
var _container : HudContainer = null
var _prev_run : RunState = null
var _prev_save_info : RunState = null
## Every card the board reported tapped this test, in order.
var _taps : Array[CardData] = []

func suite_name() -> String:
	return "DRAG PLACE"

func _ready() -> void:
	await await_siblings_except(["SETTINGS RANGE", "E2E RUN", "LEAK CANARY", "WALL PAUSE"])
	TestLog.line("============ DRAG PLACE TEST PASS ============")
	behavior_section("A CLICK AND A DRAG ARE ONE GESTURE")
	await test_a_sub_threshold_release_is_a_click()
	await test_an_over_threshold_release_on_a_legal_cell_places()
	await test_a_release_on_an_illegal_cell_returns_the_card()
	behavior_section("RELEASES THE BOARD DOES NOT OWN")
	await test_a_release_over_the_container_returns_the_card()
	await test_a_cancel_mid_drag_leaves_nothing_for_the_release()
	await test_an_escape_mid_drag_leaves_nothing_for_the_release()
	await test_a_touch_tap_selects_and_lifts_without_placing()
	behavior_section("THE DRAG CHOOSES WHICH CARD IS MOVING")
	await test_a_drag_from_a_board_card_cancels_the_arm()
	await test_a_click_on_a_board_card_tries_to_place_first()
	await test_a_refused_drag_from_an_empty_cell_places_nothing()
	await test_a_refused_drag_from_a_grid_card_places_nothing()
	behavior_section("A TAP IS A SECOND PRESS PAIRED WITH THE FIRST")
	await test_a_double_click_undoes_the_grab_the_first_click_made()
	await test_a_tap_after_a_placement_is_refused()
	await test_a_refused_pairs_release_places_nothing()
	await test_a_touch_tap_after_a_placement_is_refused()
	await test_a_double_click_on_the_armed_card_leaves_the_arm_standing()
	await test_a_double_click_on_an_empty_cells_zone_card_taps()
	await test_a_finger_pairs_its_own_taps()
	await test_a_key_or_pad_reaches_the_tap_two_ways()
	await test_the_second_mouse_button_never_taps()
	await test_the_tap_hook_runs_once_per_tap()
	finish()

# ==============================================================================
# FIXTURE — a real Main on a dealt game screen, one grid focused, per test.
# ==============================================================================

# A board card no shipped rule can pick up or stack onto: the grab answers for its own card only,
# and the placement answers "no" while recording that it was asked. Rides as a STAMP, which the
# dispatch always consults, so the card keeps the type it is drawn from.
class BoardCardRule extends CardModifierStamp:
	var place_attempts : int = 0
	func get_str() -> String: return "Test Board Card Rule"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_can_grab_stack(target: CardData) -> Array[CardData]:
		if target != data: return []
		return [target] as Array[CardData]
	func on_can_place_stack(_stack: Array[CardData], target: CardData) -> Array[CardData]:
		if target != data: return []
		place_attempts += 1
		return []

# THE DUMMY TAP EFFECT, and the only card that hears a tap: it proves the hook is dispatched, and
# is not a mechanic. A stamp, so the card it rides keeps its own type -- and it records the
# tapped card's ID, never the card, which would be a reference cycle neither of them escapes.
class TapSpy extends CardModifierStamp:
	var taps : Array[int] = []
	func get_str() -> String: return "Test Tap Spy"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_card_tapped(tapped: CardData) -> void:
		taps.append(tapped.get_instance_id())

func _record_tap(data: CardData) -> void:
	_taps.append(data)

func _start_fixture() -> void:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	var booted := await TestMainHost.boot(self, FIXTURE_WINDOW)
	_viewport = booted[0]
	_main = booted[1]
	await _main.enter_game()
	_view = _main._pictures[&"game"].screen_root as GameView
	_game = _view.game
	CardEnvironment.CURRENT = _game
	_pa = _view.play_area
	_pa.card_tapped.connect(_record_tap)
	_picture_viewport = _main._pictures[&"game"].viewport
	_container = _main.wall.get_node(^"%HudContainer")
	await _await_the_deal()
	_zoom_into_a_grid()
	await _settle_layout()

func _end_fixture() -> void:
	await TestMainHost.free_booted(_viewport, _main)
	_viewport = null
	_main = null
	_view = null
	_game = null
	_pa = null
	_picture_viewport = null
	_container = null
	_taps.clear()
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = _prev_run
	Main.save_info = _prev_save_info

# ⚠ ZOOM IN FIRST: on the all-grids view a press on a grid is orientation and places nothing, so
# a fixture that skips this proves nothing about a placement.
func _zoom_into_a_grid() -> void:
	_pa.focus_grid(0)

# The deal spawns its card controls frames behind `enter_game()`, and arms one of them, so the
# board is waited FOR rather than slept on. Bounded: a real hang is a bug to surface.
func _await_the_deal() -> void:
	var waited := 0.0
	while waited < DEAL_TIMEOUT_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not _entrance_controls().is_empty() and not _pa.selected_cards.is_empty(): return

# Waits for the Entrance to STOP MOVING: it follows the camera, and a press landing mid-ease races
# the hovered control sliding out from under the cursor.
func _settle_layout() -> void:
	var last := INF
	var waited := 0.0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var now := _pa.entrance_h_track.position.x
		if is_equal_approx(now, last): return
		last = now

func _frames(count: int) -> void:
	for _i : int in count:
		await get_tree().process_frame

# ==============================================================================
# THE BOARD, READ BACK — what the player can see and where it is.
# ==============================================================================

## The Entrance row's own controls, left to right: the row a press can grab from.
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

func _armed_card() -> CardData:
	return _pa.selected_cards[0] if _pa.selected_cards else null

func _control_centre(control: Control) -> Vector2:
	return control.get_global_rect().get_center()

func _card_centre(data: CardData) -> Vector2:
	return _control_centre(_pa.data_ui[data])

## Every card sitting in a grid cell, bottom-to-top: what a placement adds to the board.
func _placed_cards() -> Array[CardData]:
	var out : Array[CardData] = []
	for grid : GridData in _game.state.grids:
		for cell : ArrayCardData in grid.cells:
			out.append_array(cell.datas)
	return out

func _is_following(data: CardData) -> bool:
	return data in _pa.data_card and _pa.data_card[data].following

func _is_lifted(data: CardData) -> bool:
	return data in _pa.data_card and _pa.data_card[data].held > 0

## Why a release did what it did: the whole hand state one line, for a failure's detail.
func _hand_str() -> String:
	var held := _armed_card()
	return "held %d, following %s, lifted %s, armed slot %d, placed %d, undo steps %d" % [
			_pa.selected_cards.size(), _is_following(held) if held else false,
			_is_lifted(held) if held else false, _pa.armed_slot(),
			_placed_cards().size(), _game.save_history.size()]

# A cell the board itself accepts, asked through the same `on_can_place_stack` dispatch `try_place`
# uses, and fully on screen where a real drag can reach it -- no placement rule is spelled out here.
func _legal_cell_control(held: CardData) -> Control:
	var rect := Rect2(Vector2.ZERO, Vector2(_picture_viewport.size))
	var candidates : Array[Control] = []
	for control : Control in _pa.ui_data:
		if not _is_reachable(control, rect): continue
		if _game.state.cell_type_coord(_pa.ui_data[control]).is_nowhere(): continue
		candidates.append(control)
	var stack : Array[CardData] = [held]
	for control : Control in candidates:
		var accepted : Array[CardData] = await _game.return_first_data_array_result(
				&"on_can_place_stack", stack, _pa.ui_data[control])
		if accepted: return control
	return null

# A collapsed cell control has no area, and `encloses` still accepts it, so a release aimed at its
# centre lands on nothing at all.
func _is_reachable(control: Control, on_screen: Rect2) -> bool:
	var drawn := control.get_global_rect()
	return drawn.has_area() and on_screen.encloses(drawn)

# One placement made the way a player makes one -- the armed card dragged onto a cell that accepts
# it -- so the rows that need a card already on the board start from a real one.
func _drag_the_arm_into_the_grid() -> void:
	var held := _armed_card()
	var cell := await _legal_cell_control(held)
	if not cell: return
	await _drag(_card_centre(held), _control_centre(cell))

# INPUT SYNTHESIS -- pushed into the picture's own SubViewport, whose local
# coordinates are the ones every control rect is measured in.
# ==============================================================================

func _push(event: InputEvent, viewport: SubViewport) -> void:
	viewport.push_input(event)
	await get_tree().process_frame

func _mouse_button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event

func _motion(at: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	return event

# Hover, press, then carry the pointer over in two steps: a card starts following on MOTION, so a
# press-then-release with nothing in between is a different gesture entirely.
func _begin_drag(from: Vector2, to: Vector2) -> void:
	await _push(_motion(from), _picture_viewport)
	await _push(_motion(from), _picture_viewport)
	await _push(_mouse_button(from, true), _picture_viewport)
	await _push(_motion(from.lerp(to, 0.5)), _picture_viewport)
	await _push(_motion(to), _picture_viewport)

func _end_drag(at: Vector2) -> void:
	await _push(_mouse_button(at, false), _picture_viewport)
	await _frames(3)

func _drag(from: Vector2, to: Vector2) -> void:
	await _begin_drag(from, to)
	await _end_drag(to)

# A finger, in BOTH forms a real one arrives in, IN THE ENGINE'S OWN ORDER: `Input` dispatches the
# mouse form `emulate_mouse_from_touch` synthesizes (device -1) from a nested parse, BEFORE the
# touch that originated it. Pushed the other way round, a test proves the reader and not the route.
func _touch_tap(at: Vector2) -> void:
	var touch_down := InputEventScreenTouch.new()
	touch_down.index = 0
	touch_down.position = at
	touch_down.pressed = true
	var touch_up := InputEventScreenTouch.new()
	touch_up.index = 0
	touch_up.position = at
	var hover := _motion(at)
	hover.device = -1
	var press := _mouse_button(at, true)
	press.device = -1
	var release := _mouse_button(at, false)
	release.device = -1
	await _push(hover, _picture_viewport)
	await _push(press, _picture_viewport)
	await _push(touch_down, _picture_viewport)
	await _push(release, _picture_viewport)
	await _push(touch_up, _picture_viewport)
	await _frames(3)

# A HELD card's own control is MOUSE_FILTER_IGNORE and the pointer passes straight through it, so
# the key accept on its focused control is how a player reaches the card already in hand.
func _select_the_card_in_hand(data: CardData) -> void:
	await _focus_the_card(data)
	await _press_key(KEY_ENTER)

func _focus_the_card(data: CardData) -> void:
	_pa.flush_rebuild()
	_pa.data_ui[data].grab_focus()
	await get_tree().process_frame

func _press_key(code: Key) -> void:
	await _push(_key(code, true), _picture_viewport)
	await _push(_key(code, false), _picture_viewport)
	await _frames(3)

func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event

# The press the engine marks as a pair's second and the release that closes it: a double click, in
# the two events a real one arrives as.
func _double_click(at: Vector2) -> void:
	var press := _mouse_button(at, true)
	press.double_click = true
	await _push(press, _picture_viewport)
	await _push(_mouse_button(at, false), _picture_viewport)
	await _frames(6)

# The second mouse button, optionally marked as a pair's second -- which is the strictest form of
# "it never taps", and the way a player empties the hand before one.
func _right_click(at: Vector2, paired: bool) -> void:
	var press := _mouse_button(at, true)
	press.button_index = MOUSE_BUTTON_RIGHT
	press.double_click = paired
	var release := _mouse_button(at, false)
	release.button_index = MOUSE_BUTTON_RIGHT
	await _push(press, _picture_viewport)
	await _push(release, _picture_viewport)
	await _frames(4)

# ==============================================================================
# 5.1 – 5.3: THE THRESHOLD, AND WHAT A RELEASE LANDS ON
# ==============================================================================

# 5.1 (E12, E13, Q283=a): a release within a small threshold of its press is a CLICK — it grabs
# the card it landed on and leaves it held, and places nothing.
func test_a_sub_threshold_release_is_a_click() -> void:
	await _start_fixture()
	var entrance := _entrance_controls()
	check(entrance.size() >= 2, "the dealt Entrance offers a card the arm is not already holding",
			"%d control(s)" % entrance.size())
	if entrance.size() >= 2:
		var target := entrance[1]
		var data : CardData = _pa.ui_data[target]
		var threshold := GestureMetrics.drag_threshold_px(target.get_global_rect().size,
				PlayArea.settings())
		var committed := _game.save_history.size()
		var at := _control_centre(target)
		await _drag(at, at + Vector2(SUB_THRESHOLD_TRAVEL_PX, 0.0))
		check(threshold > SUB_THRESHOLD_TRAVEL_PX,
				"a %.0f px release is sub-threshold on this card, whose own threshold is %.1f px (5.1)"
				% [SUB_THRESHOLD_TRAVEL_PX, threshold], "card %s" % target.get_global_rect().size)
		check(_pa.selected_cards.has(data),
				"...so the release GRABBED that card and it stays held (5.1)", _hand_str())
		check(_placed_cards().is_empty() and _game.save_history.size() == committed,
				"...and placed nothing (5.1)", _hand_str())
		check(_pa.locked_data == data and _container.showing_description(),
				"...and locked that card's description, which only a click does (5.1)",
				"locked %s, showing %s" % [_pa.locked_data == data,
						_container.showing_description()])
	await _end_fixture()

# 5.2 (E14, E16, E18): a release beyond the threshold, over a cell the board accepts, places the
# held card there as one ordinary undo step — the same route a click-place takes.
func test_an_over_threshold_release_on_a_legal_cell_places() -> void:
	await _start_fixture()
	var held := _armed_card()
	var cell := await _legal_cell_control(held) if held else null
	check(held != null and cell != null,
			"the show opens with a card armed and a cell that accepts it",
			"held %s, cell %s" % [held != null, cell != null])
	if held and cell:
		var committed := _game.save_history.size()
		await _drag(_card_centre(held), _control_centre(cell))
		check(_placed_cards().has(held), "the release placed the dragged card into the grid (5.2)",
				_hand_str())
		check(_game.save_history.size() == committed + 1,
				"...as exactly one undo step (5.2, E18)",
				"%d -> %d" % [committed, _game.save_history.size()])
		check(not _pa.selected_cards.has(held), "...and the hand let go of it (5.2)", _hand_str())
	await _end_fixture()

# 5.3 (E17, Q280=a, Q281=a): a release over a cell the board refuses returns the card — back in
# its slot, still armed, still lifted, and no longer following. A failed drag costs nothing.
func test_a_release_on_an_illegal_cell_returns_the_card() -> void:
	await _start_fixture()
	await _drag_the_arm_into_the_grid()
	var occupied := _placed_cards()
	var held := _armed_card()
	check(occupied.size() == 1 and held != null,
			"the board offers an occupied cell, with the next Entrance card armed",
			"%d placed, %s" % [occupied.size(), _hand_str()])
	if occupied.size() == 1 and held:
		var committed := _game.save_history.size()
		await _begin_drag(_card_centre(held), _card_centre(occupied[0]))
		check(_is_following(held), "the drag carries the card: it tracks the cursor (5.3)",
				_hand_str())
		await _end_drag(_card_centre(occupied[0]))
		check(_pa.selected_cards.has(held) and _is_lifted(held),
				"...and a refused release leaves it held and lifted (5.3, Q281=a)", _hand_str())
		check(not _is_following(held), "...and no longer following (5.3, Q281=a)", _hand_str())
		check(_pa.armed_slot() != -1 and _game.save_history.size() == committed,
				"...still armed, with nothing committed (5.3)", _hand_str())
	await _end_fixture()

# ==============================================================================
# 5.4 – 5.5: RELEASES THAT ARE NOT PLACEMENTS
# ==============================================================================

# 5.4 (E17, Q288=a): the container is not a placeable spot. The release lands in the WINDOW's own
# viewport, over the container, where a player's would — and the board still hears it and returns
# the card.
func test_a_release_over_the_container_returns_the_card() -> void:
	await _start_fixture()
	var held := _armed_card()
	var cell := await _legal_cell_control(held) if held else null
	check(held != null and cell != null, "the show opens with a card armed and a cell to drag over",
			"held %s, cell %s" % [held != null, cell != null])
	if held and cell:
		var committed := _game.save_history.size()
		await _begin_drag(_card_centre(held), _control_centre(cell))
		check(_is_following(held), "the drag is live before the release (5.4)", _hand_str())
		await _push(_mouse_button(_container.container_rect().get_center(), false), _viewport)
		await _frames(3)
		check(not _is_following(held),
				"the release over the container reached the board and returned the card (5.4)",
				_hand_str())
		check(_pa.selected_cards.has(held) and _is_lifted(held),
				"...still held and still lifted (5.4, Q288=a)", _hand_str())
		check(_placed_cards().is_empty() and _game.save_history.size() == committed,
				"...and nothing was placed (5.4)", _hand_str())
	await _end_fixture()

# The second mouse button mid-drag: the release that closes the cancelled gesture must reach the
# board with nothing to place, so no drop is ever reported for a card the player let go of.
func test_a_cancel_mid_drag_leaves_nothing_for_the_release() -> void:
	await _check_a_cancelled_drag_places_nothing(false)

# Escape mid-drag does everything the second button would, and the release closing that gesture
# must be just as empty -- the wall is transitioning out while it arrives.
func test_an_escape_mid_drag_leaves_nothing_for_the_release() -> void:
	await _check_a_cancelled_drag_places_nothing(true)

# A CANCEL ENDS THE PRESS AS WELL AS THE HOLD (Q99=b, Q100=c, Q281=a): the drag is cancelled in
# flight and the button then released over a cell the board accepts, which is the one release that
# could still place a card nobody is holding.
func _check_a_cancelled_drag_places_nothing(by_escape: bool) -> void:
	await _start_fixture()
	var held := _armed_card()
	var cell := await _legal_cell_control(held) if held else null
	check(held != null and cell != null, "the show opens with a card armed and a cell that accepts it",
			"held %s, cell %s" % [held != null, cell != null])
	if held and cell:
		var drops : Array[CardData] = []
		_pa.card_dropped.connect(func(dropped: CardData) -> void: drops.append(dropped))
		var committed := _game.save_history.size()
		var at := _control_centre(cell)
		await _begin_drag(_card_centre(held), at)
		check(_is_following(held), "the drag is live before the cancel", _hand_str())
		if by_escape: await _escape_press()
		else: await _right_click(at, false)
		await _end_drag(at)
		check(drops.is_empty(), "the release closing a cancelled drag drops nothing (Q99=b, Q100=c)",
				"%d drop(s)" % drops.size())
		check(_placed_cards().is_empty() and _game.save_history.size() == committed,
				"...so the board places nothing and commits no step (Q281=a)", _hand_str())
		check(_pa.selected_cards.is_empty() and not _is_following(held),
				"...and the cancelled card is in its slot, held by nothing", _hand_str())
	await _end_fixture()

# Escape reaches the board the way a player's does: through the ROOT viewport, where the wall reads
# its own step back out of the screen from the same press.
func _escape_press() -> void:
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	await _push(cancel, _viewport)
	await _frames(3)

# 5.5 (E24, Q285=b): a touch TAP needs no threshold of its own. It selects and lifts the card it
# lands on, places nothing — and a second tap on the card already held leaves it held.
func test_a_touch_tap_selects_and_lifts_without_placing() -> void:
	await _start_fixture()
	var entrance := _entrance_controls()
	check(entrance.size() >= 2, "the dealt Entrance offers a card the arm is not already holding",
			"%d control(s)" % entrance.size())
	if entrance.size() >= 2:
		var data : CardData = _pa.ui_data[entrance[1]]
		var committed := _game.save_history.size()
		await _touch_tap(_control_centre(entrance[1]))
		check(_pa.selected_cards.has(data) and _is_lifted(data),
				"a tap selects the card it lands on and lifts it (5.5)", _hand_str())
		check(_placed_cards().is_empty() and _game.save_history.size() == committed,
				"...and places nothing, charging nothing (5.5)", _hand_str())
		await _select_the_card_in_hand(data)
		check(_pa.selected_cards.has(data) and _is_lifted(data),
				"...and selecting the card already in hand leaves it held (5.5, E24)", _hand_str())
	await _end_fixture()

# ==============================================================================
# 5.6 – 5.7: A BOARD CARD, WITH THE ENTRANCE ARMED
# ==============================================================================

# Both board-card rows start from the same board: one card placed the way a player places it, the
# next Entrance card armed, and the placed card wearing a rule the shipped deck has none of.
func _a_board_card_wearing(rule: BoardCardRule) -> CardData:
	await _start_fixture()
	await _drag_the_arm_into_the_grid()
	var placed := _placed_cards()
	check(placed.size() == 1 and _armed_card() != null,
			"a board card is on the grid, with the next Entrance card armed",
			"%d placed, %s" % [placed.size(), _hand_str()])
	if placed.size() != 1: return null
	return placed[0].with_stamp(rule)

# 5.6 (E10, E11, Q286=b): a drag is unambiguous about which card is being moved, so dragging a
# board card cancels the arm implicitly — the board card is the one held, and the one following.
func test_a_drag_from_a_board_card_cancels_the_arm() -> void:
	var board_card := await _a_board_card_wearing(BoardCardRule.new())
	var armed := _armed_card()
	if board_card and armed:
		var cell := await _legal_cell_control(armed)
		await _begin_drag(_card_centre(board_card), _control_centre(cell))
		check(_pa.selected_cards.has(board_card),
				"the drag picked the board card up (5.6, E10)", _hand_str())
		check(not _pa.selected_cards.has(armed),
				"...and the Entrance card it was holding is disarmed (5.6, Q286=b)", _hand_str())
		check(_is_following(board_card),
				"...and the board card is the one tracking the cursor (5.6, Q287=a)", _hand_str())
		await _end_drag(_control_centre(cell))
	await _end_fixture()

# 5.7 (E8, the Q122 note): a CLICK on a board card still tries to place the armed card onto it
# first; because it does not stack, the only action left is the grab, and that happens straight
# away (E9).
func test_a_click_on_a_board_card_tries_to_place_first() -> void:
	var rule := BoardCardRule.new()
	var board_card := await _a_board_card_wearing(rule)
	var armed := _armed_card()
	if board_card and armed:
		var committed := _game.save_history.size()
		var at := _card_centre(board_card)
		await _drag(at, at)
		check(rule.place_attempts >= 1,
				"the click asked the board card to take the armed card first (5.7, E8)",
				"%d attempt(s)" % rule.place_attempts)
		check(_pa.selected_cards.has(board_card) and not _pa.selected_cards.has(armed),
				"...and since it does not stack, the grab happens straight away (5.7, E9)",
				_hand_str())
		check(_placed_cards().size() == 1 and _game.save_history.size() == committed,
				"...with nothing placed onto it (5.7)", _hand_str())
	await _end_fixture()

# Only the card a drag carries can be placed by its release. One that starts on an empty cell's
# zone card, which no rule picks up, carries nothing, so the armed card must not land instead.
func test_a_refused_drag_from_an_empty_cell_places_nothing() -> void:
	await _start_fixture()
	var armed := _armed_card()
	var cell := await _legal_cell_control(armed) if armed else null
	var source := _an_empty_cell_other_than(cell)
	check(cell != null and source != null, "the board offers two empty cells with a card armed",
			"cell %s, source %s, %s" % [cell != null, source != null, _hand_str()])
	if cell and source:
		await _check_a_refused_drag_places_nothing(_control_centre(source), armed, cell)
	await _end_fixture()

# The same drag from a card already in the grid, which no shipped rule picks up.
func test_a_refused_drag_from_a_grid_card_places_nothing() -> void:
	await _start_fixture()
	await _drag_the_arm_into_the_grid()
	var placed := _placed_cards()
	var armed := _armed_card()
	var cell := await _legal_cell_control(armed) if armed else null
	check(placed.size() == 1 and cell != null,
			"a card is on the grid, the next Entrance card armed, and a cell accepts it",
			"%d placed, cell %s, %s" % [placed.size(), cell != null, _hand_str()])
	if placed.size() == 1 and cell:
		await _check_a_refused_drag_places_nothing(_card_centre(placed[0]), armed, cell)
	await _end_fixture()

# A fully on-screen empty cell a drag can start from, which is not the one it is released on.
func _an_empty_cell_other_than(excluded: Control) -> Control:
	var rect := Rect2(Vector2.ZERO, Vector2(_picture_viewport.size))
	for control : Control in _pa.ui_data:
		if control == excluded or not _is_reachable(control, rect): continue
		var coord := _game.state.cell_type_coord(_pa.ui_data[control])
		if not coord.is_nowhere() and _game.state.card_at(coord) == null: return control
	return null

# A card that does not place goes back: the release of a drag whose pickup the board refused drops
# nothing, commits nothing, and leaves the armed card held in its Entrance slot.
func _check_a_refused_drag_places_nothing(from: Vector2, armed: CardData, cell: Control) -> void:
	var drops : Array[CardData] = []
	_pa.card_dropped.connect(func(dropped: CardData) -> void: drops.append(dropped))
	var committed := _game.save_history.size()
	var placed := _placed_cards().size()
	await _drag(from, _control_centre(cell))
	check(drops.is_empty(), "the release of a refused pickup drops nothing (Q280=a)",
			"%d drop(s)" % drops.size())
	check(_game.save_history.size() == committed and _placed_cards().size() == placed,
			"...so the board commits no step (Q280=a)", _hand_str())
	check(_pa.selected_cards.has(armed) and _is_in_the_entrance(armed),
			"...and the armed card is still held in its slot (Q281=a)", _hand_str())

func _is_in_the_entrance(data: CardData) -> bool:
	for slot : ArrayCardData in _game.state.upper_zone:
		if data in slot.datas: return true
	return false

# ==============================================================================
# THE TAP — a second press paired with the first, on every input a player has
# ==============================================================================

# Q92=a, Q93a=a: the pair's first click GRABS, and the tap undoes exactly that — the card is back
# in its slot, following nothing, and the board hears the tap once.
func test_a_double_click_undoes_the_grab_the_first_click_made() -> void:
	await _start_fixture()
	var entrance := _entrance_controls()
	check(entrance.size() >= 2, "the dealt Entrance offers a card the arm is not already holding",
			"%d control(s)" % entrance.size())
	if entrance.size() >= 2:
		var data : CardData = _pa.ui_data[entrance[1]]
		var at := _control_centre(entrance[1])
		await _drag(at, at)
		check(_pa.selected_cards.has(data), "the pair's first click grabbed that card", _hand_str())
		await _double_click(at)
		check(_taps.size() == 1 and _taps.has(data), "the second press taps it, once (Q92=a)",
				"%d tap(s)" % _taps.size())
		check(not _pa.selected_cards.has(data) and not _is_lifted(data),
				"...and the grab it undid puts the card back in its slot (Q92=a)", _hand_str())
		check(not _is_following(data), "...where it follows nothing (Q92=a)", _hand_str())
	await _end_fixture()

# Q93a=a: a placement is never rewound by a double click. The pair's first click placed a card, so
# the second is refused outright — no signal, no hook, nothing given back.
func test_a_tap_after_a_placement_is_refused() -> void:
	await _start_fixture()
	var spy := TapSpy.new()
	var held := _armed_card()
	var cell := await _cell_the_arm_can_be_placed_on(held, spy)
	if held and cell:
		var at := _control_centre(cell)
		await _drag(at, at)
		var committed := _game.save_history.size()
		check(_placed_cards().has(held), "the pair's first click placed the armed card", _hand_str())
		var selections := _spy_on_selections()
		await _double_click(at)
		_check_the_placement_stands_untapped(spy, held, committed, selections)
	await _end_fixture()

# A REFUSED pair must give its closing release back to nobody: a real mouse puts a motion between
# the two clicks, which refreshes the hover the GUI pass reads, and the release would otherwise
# land as an ordinary click and place the card the placement just armed.
func test_a_refused_pairs_release_places_nothing() -> void:
	await _start_fixture()
	var spy := TapSpy.new()
	var held := _armed_card()
	var cell := await _cell_the_arm_can_be_placed_on(held, spy)
	if held and cell:
		var at := _control_centre(cell)
		await _drag(at, at)
		var committed := _game.save_history.size()
		var next_arm := _armed_card()
		check(_placed_cards().has(held) and next_arm != held,
				"the pair's first click placed the armed card and the next one armed", _hand_str())
		await _push(_motion(at + Vector2.RIGHT), _picture_viewport)
		var selections := _spy_on_selections()
		await _double_click(at)
		_check_the_placement_stands_untapped(spy, held, committed, selections)
		check(next_arm != null and not _placed_cards().has(next_arm),
				"...and the card it armed is still in the Entrance", _hand_str())
	await _end_fixture()

# Q93a=a REACHED BY A FINGER: the pair's first finger press placed the armed card, so the second is
# refused exactly as the mouse's is — the emulated mouse form of that second press, which the
# engine dispatches BEFORE the touch, must not move the depth the refusal reads.
func test_a_touch_tap_after_a_placement_is_refused() -> void:
	await _start_fixture()
	var spy := TapSpy.new()
	var held := _armed_card()
	var cell := await _cell_the_arm_can_be_placed_on(held, spy)
	if held and cell:
		var at := _control_centre(cell)
		var window := PlayArea.settings().card_tap_window_ms
		PlayArea.settings().card_tap_window_ms = PUSHED_PAIR_WINDOW_MS
		await _touch_tap(at)
		var committed := _game.save_history.size()
		check(_placed_cards().has(held), "the pair's first finger press placed the armed card",
				_hand_str())
		var selections := _spy_on_selections()
		await _touch_tap(at)
		_check_the_placement_stands_untapped(spy, held, committed, selections)
		PlayArea.settings().card_tap_window_ms = window
	await _end_fixture()

# The board a refusal row starts from: an armed card wearing the hook spy, and a cell that accepts
# it, so the pair's first press has a real placement to make.
func _cell_the_arm_can_be_placed_on(held: CardData, spy: TapSpy) -> Control:
	var cell := await _legal_cell_control(held) if held else null
	check(held != null and cell != null,
			"the show opens with a card armed and a cell that accepts it",
			"held %s, cell %s" % [held != null, cell != null])
	if held and cell: held.with_stamp(spy)
	return cell

# Everything the board selects from here on, so a row can prove a closing release gave the GUI pass
# nothing to place with.
func _spy_on_selections() -> Array[CardData]:
	var selections : Array[CardData] = []
	_pa.data_selected.connect(func(d: CardData) -> void: selections.append(d))
	return selections

# What a refusal looks like from outside, for either input: no signal, no hook, no selection, and
# the placement the pair's first press made still standing.
func _check_the_placement_stands_untapped(spy: TapSpy, held: CardData, committed: int,
		selections: Array[CardData]) -> void:
	check(_taps.is_empty(), "the pair's second press taps nothing (Q93a=a)",
			"%d tap(s)" % _taps.size())
	check(selections.is_empty(), "the refused pair's closing release is not a click (Q93a=a)",
			"%d selection(s)" % selections.size())
	check(spy.taps.is_empty(), "...so no card hears one either (Q222=b)",
			"%d hook call(s)" % spy.taps.size())
	check(_placed_cards().has(held) and _game.save_history.size() == committed,
			"...and the placement stands, unrewound (Q93a=a)", _hand_str())

# Q94=a: double-clicking the card the Entrance armed taps it and the arm STANDS — the same slot is
# armed, its card lifted in place, following nothing.
func test_a_double_click_on_the_armed_card_leaves_the_arm_standing() -> void:
	await _start_fixture()
	var armed := _armed_card()
	var slot := _pa.armed_slot()
	check(armed != null and slot != -1, "the show opens with the leftmost Entrance card armed",
			_hand_str())
	if armed:
		var at := _card_centre(armed)
		await _drag(at, at)
		await _double_click(at)
		check(_taps.size() == 1 and _taps.has(armed), "the pair taps the armed card (Q94=a)",
				"%d tap(s)" % _taps.size())
		check(_pa.armed_slot() == slot and _pa.selected_cards.has(armed),
				"...and the arm stands on the same slot (Q94=a)", _hand_str())
		check(_is_lifted(armed) and not _is_following(armed),
				"...lifted, and following nothing (Q94=a)", _hand_str())
	await _end_fixture()

# Q97=b: an empty cell's zone card taps like any other card, because a cell can carry modifiers
# too. The hand is emptied first, so the pair's first click has nothing to place.
func test_a_double_click_on_an_empty_cells_zone_card_taps() -> void:
	await _start_fixture()
	var held := _armed_card()
	var cell := await _legal_cell_control(held) if held else null
	check(cell != null, "the board offers an empty cell the armed card could have gone into",
			"cell %s" % [cell != null])
	if cell:
		var zone_card : CardData = _pa.ui_data[cell]
		var at := _control_centre(cell)
		await _right_click(at, false)
		check(_pa.selected_cards.is_empty(), "the hand is empty before the pair", _hand_str())
		await _drag(at, at)
		await _double_click(at)
		check(_taps.size() == 1 and _taps.has(zone_card),
				"the pair taps the empty cell's own zone card (Q97=b)", "%d tap(s)" % _taps.size())
		check(_placed_cards().is_empty(), "...and places nothing on the way (Q97=b)", _hand_str())
	await _end_fixture()

# Q95=a, Q96=b: Godot never marks a double tap on a Windows touchscreen, so the board pairs two
# finger presses itself — inside the tap window, and no further apart than the drag threshold.
func test_a_finger_pairs_its_own_taps() -> void:
	await _start_fixture()
	var entrance := _entrance_controls()
	check(entrance.size() >= 3, "the dealt Entrance offers three cards to a finger",
			"%d control(s)" % entrance.size())
	if entrance.size() >= 3:
		var data : CardData = _pa.ui_data[entrance[1]]
		var near := _control_centre(entrance[1])
		var far := _control_centre(entrance[2])
		var window := PlayArea.settings().card_tap_window_ms
		PlayArea.settings().card_tap_window_ms = PUSHED_PAIR_WINDOW_MS
		await _touch_tap(near)
		await _touch_tap(near)
		check(_taps.size() == 1 and _taps.has(data),
				"two finger presses inside the window, on one spot, are a tap (Q95=a)",
				"%d tap(s)" % _taps.size())
		await _touch_tap(far)
		check(_taps.size() == 1, "...a press a whole card away from the last one is not (Q96=b)",
				"%d tap(s)" % _taps.size())
		PlayArea.settings().card_tap_window_ms = window
		await _touch_tap(near)
		await await_the_tap_window()
		await _touch_tap(near)
		check(_taps.size() == 1,
				"...and two presses on one spot, further apart than the window, are not (Q96=b)",
				"%d tap(s)" % _taps.size())
	await _end_fixture()

# Q98=d: a keyboard or pad reaches the tap two ways — the bound action on the focused card, and two
# accept presses inside the window. One accept on its own still does what it always did.
func test_a_key_or_pad_reaches_the_tap_two_ways() -> void:
	await _start_fixture()
	var entrance := _entrance_controls()
	check(entrance.size() >= 2, "the dealt Entrance offers a card the arm is not already holding",
			"%d control(s)" % entrance.size())
	if entrance.size() >= 2:
		var data : CardData = _pa.ui_data[entrance[1]]
		await _focus_the_card(data)
		await _press_key(KEY_ENTER)
		check(_taps.is_empty() and _pa.selected_cards.has(data),
				"one accept press grabs the focused card and taps nothing (Q98=d)", _hand_str())
		await await_the_tap_window()
		await _focus_the_card(data)
		await _press_key(KEY_T)
		check(_taps.size() == 1 and _taps.has(data),
				"the bound tap action taps the focused card (Q98=d)", "%d tap(s)" % _taps.size())
		await _focus_the_card(data)
		await _press_key(KEY_ENTER)
		await _focus_the_card(data)
		await _press_key(KEY_ENTER)
		check(_taps.size() == 2, "...and two accept presses inside the window are one too (Q98=d)",
				"%d tap(s)" % _taps.size())
	await _end_fixture()

# F9: the second mouse button is cancel-only. It never taps, not even as a pair's second press.
func test_the_second_mouse_button_never_taps() -> void:
	await _start_fixture()
	var entrance := _entrance_controls()
	check(entrance.size() >= 2, "the dealt Entrance offers a card to press",
			"%d control(s)" % entrance.size())
	if entrance.size() >= 2:
		var at := _control_centre(entrance[1])
		await _drag(at, at)
		await _right_click(at, false)
		await _right_click(at, true)
		check(_taps.is_empty(), "the second mouse button taps nothing (F9)",
				"%d tap(s)" % _taps.size())
		check(_pa.selected_cards.is_empty(), "...it cancels the grab, which is all it does (F9)",
				_hand_str())
	await _end_fixture()

# Q161=c, Q222=b: ONE dummy effect, and it exists to prove the hook is dispatched — once per tap,
# through the same broadcast every other card hook arrives on.
func test_the_tap_hook_runs_once_per_tap() -> void:
	await _start_fixture()
	var entrance := _entrance_controls()
	check(entrance.size() >= 2, "the dealt Entrance offers a card to wear the dummy effect",
			"%d control(s)" % entrance.size())
	if entrance.size() >= 2:
		var spy := TapSpy.new()
		var data : CardData = _pa.ui_data[entrance[1]]
		data.with_stamp(spy)
		var at := _control_centre(entrance[1])
		await _drag(at, at)
		await _double_click(at)
		check(_taps.size() == 1, "the pair tapped the card wearing the dummy effect (Q222=b)",
				"%d tap(s)" % _taps.size())
		check(spy.taps.size() == 1 and spy.taps.has(data.get_instance_id()),
				"...and its hook ran once, with the tapped card (Q222=b)",
				"%d hook call(s)" % spy.taps.size())
	await _end_fixture()
