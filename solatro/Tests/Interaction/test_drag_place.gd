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

var _viewport : SubViewport = null
var _main : Main = null
var _view : GameView = null
var _game : Game = null
var _pa : PlayArea = null
var _picture_viewport : SubViewport = null
var _container : HudContainer = null
var _prev_run : RunState = null
var _prev_save_info : RunState = null

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
	await test_a_touch_tap_selects_and_lifts_without_placing()
	behavior_section("THE DRAG CHOOSES WHICH CARD IS MOVING")
	await test_a_drag_from_a_board_card_cancels_the_arm()
	await test_a_click_on_a_board_card_tries_to_place_first()
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
		if not rect.encloses(control.get_global_rect()): continue
		if _game.state.cell_type_coord(_pa.ui_data[control]).is_nowhere(): continue
		candidates.append(control)
	var stack : Array[CardData] = [held]
	for control : Control in candidates:
		var accepted : Array[CardData] = await _game.return_first_data_array_result(
				&"on_can_place_stack", stack, _pa.ui_data[control])
		if accepted: return control
	return null

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

# A finger, in BOTH forms a real one arrives in: the touch itself, and the mouse form
# `emulate_mouse_from_touch` synthesizes from it (device -1), which is the one the board reads.
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
	await _push(touch_down, _picture_viewport)
	await _push(press, _picture_viewport)
	await _push(touch_up, _picture_viewport)
	await _push(release, _picture_viewport)
	await _frames(3)

# A HELD card's own control is MOUSE_FILTER_IGNORE and the pointer passes straight through it, so
# the key accept on its focused control is how a player reaches the card already in hand.
func _select_the_card_in_hand(data: CardData) -> void:
	_pa.data_ui[data].grab_focus()
	await get_tree().process_frame
	await _push(_accept_key(true), _picture_viewport)
	await _push(_accept_key(false), _picture_viewport)
	await _frames(3)

func _accept_key(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = pressed
	return event

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
