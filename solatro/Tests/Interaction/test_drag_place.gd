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
## Higher than a real deck can score in a handful of placements, so no row's placement trips the goal's own automatic end.
const GOAL_OUT_OF_REACH : int = 100000000
## A window wide enough for a PUSHED pair: the frames one spans cost more wall clock than a player.
const PUSHED_PAIR_WINDOW_MS := 2000.0
## How far either side of a card's drag threshold a release lands: past float noise, well inside a zoom's change to it.
const THRESHOLD_MARGIN_PX := 2.0
## The picture's own top-left corner, where the board lays out no cell and no card.
const BARE_BOARD_CORNER_PX := 24.0
## How far past the picture's far corner a release lands to be off the window altogether.
const OFF_WINDOW_PX := 80.0

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
	check_all_tests_registered()
	behavior_section("NOTHING IS HELD UNTIL THE PLAYER ACTS")
	await test_the_show_opens_with_nothing_held()
	await test_a_placement_leaves_nothing_held()
	await test_a_click_lifts_the_card_without_following()
	await test_a_click_on_a_legal_cell_places_the_lifted_card()
	behavior_section("A CLICK AND A DRAG ARE ONE GESTURE")
	await test_a_sub_threshold_release_is_a_click()
	await test_an_over_threshold_release_on_a_legal_cell_places()
	await test_the_drag_threshold_follows_the_boards_zoom()
	await test_a_release_on_an_illegal_cell_drops_the_card()
	await test_a_lifted_card_follows_only_on_a_new_press_with_travel()
	behavior_section("RELEASES THE BOARD DOES NOT OWN")
	await test_a_release_over_the_container_drops_the_card()
	await test_a_release_away_from_the_cells_drops_the_card()
	await test_an_act_with_the_card_ends_its_lock_and_its_focus()
	await test_a_rebuild_under_the_outcome_overlay_rests_on_nothing()
	await test_a_cancel_mid_drag_leaves_nothing_for_the_release()
	await test_an_escape_mid_drag_leaves_nothing_for_the_release()
	await test_a_touch_tap_selects_and_lifts_without_placing()
	behavior_section("THE DRAG CHOOSES WHICH CARD IS MOVING")
	await test_a_drag_from_a_board_card_drops_the_lifted_card()
	await test_a_click_on_a_board_card_tries_to_place_first()
	await test_a_refused_drag_from_an_empty_cell_places_nothing()
	await test_a_refused_drag_from_a_grid_card_places_nothing()
	behavior_section("A TAP IS A SECOND PRESS PAIRED WITH THE FIRST")
	await test_a_double_click_undoes_the_grab_the_first_click_made()
	await test_a_tap_after_a_placement_is_refused()
	await test_a_refused_pairs_release_places_nothing()
	await test_a_touch_tap_after_a_placement_is_refused()
	await test_a_double_click_on_an_empty_cells_zone_card_taps()
	await test_a_finger_pairs_its_own_taps()
	await test_a_key_or_pad_reaches_the_tap_two_ways()
	await test_the_second_mouse_button_never_taps()
	await test_the_tap_hook_runs_once_per_tap()
	behavior_section("ONLY A PLACEMENT TAKES THE ENTRANCE UNDER A GRID")
	await test_a_pickup_leaves_the_entrance_centred_until_a_placement_takes_it()
	await test_a_drag_pickup_aims_at_the_grid_nearest_the_window_centre()
	await test_the_entrance_slide_survives_the_picture_being_left()
	behavior_section("A USED-UP ENTRANCE FREES THE COMMITTED GRID")
	await test_a_used_up_entrance_frees_the_commitment()
	await test_a_one_grid_show_commits_as_it_opens()
	await test_a_one_grid_commitment_survives_a_used_up_entrance()
	behavior_section("A DRAG PAN NEEDS THE BUTTON HELD, AND ENDS ON A GRID")
	await test_a_drag_pan_needs_the_button_held()
	await test_a_cancel_ends_a_latched_drag_pan()
	await test_a_cancel_that_steps_out_lands_first_and_is_superseded()
	await test_a_drag_pan_release_lands_on_the_grid_nearest_the_centre()
	await test_a_drag_pan_release_focuses_an_entrance_card()
	await test_a_key_pan_leaves_the_focus_where_it_was()
	behavior_section("THE CANCEL LADDER STEPS OUT ONE LEVEL PER PRESS")
	await test_the_second_button_cancels_one_rung_per_press()
	await test_an_escape_with_something_to_spend_still_reaches_the_wall()
	await test_an_escape_with_nothing_to_spend_steps_out_of_the_grid_first()
	await test_a_one_grid_board_has_no_grid_to_step_out_of()
	behavior_section("THE KEYS ALONE CARRY A CARD FROM THE ENTRANCE TO THE GRID")
	await test_the_keys_reach_the_entrance_and_come_back()
	await test_the_keys_alone_lift_place_and_cancel()
	await test_up_with_a_card_in_hand_stays_on_the_board()
	await test_down_with_a_card_in_hand_moves_nothing()
	await test_down_under_another_grid_carries_the_view_to_the_entrance()
	await test_a_lift_and_a_quick_placement_never_pair_into_a_tap()
	behavior_section("EVERY FOCUSED CARD WEARS ONE RIM")
	await test_a_focused_entrance_card_wears_the_rim_a_focused_cell_does()
	behavior_section("A PLACEMENT ONTO THE FOCUSED CELL MOVES ITS RIM ONTO THE CARD")
	await test_a_click_placement_onto_the_focused_cell_rims_the_card()
	await test_a_drag_placement_onto_the_focused_cell_rims_the_card()
	await test_a_key_placement_onto_the_focused_cell_rims_the_card()
	await test_an_undo_hands_the_focused_cells_rim_back_to_its_mark()
	await test_a_removed_top_card_hands_the_rim_back_to_its_mark()
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
	run.pending_goal = GOAL_OUT_OF_REACH
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
	check(not _game.state.show_ended, "the row's placements left the show running",
			str(_game.state.total_score))
	await TestMainHost.free_booted(self, _viewport, _main)
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

# The deal spawns its card controls frames behind `enter_game()`, so the board is waited FOR rather
# than slept on. Bounded: a real hang is a bug to surface.
func _await_the_deal() -> void:
	var waited := 0.0
	while waited < DEAL_TIMEOUT_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not _entrance_controls().is_empty() and not _game.processing: return

# Waits for the board AND the Entrance to STOP MOVING; never a frame count, both are DURATIONS.
# ⚠ THE SCROLL IS PART OF "SETTLED": an uncommitted Entrance never moves, so waiting on its x alone
# returns on the first frame and hands back a board still panning.
func _settle_layout() -> void:
	var last := Vector3.INF
	var waited := 0.0
	while waited < 2.0:
		await get_tree().physics_frame
		await get_tree().process_frame
		waited += get_process_delta_time()
		if _pa._view_ease < 1.0: continue
		var now := Vector3(_pa.entrance_h_track.position.x, _pa._entrance_slide,
				_pa.top_level_vbox.global_position.x)
		if now.is_equal_approx(last): return
		last = now

func _frames(count: int) -> void:
	for _i : int in count:
		await get_tree().process_frame

# The one-grid fixture grown to `n` grids and re-opened on the view a show of that size opens on.
# The shipped one-deal show never grows mid-board, so the opening view is re-run by its own entry
# point rather than left latched on the count the deal had.
func _start_fixture_grids(n: int) -> void:
	await _start_fixture()
	while _game.state.grids.size() < n:
		Board.add_grid(_game.state, GridData.new())
#⚠ THE ONE-GRID DEAL ALREADY COMMITTED ITS GRID (nothing to choose); a dealt board of two or more
#commits nothing until a placement, and that is the board these rows are about.
	if n > 1: _game.state.committed_grid = -1
	_pa.flush_rebuild()
	_pa.open_show_view()
	await _settle_layout()

#⚠ `global_position` CARRIES EVERY SCALE ABOVE IT AND `size` CARRIES NONE, so a zoomed board needs
#the transform's own scale rather than the control's size.

## A control's centre AS DRAWN, in the picture's own pixels.
func _drawn_centre_x(c: Control) -> float:
	var t := c.get_global_transform()
	return t.origin.x + t.get_scale().x * c.size.x * 0.5

## The grid nearest the middle of the board's window, off the DRAWN rects: the test's own answer.
func _nearest_drawn_grid() -> int:
	var centre := _drawn_centre_x(_pa.scroll_container)
	var best := -1
	var best_dx := INF
	for gi : int in _pa.grid_container.get_child_count():
		var dx := absf(_drawn_centre_x(_pa._cells_root(
				_pa.grid_container.get_child(gi) as Control)) - centre)
		if dx >= best_dx: continue
		best_dx = dx
		best = gi
	return best

## How far the Entrance's row is from grid `gi`'s columns, drawn; 0 means it sits under that grid.
func _entrance_off_grid_px(gi: int) -> float:
	return absf(_drawn_centre_x(_pa.upper_zone_right) - _drawn_centre_x(_pa._cells_root(
			_pa.grid_container.get_child(gi) as Control)))

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

func _held_card() -> CardData:
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
	var held := _held_card()
	return "held %d, following %s, lifted %s, leftmost slot %d, placed %d, undo steps %d" % [
			_pa.selected_cards.size(), _is_following(held) if held else false,
			_is_lifted(held) if held else false, TestGridFixtures.leftmost_entrance_slot(),
			_placed_cards().size(), _game.save_history.size()]

# A cell on the board's own drop map, fully on screen where a real drag can reach it -- no
# placement rule is spelled out here.
func _legal_cell_control(held: CardData) -> Control:
	var legal := await _game.legal_cells_for([held] as Array[CardData], _game.state.grids)
	for control : Control in _reachable_cells():
		if _pa.ui_data[control] in legal: return control
	return null

# ⚠ "REACHABLE" IS THE WHOLE PICTURE, NOT THE BOARD'S WINDOW, so on a multi-grid board a cell of a
# NEIGHBOUR can answer `_legal_cell_control`. A row about which grid a placement commits to has to
# name the grid it places into.
func _legal_cell_control_in_grid(held: CardData, gi: int) -> Control:
	var legal := await _game.legal_cells_for([held] as Array[CardData], _game.state.grids)
	for control : Control in _reachable_cells():
		var data : CardData = _pa.ui_data[control]
		if data in legal and _game.state.cell_type_coord(data).grid == gi: return control
	return null

# Every grid cell control fully on screen, where a real drag can reach it.
func _reachable_cells() -> Array[Control]:
	var rect := Rect2(Vector2.ZERO, Vector2(_picture_viewport.size))
	var cells : Array[Control] = []
	for control : Control in _pa.ui_data:
		if not _is_reachable(control, rect): continue
		if _game.state.cell_type_coord(_pa.ui_data[control]).is_nowhere(): continue
		cells.append(control)
	return cells

# A collapsed cell control has no area, and `encloses` still accepts it, so a release aimed at its
# centre lands on nothing at all.
func _is_reachable(control: Control, on_screen: Rect2) -> bool:
	var drawn := control.get_global_rect()
	return drawn.has_area() and on_screen.encloses(drawn)

# One placement made the way a player makes one -- the leftmost Entrance card dragged onto a cell
# that accepts it -- so the rows that need a card already on the board start from a real one.
func _drag_a_card_into_the_grid() -> void:
	var entrance := _entrance_controls()
	if entrance.is_empty(): return
	var data : CardData = _pa.ui_data[entrance[0]]
	var cell := await _legal_cell_control(data)
	if not cell: return
	await _drag(_control_centre(entrance[0]), _control_centre(cell))

# One card lifted the way a player lifts one: a click -- a press and a release inside the card's
# own drag threshold -- on the leftmost Entrance card. Hands back the card now in hand.
func _lift_the_leftmost() -> CardData:
	var entrance := _entrance_controls()
	if entrance.is_empty(): return null
	var at := _control_centre(entrance[0])
	await _drag(at, at)
	return _held_card()

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
# NOTHING IS HELD UNTIL THE PLAYER ACTS
# ==============================================================================

# The deal settles with an Entrance full of cards and the player's hand empty: no card is held, no
# card is lifted, and the board's opening focus rests on a grid cell a pad can move from.
func test_the_show_opens_with_nothing_held() -> void:
	await _start_fixture()
	check(not _entrance_controls().is_empty() and TestGridFixtures.leftmost_entrance_slot() != -1,
			"the deal filled the Entrance", _hand_str())
	check(_pa.selected_cards.is_empty(), "...and left nothing in the player's hand", _hand_str())
	var lifted : Array[CardData] = []
	for data : CardData in _pa.data_card:
		if _is_lifted(data): lifted.append(data)
	check(lifted.is_empty(), "...and no card on the board is lifted", str(lifted.size()))
	var owner := _picture_viewport.gui_get_focus_owner()
	check(owner != null and _pa.ui_data.has(owner)
			and not _game.state.cell_type_coord(_pa.ui_data[owner]).is_nowhere(),
			"...with the picture viewport's opening focus on a grid cell's own control",
			"picture=%s root=%s" % [owner, _viewport.gui_get_focus_owner()])
	await _end_fixture()

# A placement empties the hand and puts nothing back into it: the next card is picked up by the
# player or not at all.
func test_a_placement_leaves_nothing_held() -> void:
	await _start_fixture()
	await _drag_a_card_into_the_grid()
	check(_placed_cards().size() == 1, "the drag placed one card into the grid", _hand_str())
	check(_pa.selected_cards.is_empty(), "...and the hand is empty behind it", _hand_str())
	var refill : Array[Control] = _entrance_controls()
	check(not refill.is_empty() and _pa.selected_cards.is_empty(),
			"...even once the Entrance has refilled", _hand_str())
	await _end_fixture()

# A CLICK LIFTS, IT DOES NOT CARRY: the card is held and raised in its own slot, and pointer motion
# with no button down leaves it there.
func test_a_click_lifts_the_card_without_following() -> void:
	await _start_fixture()
#ONE GRID IS THE DEFAULT BOARD, and it is centred: the position the Entrance takes under its grid
#and the centre of the window are the same place, so a pickup must move it nowhere at all.
	check(_game.state.grids.size() == 1,
			"precondition: the dealt board is the one-grid default", "%d grid(s)"
			% _game.state.grids.size())
	var before := _pa.entrance_h_track.position.x
	var held := await _lift_the_leftmost()
	await _settle_layout()
	check(absf(_pa.entrance_h_track.position.x - before) <= 0.5,
			"a pickup on a one-grid board moves the Entrance nowhere: nothing jumps",
			"x %.2f -> %.2f" % [before, _pa.entrance_h_track.position.x])
	check(held != null and _is_lifted(held), "a click lifted the card it landed on", _hand_str())
	if held:
		check(not _is_following(held), "...and it is NOT following the cursor", _hand_str())
		var visual : CardVisual = _pa.data_card[held]
		check(visual.held_lift_px() > 0.0, "...by the held card's own lift, a real height",
				"%.1f px" % visual.held_lift_px())
		await _nudge(_card_centre(held))
		await _nudge(_control_centre(_entrance_controls()[-1]))
		check(not _is_following(held),
				"...and mouse motion with the button UP never starts it following", _hand_str())
		check(_pa.selected_cards.has(held) and _is_lifted(held),
				"...it just waits in its slot, still lifted", _hand_str())
	await _end_fixture()

# The second half of the click model: with a card lifted, a click on a cell the board accepts
# places it there, as one ordinary undo step.
func test_a_click_on_a_legal_cell_places_the_lifted_card() -> void:
	await _start_fixture()
	var held := await _lift_the_leftmost()
	var cell := await _legal_cell_control(held) if held else null
	check(held != null and cell != null, "a card is lifted and a cell accepts it",
			"held %s, cell %s" % [held != null, cell != null])
	if held and cell:
		var committed := _game.save_history.size()
		var at := _control_centre(cell)
		await _drag(at, at)
		check(_placed_cards().has(held), "a click on that cell placed the lifted card", _hand_str())
		check(_game.save_history.size() == committed + 1, "...as exactly one undo step",
				"%d -> %d" % [committed, _game.save_history.size()])
	await _end_fixture()

# ==============================================================================
# 5.1 – 5.3: THE THRESHOLD, AND WHAT A RELEASE LANDS ON
# ==============================================================================

# 5.1 (E12, E13, Q283=a): a release within a small threshold of its press is a CLICK — it grabs
# the card it landed on and leaves it held, and places nothing.
func test_a_sub_threshold_release_is_a_click() -> void:
	await _start_fixture()
	var entrance := _entrance_controls()
	check(entrance.size() >= 2, "the dealt Entrance offers cards to press",
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
	var held := await _lift_the_leftmost()
	var cell := await _legal_cell_control(held) if held else null
	check(held != null and cell != null,
			"a card is lifted and a cell accepts it",
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

# The threshold a real press reads is the card as DRAWN on a board zoomed into a grid, so both
# releases are measured from the size the player sees there, never from the unzoomed card.
func test_the_drag_threshold_follows_the_boards_zoom() -> void:
	await _start_fixture()
	var entrance := _entrance_controls()
	check(not is_equal_approx(_pa.board_zoom, 1.0), "the focused board sits at a zoom other than 1.0 (2.7)",
			str(_pa.board_zoom))
	check(entrance.size() >= 2, "the dealt Entrance offers cards to press",
			"%d control(s)" % entrance.size())
	if entrance.size() >= 2:
		await _check_a_release_just_under_the_threshold_clicks(entrance[1])
		await _check_a_release_just_over_the_threshold_drops()
	await _end_fixture()

func _drawn_threshold_px(card: Control) -> float:
	return GestureMetrics.drag_threshold_px(card.get_global_rect().size, PlayArea.settings())

func _check_a_release_just_under_the_threshold_clicks(target: Control) -> void:
	var data : CardData = _pa.ui_data[target]
	var travel := _drawn_threshold_px(target) - THRESHOLD_MARGIN_PX
	var at := _control_centre(target)
	var drops := _spy_on_drops()
	await _drag(at, at + Vector2(travel, 0.0))
	check(drops.is_empty() and _pa.selected_cards.has(data) and _pa.locked_data == data
			and _placed_cards().is_empty(),
			"a release %.1f px from its press, just under the zoomed card's threshold, is a click (2.7)"
			% [travel], "%d drop(s), %s" % [drops.size(), _hand_str()])

# No legal cell lies within a threshold of any Entrance card -- the grid sits a gap wider than one
# away -- so the release that proves "over" lands back on the held card, where it is a drop.
func _check_a_release_just_over_the_threshold_drops() -> void:
	var held := _held_card()
	var card : Control = _pa.data_ui[held]
	var travel := _drawn_threshold_px(card) + THRESHOLD_MARGIN_PX
	var at := _control_centre(card)
	var drops := _spy_on_drops()
	await _drag(at, at + Vector2(travel, 0.0))
	check(drops.size() == 1 and drops.has(held) and _placed_cards().is_empty(),
			"a release %.1f px from its press, just over the zoomed card's threshold, is a drag (2.7)"
			% [travel], "%d drop(s), %s" % [drops.size(), _hand_str()])

func _spy_on_drops() -> Array[CardData]:
	var drops : Array[CardData] = []
	_pa.card_dropped.connect(func(dropped: CardData) -> void: drops.append(dropped))
	return drops

# 5.3 (E17): only a cell that takes the card ends a drag holding anything. A
# release over a cell the board refuses lets it go: the hand empties, the card lies flat in its
# slot and the drop map goes out.
func test_a_release_on_an_illegal_cell_drops_the_card() -> void:
	await _start_fixture()
	await _drag_a_card_into_the_grid()
	var occupied := _placed_cards()
	var held := await _lift_the_leftmost()
	check(occupied.size() == 1 and held != null,
			"the board offers an occupied cell, with a second Entrance card lifted",
			"%d placed, %s" % [occupied.size(), _hand_str()])
	if occupied.size() == 1 and held:
		var committed := _game.save_history.size()
		await _begin_drag(_card_centre(held), _card_centre(occupied[0]))
		check(_is_following(held), "the drag carries the card: it tracks the cursor (5.3)",
				_hand_str())
		check(TestGridFixtures.lit_cell_count(_pa) > 0,
				"...with the drop map lit while it is in hand (5.3)",
				str(TestGridFixtures.lit_cell_count(_pa)))
		await _end_drag(_card_centre(occupied[0]))
		check(_pa.selected_cards.is_empty(),
				"...and a refused release empties the hand (5.3)", _hand_str())
		check(not _is_lifted(held) and not _is_following(held),
				"...the card flat in its slot, following nothing (5.3)", _hand_str())
		check(_game.save_history.size() == committed and _placed_cards().size() == 1,
				"...with nothing placed and nothing committed (5.3)", _hand_str())
		check(TestGridFixtures.lit_cell_count(_pa) == 0,
				"...and the drop map out on every cell (5.3)",
				str(TestGridFixtures.lit_cell_count(_pa)))
	await _end_fixture()

# The chase restarts on a new press AND travel past the threshold, never on either
# alone. A CLICK is how a card reaches the lifted, not-following state the restart starts from.
func test_a_lifted_card_follows_only_on_a_new_press_with_travel() -> void:
	await _start_fixture()
	var held := await _lift_the_leftmost()
	check(held != null and _is_lifted(held) and not _is_following(held),
			"a click left a card lifted in its slot, following nothing", _hand_str())
	if held:
		var from := _card_centre(held)
		await _nudge(from)
		check(not _is_following(held),
				"a mouse motion alone leaves it resting in its slot", _hand_str())
		await _push(_mouse_button(from, true), _picture_viewport)
		await _nudge(from)
		check(not _is_following(held),
				"...a new press alone does not restart the follow", _hand_str())
		await _push(_motion(from + Vector2(
				_drawn_threshold_px(_pa.data_ui[held]) + THRESHOLD_MARGIN_PX, 0.0)),
				_picture_viewport)
		check(_is_following(held),
				"...it takes a press AND travel past the threshold", _hand_str())
	await _end_fixture()

# A motion the card cannot read as a drag: short of every threshold, so what it proves is the
# MOTION, never the travel.
func _nudge(from: Vector2) -> void:
	await _push(_motion(from + Vector2(SUB_THRESHOLD_TRAVEL_PX, 0.0)), _picture_viewport)

# ==============================================================================
# 5.4 – 5.5: RELEASES THAT ARE NOT PLACEMENTS
# ==============================================================================

# 5.4 (E17, Q288=a): the container is not a placeable spot. The release lands in the WINDOW's own
# viewport, over the container, where a player's would — and the board still hears it and lets the
# card go.
func test_a_release_over_the_container_drops_the_card() -> void:
	await _start_fixture()
	var held := await _lift_the_leftmost()
	var cell := await _legal_cell_control(held) if held else null
	check(held != null and cell != null, "a card is lifted and a cell offers somewhere to drag over",
			"held %s, cell %s" % [held != null, cell != null])
	if held and cell:
		var committed := _game.save_history.size()
		await _begin_drag(_card_centre(held), _control_centre(cell))
		check(_is_following(held), "the drag is live before the release (5.4)", _hand_str())
		check(TestGridFixtures.lit_cell_count(_pa) > 0,
				"...with the drop map lit while it is in hand (5.4)",
				str(TestGridFixtures.lit_cell_count(_pa)))
		await _push(_mouse_button(_container.container_rect().get_center(), false), _viewport)
		await _frames(3)
		check(not _is_following(held),
				"the release over the container reached the board and ended the chase (5.4)",
				_hand_str())
		check(_pa.selected_cards.is_empty() and not _is_lifted(held),
				"...the hand empty, the card flat in its slot (5.4)", _hand_str())
		check(_placed_cards().is_empty() and _game.save_history.size() == committed,
				"...and nothing was placed (5.4)", _hand_str())
		check(TestGridFixtures.lit_cell_count(_pa) == 0,
				"...and the drop map out on every cell (5.4)",
				str(TestGridFixtures.lit_cell_count(_pa)))
	await _end_fixture()

## Where a release lands on no cell the board takes: bare board, another Entrance card's own slot, and off the window entirely.
func _release_points_that_take_nothing() -> Array[Vector2]:
	var entrance := _entrance_controls()
	var rightmost : Control = entrance.back()
	return [Vector2(BARE_BOARD_CORNER_PX, BARE_BOARD_CORNER_PX), _control_centre(rightmost),
			Vector2(_picture_viewport.size) + Vector2(OFF_WINDOW_PX, OFF_WINDOW_PX)]

# Only a cell that takes the card ends a drag holding anything. Over bare board, over another
# Entrance card and off the window entirely, the release lets go of what it was carrying.
func test_a_release_away_from_the_cells_drops_the_card() -> void:
	await _start_fixture()
	var places : Array[String] = ["bare board", "another Entrance card", "off the window"]
	var points := _release_points_that_take_nothing()
	for i : int in points.size():
		var held := await _lift_the_leftmost()
		check(held != null and TestGridFixtures.lit_cell_count(_pa) > 0,
				"a card is lifted with the drop map lit, before the release over %s" % places[i],
				_hand_str())
		if not held: continue
		await _drag(_card_centre(held), points[i])
		check(_pa.selected_cards.is_empty() and not _is_lifted(held) and not _is_following(held),
				"a release over %s drops the card" % places[i], _hand_str())
		check(TestGridFixtures.lit_cell_count(_pa) == 0,
				"...and the drop map is out over %s" % places[i],
				str(TestGridFixtures.lit_cell_count(_pa)))
	await _end_fixture()

# A CARD THE PLAYER ACTED WITH IS FINISHED WITH, and a cancelled one is not. Both halves are pinned
# here so they cannot drift together: the drop and the placement give up the description lock the
# click made and the focus that outlines the card, and the cancel keeps both for its second press.
func test_an_act_with_the_card_ends_its_lock_and_its_focus() -> void:
	await _start_fixture()
	var lifted := await _lift_the_leftmost()
	check(lifted != null and _container.is_locked() and _is_outlined(lifted),
			"a click lifts the card, locks its description and outlines it",
			_lock_str(lifted))
	var cell := await _legal_cell_control(lifted) if lifted else null
	if lifted and cell:
		await _drag(_card_centre(lifted), Vector2(BARE_BOARD_CORNER_PX, BARE_BOARD_CORNER_PX))
		check(_pa.selected_cards.is_empty() and not _container.is_locked()
				and not _container.showing_description(),
				"a DROP gives the sidebar back to the HUD: the lock is gone and no description is up",
				_lock_str(lifted))
		check(not _is_outlined(lifted),
				"...and the dropped card is no longer outlined", _lock_str(lifted))
		check(_pa.focused_control == _resting_focus_control()
				and _picture_viewport.gui_get_focus_owner() == _resting_focus_control(),
				"...with the focus rested on the selected grid's origin cell, inside the board's "
				+ "own viewport, where a pad can move on from",
				"%s, owner %s" % [str(_pa.focused_control),
				str(_picture_viewport.gui_get_focus_owner())])

		var again := await _lift_the_leftmost()
		var target := await _legal_cell_control(again) if again else null
		check(again != null and target != null and _container.is_locked(),
				"a second card is lifted, locked and aimed at a cell that takes it",
				_lock_str(again))
		if again and target:
			await _drag(_control_centre(target), _control_centre(target))
			check(_placed_cards().has(again) and not _container.is_locked()
					and not _container.showing_description(),
					"a PLACEMENT does the same: the card lands and the HUD is back",
					_lock_str(again))
			check(_pa.focused_control == _resting_focus_control()
					and _picture_viewport.gui_get_focus_owner() == _resting_focus_control(),
					"...and the focus is rested on the origin cell, off the card that was placed",
					"%s, owner %s" % [str(_pa.focused_control),
					str(_picture_viewport.gui_get_focus_owner())])

		var cancelled := await _lift_the_leftmost()
		if cancelled:
			await _right_click(_card_centre(cancelled), false)
			check(_pa.selected_cards.is_empty() and _container.is_locked()
					and _container.showing_description(),
					"a CANCEL is not an act: the first press only releases the card and the "
					+ "description it was read against is still up",
					_lock_str(cancelled))
	await _end_fixture()

# A RESOLVED SHOW HAS NO BOARD TO REST ON: the overlay's `disable_board_focus` holds every cell at
# FOCUS_NONE, the one control `_cell_focus_control` will not hand back. A settings write rebuilds
# the board under it -- the setter announces to EVERY live board -- and that rebuild asks again.
func test_a_rebuild_under_the_outcome_overlay_rests_on_nothing() -> void:
	await _start_fixture()
	await _drag_a_card_into_the_grid()
	_game.end_show()
	await _frames(8)
	check(_pa.board_focus_locked,
			"the resolved show disabled the board's focus", str(_pa.board_focus_locked))
	check(_pa._cell_focus_control(BoardCoord.new(_pa.selected_grid, 0, 0, 0)) == null
			and _pa.selected_cards.is_empty(),
			"...so the selected grid's origin cell offers nothing to rest on, and no held card "
			+ "stands in for it", _hand_str())
	var rested_on := _picture_viewport.gui_get_focus_owner()
	var slide : float = SettingsManager.settings.container_slide_duration
	SettingsManager.settings.container_slide_duration = slide
	await _frames(8)
	check(_picture_viewport.gui_get_focus_owner() == rested_on,
			"the rebuild that settings write causes leaves the focus where the outcome put it",
			"%s, was %s" % [str(_picture_viewport.gui_get_focus_owner()), str(rested_on)])
	_pa.rest_focus_on_board()
	check(_picture_viewport.gui_get_focus_owner() == rested_on,
			"...and asking for the rest outright is the same nothing, by the one route both "
			+ "callers take",
			"%s, was %s" % [str(_picture_viewport.gui_get_focus_owner()), str(rested_on)])
	_game.undo()
	await _frames(8)
	check(not _game.state.show_ended and not _pa.board_focus_locked,
			"the undo takes the overlay back down, so the board has cells to rest on again and the "
			+ "fixture hands the show on the way it found it",
			"ended %s, locked %s" % [str(_game.state.show_ended), str(_pa.board_focus_locked)])
	await _end_fixture()

## Where a hand with nothing in it rests the board focus: the selected grid's origin cell.
func _resting_focus_control() -> Control:
	return _pa._cell_focus_control(BoardCoord.new(_pa.selected_grid, 0, 0, 0))

## Is this card drawn wearing the focus outline -- the mark itself, not the field behind it?
func _is_outlined(data: CardData) -> bool:
	var visual : CardVisual = _pa.data_card.get(data)
	if not visual: return false
	return _rim_ink_and_width(visual).x == PaletteDB.ROLES.match_rim

func _lock_str(data: CardData) -> String:
	return "locked %s, showing %s, outlined %s, %s" % [str(_container.is_locked()),
			str(_container.showing_description()), str(_is_outlined(data)), _hand_str()]

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
	var held := await _lift_the_leftmost()
	var cell := await _legal_cell_control(held) if held else null
	check(held != null and cell != null, "a card is lifted and a cell accepts it",
			"held %s, cell %s" % [held != null, cell != null])
	if held and cell:
		var drops := _spy_on_drops()
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
	check(entrance.size() >= 2, "the dealt Entrance offers cards to tap",
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
# 5.6 – 5.7: A BOARD CARD, WITH AN ENTRANCE CARD IN HAND
# ==============================================================================

# Both board-card rows start from the same board: one card placed the way a player places it, a
# second Entrance card lifted, and the placed card wearing a rule the shipped deck has none of.
func _a_board_card_wearing(rule: BoardCardRule) -> CardData:
	await _start_fixture()
	await _drag_a_card_into_the_grid()
	var placed := _placed_cards()
	var lifted := await _lift_the_leftmost()
	check(placed.size() == 1 and lifted != null,
			"a board card is on the grid, with another Entrance card lifted",
			"%d placed, %s" % [placed.size(), _hand_str()])
	if placed.size() != 1: return null
	return placed[0].with_stamp(rule)

# 5.6 (E10, E11, Q286=b): a drag is unambiguous about which card is being moved, so dragging a
# board card drops the lifted one implicitly — the board card is the one held, and the one following.
func test_a_drag_from_a_board_card_drops_the_lifted_card() -> void:
	var board_card := await _a_board_card_wearing(BoardCardRule.new())
	var lifted := _held_card()
	if board_card and lifted:
		var cell := await _legal_cell_control(lifted)
		await _begin_drag(_card_centre(board_card), _control_centre(cell))
		check(_pa.selected_cards.has(board_card),
				"the drag picked the board card up (5.6, E10)", _hand_str())
		check(not _pa.selected_cards.has(lifted),
				"...and the Entrance card it was holding is let go (5.6, Q286=b)", _hand_str())
		check(_is_following(board_card),
				"...and the board card is the one tracking the cursor (5.6, Q287=a)", _hand_str())
		await _end_drag(_control_centre(cell))
	await _end_fixture()

# 5.7 (E8, the Q122 note): a CLICK on a board card still tries to place the lifted card onto it
# first; because it does not stack, the only action left is the grab, and that happens straight
# away (E9).
func test_a_click_on_a_board_card_tries_to_place_first() -> void:
	var rule := BoardCardRule.new()
	var board_card := await _a_board_card_wearing(rule)
	var lifted := _held_card()
	if board_card and lifted:
		var committed := _game.save_history.size()
		var at := _card_centre(board_card)
		await _drag(at, at)
		check(rule.place_attempts >= 1,
				"the click asked the board card to take the lifted card first (5.7, E8)",
				"%d attempt(s)" % rule.place_attempts)
		check(_pa.selected_cards.has(board_card) and not _pa.selected_cards.has(lifted),
				"...and since it does not stack, the grab happens straight away (5.7, E9)",
				_hand_str())
		check(_placed_cards().size() == 1 and _game.save_history.size() == committed,
				"...with nothing placed onto it (5.7)", _hand_str())
	await _end_fixture()

# Only the card a drag carries can be placed by its release. One that starts on an empty cell's
# zone card, which no rule picks up, carries nothing, so the lifted card must not land instead.
func test_a_refused_drag_from_an_empty_cell_places_nothing() -> void:
	await _start_fixture()
	var lifted := await _lift_the_leftmost()
	var cell := await _legal_cell_control(lifted) if lifted else null
	var source := _an_empty_cell_other_than(cell)
	check(cell != null and source != null, "the board offers two empty cells with a card lifted",
			"cell %s, source %s, %s" % [cell != null, source != null, _hand_str()])
	if cell and source:
		await _check_a_refused_drag_places_nothing(_control_centre(source), lifted, cell)
	await _end_fixture()

# The same drag from a card already in the grid, which no shipped rule picks up.
func test_a_refused_drag_from_a_grid_card_places_nothing() -> void:
	await _start_fixture()
	await _drag_a_card_into_the_grid()
	var placed := _placed_cards()
	var lifted := await _lift_the_leftmost()
	var cell := await _legal_cell_control(lifted) if lifted else null
	check(placed.size() == 1 and cell != null,
			"a card is on the grid, a second Entrance card lifted, and a cell accepts it",
			"%d placed, cell %s, %s" % [placed.size(), cell != null, _hand_str()])
	if placed.size() == 1 and cell:
		await _check_a_refused_drag_places_nothing(_card_centre(placed[0]), lifted, cell)
	await _end_fixture()

# A fully on-screen empty cell a drag can start from, which is not the one it is released on.
func _an_empty_cell_other_than(excluded: Control) -> Control:
	for control : Control in _reachable_cells():
		if control == excluded: continue
		if _game.state.card_at(_game.state.cell_type_coord(_pa.ui_data[control])) == null: return control
	return null

# A card that does not place goes back: the release of a drag whose pickup the board refused drops
# nothing, commits nothing, and leaves the lifted card held in its Entrance slot.
func _check_a_refused_drag_places_nothing(from: Vector2, lifted: CardData, cell: Control) -> void:
	var drops := _spy_on_drops()
	var committed := _game.save_history.size()
	var placed := _placed_cards().size()
	await _drag(from, _control_centre(cell))
	check(drops.is_empty(), "the release of a refused pickup drops nothing (Q280=a)",
			"%d drop(s)" % drops.size())
	check(_game.save_history.size() == committed and _placed_cards().size() == placed,
			"...so the board commits no step (Q280=a)", _hand_str())
	check(_pa.selected_cards.has(lifted) and _is_in_the_entrance(lifted),
			"...and the lifted card is still held in its slot (Q281=a)", _hand_str())

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
	check(entrance.size() >= 2, "the dealt Entrance offers cards to click",
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
	var held := await _lift_the_leftmost()
	var cell := await _cell_the_lifted_card_can_be_placed_on(held, spy)
	if held and cell:
		var at := _control_centre(cell)
		await _drag(at, at)
		var committed := _game.save_history.size()
		check(_placed_cards().has(held), "the pair's first click placed the lifted card", _hand_str())
		var selections := _spy_on_selections()
		await _double_click(at)
		_check_the_placement_stands_untapped(spy, held, committed, selections)
	await _end_fixture()

# A REFUSED pair must give its closing release back to nobody: a real mouse puts a motion between
# the two clicks, which refreshes the hover the GUI pass reads, and the release would otherwise
# land as an ordinary click on the cell the placement just filled.
func test_a_refused_pairs_release_places_nothing() -> void:
	await _start_fixture()
	var spy := TapSpy.new()
	var held := await _lift_the_leftmost()
	var cell := await _cell_the_lifted_card_can_be_placed_on(held, spy)
	if held and cell:
		var at := _control_centre(cell)
		await _drag(at, at)
		var committed := _game.save_history.size()
		check(_placed_cards().has(held) and _pa.selected_cards.is_empty(),
				"the pair's first click placed the lifted card and left the hand empty", _hand_str())
		await _push(_motion(at + Vector2.RIGHT), _picture_viewport)
		var selections := _spy_on_selections()
		await _double_click(at)
		_check_the_placement_stands_untapped(spy, held, committed, selections)
		check(_pa.selected_cards.is_empty(),
				"...and lifted nothing in its place", _hand_str())
	await _end_fixture()

# Q93a=a REACHED BY A FINGER: the pair's first finger press placed the lifted card, so the second is
# refused exactly as the mouse's is — the emulated mouse form of that second press, which the
# engine dispatches BEFORE the touch, must not move the depth the refusal reads.
func test_a_touch_tap_after_a_placement_is_refused() -> void:
	await _start_fixture()
	var spy := TapSpy.new()
	var held := await _lift_the_leftmost()
	var cell := await _cell_the_lifted_card_can_be_placed_on(held, spy)
	if held and cell:
		var at := _control_centre(cell)
		var window := PlayArea.settings().card_tap_window_ms
		PlayArea.settings().card_tap_window_ms = PUSHED_PAIR_WINDOW_MS
		await _touch_tap(at)
		var committed := _game.save_history.size()
		check(_placed_cards().has(held), "the pair's first finger press placed the lifted card",
				_hand_str())
		var selections := _spy_on_selections()
		await _touch_tap(at)
		_check_the_placement_stands_untapped(spy, held, committed, selections)
		PlayArea.settings().card_tap_window_ms = window
	await _end_fixture()

# The board a refusal row starts from: a lifted card wearing the hook spy, and a cell that accepts
# it, so the pair's first press has a real placement to make.
func _cell_the_lifted_card_can_be_placed_on(held: CardData, spy: TapSpy) -> Control:
	var cell := await _legal_cell_control(held) if held else null
	check(held != null and cell != null,
			"a card is lifted and a cell accepts it",
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

# Q97=b: an empty cell's zone card taps like any other card, because a cell can carry modifiers
# too. Nothing is picked up first, so the pair's first click has nothing to place.
func test_a_double_click_on_an_empty_cells_zone_card_taps() -> void:
	await _start_fixture()
	var entrance := _entrance_controls()
	var cell := await _legal_cell_control(_pa.ui_data[entrance[0]]) if entrance else null
	check(cell != null, "the board offers an empty cell an Entrance card could have gone into",
			"cell %s" % [cell != null])
	if cell:
		var zone_card : CardData = _pa.ui_data[cell]
		var at := _control_centre(cell)
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
	check(entrance.size() >= 2, "the dealt Entrance offers cards to focus",
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

# ==============================================================================
# A PICKUP AIMS THE BOARD; ONLY A PLACEMENT TAKES THE ENTRANCE. ⚠ THE GRID COUNT IS THE POINT.
# ==============================================================================

#A CLICK is a pickup, so a click aims the board -- but the Entrance waits in the middle of the
#window until a card is actually PLACED, so the player can still choose another grid.
func test_a_pickup_leaves_the_entrance_centred_until_a_placement_takes_it() -> void:
	await _start_fixture_grids(3)
	check(_pa.view_mode == PlayArea.ViewMode.OVERVIEW and _game.state.committed_grid == -1
			and _game.state.grids.size() == 3,
			"precondition: three grids, looked at whole, nothing committed",
			"mode %d, committed %d, %d grid(s)"
			% [_pa.view_mode, _game.state.committed_grid, _game.state.grids.size()])
#THE KEYBOARD SURVIVES A FOCUS. A card the player has focused is a card they can still act on once
#the board has moved, so aiming the board must not take the focus out of the picture with it.
	var resting : CardData = _pa.ui_data[_entrance_controls()[0]]
	await _focus_the_card(resting)
	var owner := _picture_viewport.gui_get_focus_owner()
	check(owner != null and owner == _pa.data_ui[resting],
			"precondition: keyboard focus can reach an Entrance card at all", str(owner))
	_pa.focus_grid(2)
	await _settle_layout()
	check(_pa.entrance_home_grid() == PlayArea.NO_GRID
			and is_equal_approx(_pa._entrance_slide, 0.0),
			"focusing a grid does NOT take the Entrance: it belongs to no grid and has not travelled",
			"home grid %d, slide %.3f" % [_pa.entrance_home_grid(), _pa._entrance_slide])
	check(_picture_viewport.gui_get_focus_owner() == owner
			and (owner as Control).get_viewport() == _picture_viewport,
			"...and the focus stays on the same control, in the picture's own viewport",
			str(_picture_viewport.gui_get_focus_owner()))
	_pa.open_zoomed_out()
	await _settle_layout()

	await _press_key(KEY_PERIOD)
	await _settle_layout()
	check(_pa.pan_grid == 2,
			"precondition: a real pan key stepped the overview onto the last grid",
			"pan_grid %d" % _pa.pan_grid)
	var window_centre := _drawn_centre_x(_pa.scroll_container)
	check(absf(_drawn_centre_x(_pa.upper_zone_right) - window_centre) <= 1.0,
			"precondition: the uncommitted Entrance starts centred in the board's window",
			"row %.2f vs window %.2f"
			% [_drawn_centre_x(_pa.upper_zone_right), window_centre])

	var entrance := _entrance_controls()
	check(not entrance.is_empty(), "precondition: the deal left a card in the Entrance to lift",
			"%d control(s)" % entrance.size())
	var aimed_at : CardData = _pa.ui_data[entrance[0]]
	var held := await _lift_the_leftmost()
	check(held == aimed_at,
			"a click at a card's DRAWN position picks up THAT card: hit-testing follows the "
			+ "Entrance wherever it is drawn", _hand_str())
	check(_pa.view_mode == PlayArea.ViewMode.FOCUSED and _pa.focused_grid == 2,
			"...and the pickup focuses the grid nearest the middle of the board's window",
			"mode %d, focused %d" % [_pa.view_mode, _pa.focused_grid])
	await _settle_layout()
	check(_pa.entrance_home_grid() == PlayArea.NO_GRID
			and is_equal_approx(_pa._entrance_slide, 0.0),
			"...and the PICKUP still leaves the Entrance owned by no grid: nothing has been placed yet",
			"home grid %d, slide %.3f, committed %d"
			% [_pa.entrance_home_grid(), _pa._entrance_slide, _game.state.committed_grid])

#A CANCELLED pickup takes nothing back and gives nothing away: the board stays where the pickup
#aimed it and the Entrance is still free to go to any grid.
	await _right_click(_control_centre(_entrance_controls()[-1]), false)
	await _settle_layout()
	check(_pa.selected_cards.is_empty(), "precondition: the second button let the card go",
			_hand_str())
	check(_pa.focused_grid == 2 and _pa.entrance_home_grid() == PlayArea.NO_GRID,
			"a cancelled pickup leaves the board focused and the Entrance still owned by no grid",
			"focused %d, home grid %d" % [_pa.focused_grid, _pa.entrance_home_grid()])

#THE PLACEMENT IS WHAT COMMITS, and the slide starts from it.
	var to_place := await _lift_the_leftmost()
	var cell := await _legal_cell_control_in_grid(to_place, 2) if to_place else null
	check(to_place != null and cell != null,
			"precondition: a card is lifted and a cell on the grid in view accepts it",
			"held %s, cell %s" % [to_place != null, cell != null])
	if to_place and cell:
		var at := _control_centre(cell)
		await _drag(at, at)
		check(_placed_cards().has(to_place) and _game.state.committed_grid == 2,
				"placing the card is what commits the Entrance, and it commits to the grid it went on",
				"committed %d, %s" % [_game.state.committed_grid, _hand_str()])
#SAMPLED PER PHYSICS FRAME, because a still frame cannot tell a slide from a jump. ⚠ THE DRAWN
#x DOES NOT MOVE HERE and must not be asserted on: the committed grid is the focused one, so it is
#already centred in the window and both ends of the travel are the same point.
		var travel : Array[float] = []
		var waited := 0.0
		var landed := -1.0
		while waited < PlayArea.settings().grid_pan_duration * 3.0:
			await get_tree().physics_frame
			waited += get_physics_process_delta_time()
			travel.append(_pa._entrance_slide)
			if landed < 0.0 and is_equal_approx(_pa._entrance_slide, 1.0): landed = waited
		check(travel.size() > 2, "precondition: the slide was sampled over several physics frames",
				"%d sample(s)" % travel.size())
		var monotonic := true
		for i : int in range(1, travel.size()):
			if travel[i] + 0.0001 < travel[i - 1]: monotonic = false
		check(monotonic, "the Entrance travels one way across, never back",
				"%d sample(s), first %.3f last %.3f" % [travel.size(), travel[0], travel[-1]])
		check(landed >= 0.0 and landed <= PlayArea.settings().grid_pan_duration
				+ get_physics_process_delta_time() * 2.0,
				"...and it is all the way across within the pan clock",
				"landed %.3f s in, clock %.3f s" % [landed, PlayArea.settings().grid_pan_duration])
		await _settle_layout()
		check(_pa.entrance_home_grid() == 2 and _entrance_off_grid_px(2) <= 1.0,
				"a committed Entrance belongs to the grid it was placed on and is drawn under it",
				"home grid %d, %.2f px off grid 2"
				% [_pa.entrance_home_grid(), _entrance_off_grid_px(2)])

#AND NOW IT FOLLOWS THAT GRID. Panning away is the one route where the two positions differ, so it
#is the only one that can show the Entrance MOVING through the positions in between.
		var started := _pa.entrance_h_track.position.x
		_pa.pan_by_grids(-1)
		var drawn : Array[float] = []
		var panned := 0.0
		while panned < PlayArea.settings().grid_pan_duration * 3.0:
			await get_tree().physics_frame
			panned += get_physics_process_delta_time()
			drawn.append(_pa.entrance_h_track.position.x)
		await _settle_layout()
		var ended := _pa.entrance_h_track.position.x
		check(absf(ended - started) > 1.0,
				"precondition: panning off the committed grid moved the Entrance with it",
				"x %.2f -> %.2f" % [started, ended])
		var between := 0
		for x : float in drawn:
			if minf(started, ended) + 1.0 < x and x < maxf(started, ended) - 1.0: between += 1
		check(between > 0,
				"...PASSING THROUGH the positions in between rather than jumping",
				"%d of %d samples strictly between %.1f and %.1f"
				% [between, drawn.size(), started, ended])
		check(_entrance_off_grid_px(2) <= 1.0
				and absf(_drawn_centre_x(_pa.upper_zone_right)
				- _drawn_centre_x(_pa.scroll_container)) > 1.0,
				"...and it stays under its own grid, no longer in the middle of the window",
				"%.2f px off grid 2, %.2f px off the window centre"
				% [_entrance_off_grid_px(2), absf(_drawn_centre_x(_pa.upper_zone_right)
				- _drawn_centre_x(_pa.scroll_container))])
	await _end_fixture()

# The DRAG half of the same gesture aims the board exactly as the click does, and "nearest" is
# geometry: it is neither the grid a pan is heading for nor the grid that was focused.
func test_a_drag_pickup_aims_at_the_grid_nearest_the_window_centre() -> void:
	await _start_fixture_grids(3)
	check(_pa.view_mode == PlayArea.ViewMode.OVERVIEW and _pa.pan_grid == 1,
			"precondition: a three-grid show opens looking at the middle grid",
			"mode %d, pan_grid %d" % [_pa.view_mode, _pa.pan_grid])
	var entrance := _entrance_controls()
	check(not entrance.is_empty(), "precondition: a card to drag out of the Entrance",
			"%d control(s)" % entrance.size())
	var from := _control_centre(entrance[0])
	await _begin_drag(from, from + Vector2(_pa._swipe_threshold_px() * 3.0, 0.0))
	check(_held_card() != null and _is_following(_held_card()),
			"precondition: a press dragged past the threshold has the card following the cursor",
			_hand_str())
	check(_pa.view_mode == PlayArea.ViewMode.FOCUSED and _pa.focused_grid == 1,
			"a DRAG pickup focuses the grid in view exactly as a click does",
			"mode %d, focused %d" % [_pa.view_mode, _pa.focused_grid])
	await _end_drag(from)
	await _settle_layout()
	check(_pa.entrance_home_grid() == PlayArea.NO_GRID
			and is_equal_approx(_pa._entrance_slide, 0.0),
			"...and a DRAG pickup takes the Entrance no more than a click does: still owned by no grid",
			"home grid %d, slide %.3f" % [_pa.entrance_home_grid(), _pa._entrance_slide])
	await _right_click(from, false)

#MID-PAN: the board is heading for grid 1 while grid 0 is still the one in front of the player.
	_pa.focus_grid(0)
	await _settle_layout()
	check(_pa.focused_grid == 0 and _nearest_drawn_grid() == 0,
			"precondition: the board is focused on grid 0 and grid 0 is the grid in view",
			"focused %d, nearest %d" % [_pa.focused_grid, _nearest_drawn_grid()])
#⚠ ASKED ON THE FRAME THE PAN STARTS, BEFORE ANYTHING HAS MOVED. The board eases out, so it is past
#the halfway point between the two grids within a handful of frames (measured: a pan key's own
#press-and-release is already enough) and this is the only honest way to catch the state.
	_pa.pan_by_grids(1)
	check(_pa.pan_grid == 1 and _nearest_drawn_grid() == 0
			and _pa._grid_nearest_the_window_centre() == 0,
			"the grid nearest the window's centre is read off where the board IS, not off the grid "
			+ "a pan is heading for",
			"pan_grid %d, drawn nearest %d, product says %d"
			% [_pa.pan_grid, _nearest_drawn_grid(), _pa._grid_nearest_the_window_centre()])

#THE PAN LANDED: grid 1 is now the grid in front of the player while grid 0 is still focused.
	var waited := 0.0
	while waited < 3.0 and _nearest_drawn_grid() != 1:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(_nearest_drawn_grid() == 1 and _pa.focused_grid == 0,
			"precondition: the pan carried grid 1 nearest the centre while the board is still "
			+ "FOCUSED on grid 0",
			"nearest %d, focused %d" % [_nearest_drawn_grid(), _pa.focused_grid])
	var late : CardData = _pa.ui_data[_entrance_controls()[0]]
	await _select_the_card_in_hand(late)
	check(_pa.focused_grid == 1,
			"...and a pickup now takes grid 1: nearest is geometry, not the grid that was focused",
			"focused %d, %s" % [_pa.focused_grid, _hand_str()])
	await _settle_layout()
	check(absf(_drawn_centre_x(_pa.upper_zone_right)
			- _drawn_centre_x(_pa.scroll_container)) <= 1.0,
			"...with the Entrance left in the middle of the window for that grid to come to",
			"%.2f px off the window centre"
			% absf(_drawn_centre_x(_pa.upper_zone_right)
			- _drawn_centre_x(_pa.scroll_container)))
	await _end_fixture()

# The picture the player is not looking at does not process, so a slide caught by leaving the game
# screen freezes where it is — and finishes, never abandoned half way, when the picture comes back.
func test_the_entrance_slide_survives_the_picture_being_left() -> void:
	await _start_fixture_grids(3)
#ONLY A PLACEMENT STARTS THE SLIDE, so the slide this row freezes has to be started by one.
	var held := await _lift_the_leftmost()
	await _settle_layout()
	var cell := await _legal_cell_control_in_grid(held, _pa.focused_grid) if held else null
	check(held != null and cell != null, "precondition: a card lifted and a cell that accepts it",
			"held %s, cell %s" % [held != null, cell != null])
	if not (held and cell):
		await _end_fixture()
		return
	var at := _control_centre(cell)
	await _drag(at, at)
	check(_game.state.committed_grid != -1,
			"precondition: the placement committed the Entrance and started its slide",
			"committed %d" % _game.state.committed_grid)
	var home := _game.state.committed_grid
	check(_pa._entrance_slide < 1.0,
			"precondition: the slide was caught part way across",
			"travelled %.3f" % _pa._entrance_slide)

	check(get_tree().paused,
			"precondition: the wall holds the tree paused for the whole session, so the screen's own "
			+ "process mode is what decides whether it runs", str(get_tree().paused))
	var prev_mode := _view.process_mode
	_view.process_mode = Node.PROCESS_MODE_PAUSABLE
	var frozen := _pa._entrance_slide
	await _frames(8)
	check(is_equal_approx(_pa._entrance_slide, frozen) and frozen < 1.0,
			"leaving the picture stops the slide exactly where it stood",
			"travelled %.3f -> %.3f, x %.2f"
			% [frozen, _pa._entrance_slide, _pa.entrance_h_track.position.x])
	_view.process_mode = prev_mode
	await _settle_layout()
	check(is_equal_approx(_pa._entrance_slide, 1.0) and _entrance_off_grid_px(home) <= 1.0,
			"...and coming back finishes it under the grid, never abandoned half way",
			"travelled %.3f, %.2f px off grid %d"
			% [_pa._entrance_slide, _entrance_off_grid_px(home), home])
	await _end_fixture()

# ==============================================================================
# A USED-UP ENTRANCE FREES THE COMMITTED GRID.
# ==============================================================================

## How many Entrance slots still hold a card the player could pick up.
func _filled_entrance_slots() -> int:
	var filled := 0
	for column : ArrayCardData in _game.state.upper_zone:
		if not column.datas.is_empty(): filled += 1
	return filled

# Empties every Entrance slot but the one whose top card the committed grid still accepts, and
# hands that card back. A show that runs its own Entrance dry takes the whole deck to reach.
func _leave_one_entrance_card(home: int) -> CardData:
	var keep : CardData = null
	var keep_column : ArrayCardData = null
	for column : ArrayCardData in _game.state.upper_zone:
		if column.datas.is_empty(): continue
		var top : CardData = column.datas.back()
		var legal := await _game.legal_cells_for([top] as Array[CardData], [_game.state.grids[home]])
		if legal.is_empty(): continue
		keep = top
		keep_column = column
		break
	if not keep: return null
	for column : ArrayCardData in _game.state.upper_zone:
		if column != keep_column: column.datas.clear()
	keep_column.datas.assign([keep] as Array[CardData])
	_pa.queue_rebuild()
	await _settle_layout()
	return keep

# The player's LAST Entrance card put down on the committed grid -- the used-up moment, which a
# real show reaches only by dealing its whole deck. False when the fixture could not set it up.
func _spend_the_last_entrance_card(home: int) -> bool:
	var last := await _leave_one_entrance_card(home)
	check(last != null and _filled_entrance_slots() == 1,
			"precondition: the player is down to ONE Entrance card, and the committed grid still "
			+ "accepts it", "%d slot(s) hold a card" % _filled_entrance_slots())
	var last_cell := await _legal_cell_control_in_grid(last, home) if last else null
	check(last_cell != null, "precondition: a cell on the committed grid takes that last card",
			"cell %s" % [last_cell != null])
	if not (last and last_cell): return false
	var last_from := _card_centre(last)
	await _drag(last_from, last_from)
	var last_at := _control_centre(last_cell)
	await _drag(last_at, last_at)
	await _settle_layout()
	return true

#ONCE THE PLAYER'S HAND HAS NOWHERE LEFT TO GO ON THE COMMITTED GRID -- and an emptied Entrance has
#nowhere by definition -- the commitment lifts BEFORE the refill, so the next hand may choose
#another grid. Asked after the refill it is asked about the cards the refill just dealt.
func test_a_used_up_entrance_frees_the_commitment() -> void:
	await _start_fixture_grids(2)
	var first := await _lift_the_leftmost()
	await _settle_layout()
	var cell := await _legal_cell_control_in_grid(first, _pa.focused_grid) if first else null
	check(first != null and cell != null,
			"precondition: a card lifted and a cell of the grid in view that accepts it",
			"held %s, cell %s" % [first != null, cell != null])
	if not (first and cell):
		await _end_fixture()
		return
	var at := _control_centre(cell)
	await _drag(at, at)
	var home := _game.state.committed_grid
	check(home != -1, "precondition: the first placement committed a grid",
			"committed %d" % home)
	if home == -1:
		await _end_fixture()
		return

	if not await _spend_the_last_entrance_card(home):
		await _end_fixture()
		return
	check(_game.state.committed_grid == -1,
			"using the Entrance up frees the commitment: it lifts BEFORE the refill, so the hand "
			+ "the refill deals is not what the grid is judged by",
			"committed %d, %d slot(s) hold a card"
			% [_game.state.committed_grid, _filled_entrance_slots()])
	check(_filled_entrance_slots() > 0,
			"...and the refill still ran, so the player has a hand again",
			"%d slot(s) hold a card" % _filled_entrance_slots())

#THE PAYOFF: a placement onto a grid that is not the committed one is REFUSED outright, so the
#freed commitment is the only thing that lets the next hand choose the other grid.
	var other := 1 - home
	_pa.focus_grid(other)
	await _settle_layout()
	var next := await _lift_the_leftmost()
	await _settle_layout()
	var next_cell := await _legal_cell_control_in_grid(next, other) if next else null
	check(next != null and next_cell != null,
			"precondition: a card from the refilled Entrance, and a cell on the OTHER grid that "
			+ "accepts it", "held %s, cell %s" % [next != null, next_cell != null])
	if next and next_cell:
		var next_at := _control_centre(next_cell)
		await _drag(next_at, next_at)
		check(_placed_cards().has(next) and _game.state.committed_grid == other,
				"...and the next hand commits to the OTHER grid, which a still-committed board "
				+ "would have refused",
				"committed %d (was %d), %s"
				% [_game.state.committed_grid, home, _hand_str()])
	await _end_fixture()

#A ONE-GRID SHOW HAS NOTHING TO CHOOSE, so it commits as it opens (owner ruling): the Entrance is
#under the grid on the opening frame, and the first placement moves it nowhere.
func test_a_one_grid_show_commits_as_it_opens() -> void:
	await _start_fixture()
	check(_game.state.grids.size() == 1, "precondition: the dealt show has exactly one grid",
			"%d grid(s)" % _game.state.grids.size())
	check(_game.state.committed_grid == 0,
			"a one-grid show commits its Entrance to the only grid as it OPENS, with nothing placed",
			"committed %d, %s" % [_game.state.committed_grid, _hand_str()])
	check(_pa.entrance_home_grid() == 0,
			"...so the Entrance's home is that grid from the first frame",
			"home %d, %.2f px off grid 0"
			% [_pa.entrance_home_grid(), _entrance_off_grid_px(0)])
	var before := _pa.entrance_h_track.position.x
	var held := await _lift_the_leftmost()
	await _settle_layout()
	var cell := await _legal_cell_control_in_grid(held, 0) if held else null
	check(held != null and cell != null, "precondition: a card lifted and a cell that accepts it",
			"held %s, cell %s" % [held != null, cell != null])
	if not (held and cell):
		await _end_fixture()
		return
	var at := _control_centre(cell)
	await _drag(at, at)
	await _settle_layout()
	check(_placed_cards().has(held)
			and absf(_pa.entrance_h_track.position.x - before) <= 0.01,
			"...and the FIRST placement moves the row NOWHERE: it is already where it belongs",
			"x %.2f -> %.2f, committed %d"
			% [before, _pa.entrance_h_track.position.x, _game.state.committed_grid])
	await _end_fixture()

#A SPENT HAND FREES THE COMMITTED GRID SO ANOTHER CAN BE CHOSEN -- and with one grid there is no
#other, so the opening commitment stands and the Entrance never returns to the centre.
func test_a_one_grid_commitment_survives_a_used_up_entrance() -> void:
	await _start_fixture()
	if not await _spend_the_last_entrance_card(0):
		await _end_fixture()
		return
	check(_game.state.committed_grid == 0,
			"using the Entrance up leaves a ONE-grid commitment standing: there is no other grid "
			+ "for the freed hand to choose, so lifting it would only recentre the Entrance",
			"committed %d, %d slot(s) hold a card"
			% [_game.state.committed_grid, _filled_entrance_slots()])
	check(_pa.entrance_home_grid() == 0 and is_equal_approx(_pa._entrance_slide, 1.0),
			"...so the Entrance stays under the grid across the refill",
			"home %d, travelled %.3f" % [_pa.entrance_home_grid(), _pa._entrance_slide])
	await _end_fixture()

# ==============================================================================
# A DRAG PAN NEEDS THE BUTTON HELD, AND ENDS ON A GRID.
# ==============================================================================

## The scroll container's own drag latch: true while it believes the button is still down.
func _content_dragging() -> bool:
	return (_pa.scroll_container as SmoothScrollContainer).input_handler.content_dragging

## Where the board's content sits, in the picture's own pixels: what a pan moves.
func _board_content_x() -> float:
	return _pa.top_level_vbox.global_position.x

# A point inside the board's window that no card control answers to, so a press there is a PAN and
# never a pickup. The isolating buffer leaves bare board at the window's own edges.
func _bare_board_point() -> Vector2:
	var window := _pa.scroll_container.get_global_rect()
	for step : int in 12:
		var at := Vector2(window.position.x + 4.0 + step * 6.0, window.get_center().y)
		if _pa._card_control_at(at) == null: return at
	return Vector2.INF

# A motion event that CARRIES ITS TRAVEL. SmoothScrollContainer pans by `relative` alone, so a
# motion synthesized without it moves the pointer and the board not at all.
func _motion_by(at: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = rel
	return event

## Press at `from` and carry the pointer `travel` px in four steps, leaving the button DOWN.
func _begin_pan(from: Vector2, travel: float) -> void:
	await _push(_motion(from), _picture_viewport)
	await _push(_mouse_button(from, true), _picture_viewport)
	for step : int in 4:
		await _push(_motion_by(from + Vector2(travel * (step + 1) / 4.0, 0.0),
				Vector2(travel / 4.0, 0.0)), _picture_viewport)

#THE PAN IS HELD, NOT TOGGLED. The board consumes the release before the scroll container's own
#input handler can see it, so the container's drag has to be ended here or it latches on and bare
#motion keeps panning -- which is the "clicking is a toggle to drag" the owner saw.
func test_a_drag_pan_needs_the_button_held() -> void:
	await _start_fixture_grids(3)
	_pa.focus_grid(1)
	await _settle_layout()
	var from := _bare_board_point()
	check(from != Vector2.INF, "precondition: the board window offers a point on no card to press",
			str(from))
	if from == Vector2.INF:
		await _end_fixture()
		return
	await _begin_pan(from, -120.0)
	check(_content_dragging(),
			"precondition: a press on bare board with the button still down IS a drag pan",
			"content_dragging %s" % _content_dragging())
	await _push(_mouse_button(from + Vector2(-120.0, 0.0), false), _picture_viewport)
	await _frames(2)
	check(not _content_dragging(),
			"letting the button go ends the pan: the container's own drag latch is clear even "
			+ "though the board consumed the release",
			"content_dragging %s" % _content_dragging())

	await _settle_layout()
	var resting := _board_content_x()
	for step : int in 6:
		await _push(_motion_by(from + Vector2(-140.0 - step * 20.0, 0.0), Vector2(-20.0, 0.0)),
				_picture_viewport)
	await _frames(2)
	check(is_equal_approx(_board_content_x(), resting),
			"...and bare motion afterwards moves the board not at all -- the pan needs the button "
			+ "HELD, it is not a toggle",
			"content x %.2f -> %.2f" % [resting, _board_content_x()])
	await _end_fixture()

#A CANCEL ALSO ENDS IT. The right-click press is consumed before the GUI pass exactly as the
#release is, so without this the one thing that should stop a runaway pan cannot reach it.
func test_a_cancel_ends_a_latched_drag_pan() -> void:
	await _start_fixture_grids(3)
	_pa.focus_grid(0)
	await _settle_layout()
#A CARD IS LIFTED FIRST so the cancel's own first rung is the held card and the press never reaches
#the step-out. The landing is then observable: a cancel that DOES step out lands too, but the
#overview's rest supersedes the aim on the same press, so nothing could be read from it.
	var held := await _lift_the_leftmost()
	await _settle_layout()
	var from := _bare_board_point()
	check(held != null and from != Vector2.INF,
			"precondition: a card in hand and a point on no card to press",
			"held %s, at %s" % [held != null, from])
	if held == null or from == Vector2.INF:
		await _end_fixture()
		return
	var travel := -_pa.grid_pitch_px() * 0.75 * _pa.drawn_zoom
	await _begin_pan(from, travel)
	check(_content_dragging(), "precondition: the pan is live with the button down",
			"content_dragging %s" % _content_dragging())
	check(_nearest_drawn_grid() == 1 and _pa.pan_grid == 0,
			"precondition: the drag carried grid 1 nearest the middle of the window while the "
			+ "board is still AIMED at grid 0", "nearest %d, pan_grid %d"
			% [_nearest_drawn_grid(), _pa.pan_grid])
	await _right_click(from + Vector2(travel, 0.0), false)
	await _frames(2)
	check(not _content_dragging(),
			"a right-click cancel ends a live drag pan",
			"content_dragging %s" % _content_dragging())
	check(_pa.selected_cards.is_empty() and _pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"...and spends its rung on the held card, so this press never reached the step-out",
			"held %d, mode %d" % [_pa.selected_cards.size(), _pa.view_mode])
	check(_pa.pan_grid == 1,
			"...and the cancel LANDS the grid nearest the middle of the window, exactly as a "
			+ "release does, rather than leaving the board stopped between two grids",
			"pan_grid %d, nearest %d" % [_pa.pan_grid, _nearest_drawn_grid()])
	await _settle_layout()
	await _settle_scroll_x()
	check(_nearest_drawn_grid() == 1 and _grid_off_centre_px(1) <= 1.0,
			"...and the board comes to rest with that grid centred",
			"nearest %d, %.2f px off centre" % [_nearest_drawn_grid(), _grid_off_centre_px(1)])
	var owner := _pa.get_viewport().gui_get_focus_owner()
	check(owner != null and _pa.ui_data.has(owner)
			and _pa.upper_zone_right.is_ancestor_of(owner)
			and owner.get_viewport() == _picture_viewport,
			"...and the landing's focus SURVIVES the ungrab the same press does: an Entrance stop "
			+ "in the picture's own viewport still holds the keyboard",
			_where_focus_is())
	await _end_fixture()

#THE STEP-OUT SUPERSEDES THE LANDING ON THE SAME PRESS, and that is the order: the landing rides the
#press first, then the ladder spends it, and the overview it steps out to rests where it rests.
func test_a_cancel_that_steps_out_lands_first_and_is_superseded() -> void:
	await _start_fixture_grids(3)
	_pa.focus_grid(0)
	await _settle_layout()
	var from := _bare_board_point()
	check(from != Vector2.INF, "precondition: a point on no card to press", str(from))
	if from == Vector2.INF:
		await _end_fixture()
		return
	var travel := -_pa.grid_pitch_px() * 0.75 * _pa.drawn_zoom
	await _begin_pan(from, travel)
	check(_content_dragging() and _pa.selected_cards.is_empty(),
			"precondition: a live pan with nothing held and no description to dismiss",
			"content_dragging %s, held %d" % [_content_dragging(), _pa.selected_cards.size()])
	await _right_click(from + Vector2(travel, 0.0), false)
	await _frames(2)
	check(not _content_dragging() and _pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"with no higher rung to spend the same press ends the pan AND steps out to the "
			+ "every-grid view -- the one-thing-per-press ladder is unchanged",
			"content_dragging %s, mode %d" % [_content_dragging(), _pa.view_mode])
	await _settle_layout()
	await _settle_scroll_x()
	check(_pa.pan_grid == _pa.resting_grid(),
			"...and the overview rests where IT rests, so the landing the press made first is "
			+ "superseded rather than fought over",
			"pan_grid %d, resting %d" % [_pa.pan_grid, _pa.resting_grid()])
	var owner := _pa.get_viewport().gui_get_focus_owner()
	check(owner != null and _pa.ui_data.has(owner)
			and _pa.upper_zone_right.is_ancestor_of(owner)
			and owner.get_viewport() == _picture_viewport,
			"...and stepping out leaves the landing's focus on an Entrance stop in the picture's "
			+ "own viewport, never on a control the overview freed",
			_where_focus_is())
	await _end_fixture()

#THE RELEASE LANDS ON A GRID, as if Left or Right had been pressed: the board does not stop wherever
#the finger left it. The Entrance follows the grid it belongs to, which is the (e) rule and needs
#nothing of its own here.
func test_a_drag_pan_release_lands_on_the_grid_nearest_the_centre() -> void:
	await _start_fixture_grids(3)
	_pa.focus_grid(0)
	await _settle_layout()
	check(_pa.pan_grid == 0 and _nearest_drawn_grid() == 0,
			"precondition: the board is centred on grid 0", "pan_grid %d, nearest %d"
			% [_pa.pan_grid, _nearest_drawn_grid()])
	var from := _bare_board_point()
	check(from != Vector2.INF, "precondition: a point on no card to press", str(from))
	if from == Vector2.INF:
		await _end_fixture()
		return

#PART OF THE WAY TO GRID 1 AND NO FURTHER: the release is what has to finish the journey, so it is
#let go while the board sits between two grids.
	var travel := -_pa.grid_pitch_px() * 0.75 * _pa.drawn_zoom
	await _begin_pan(from, travel)
	await _frames(2)
	var mid := _nearest_drawn_grid()
	check(mid == 1,
			"precondition: the drag carried grid 1 nearest the middle of the window without the "
			+ "board ever being aimed there",
			"nearest %d, pan_grid %d, travelled %.1f px, grid 1 is %.1f px off centre"
			% [mid, _pa.pan_grid, travel, _grid_off_centre_px(1)])
	await _push(_mouse_button(from + Vector2(travel, 0.0), false), _picture_viewport)
	await _frames(2)
	check(_pa.pan_grid == 1,
			"the release aims the board at the grid nearest the middle of the window, as Left and "
			+ "Right do", "pan_grid %d" % _pa.pan_grid)
	await _settle_layout()
	await _settle_scroll_x()
	check(_nearest_drawn_grid() == 1 and _grid_off_centre_px(1) <= 1.0,
			"...and the board comes to rest with that grid centred, not wherever the pointer left "
			+ "it", "nearest %d, %.2f px off centre"
			% [_nearest_drawn_grid(), _grid_off_centre_px(1)])
	await _end_fixture()

#A DRAG PAN IS A POINTER GESTURE AND THE POINTER ENDS IT, so the release hands the keyboard a
#place to carry on from: the Entrance card nearest where the button came up (owner ruling).
func test_a_drag_pan_release_focuses_an_entrance_card() -> void:
	await _start_fixture_grids(3)
	_pa.focus_grid(0)
	await _settle_layout()
#THE LEFTMOST SLOT IS SPENT -- no card left in it and no stock under it -- so its own zone card is
#still an arrow stop while holding nothing. That is the stop the focus must NOT settle on.
	_empty_the_entrance_slot(0)
	await _settle_layout()
	var entrance := _entrance_controls()
	var from := _bare_board_point()
	check(entrance.size() >= 2 and not _is_a_card_in_hand(entrance[0])
			and _is_a_card_in_hand(entrance[1]),
			"precondition: the leftmost Entrance stop holds NO card and a stop further along does",
			"%d stop(s), leftmost holds a card: %s" % [entrance.size(),
			entrance.is_empty() or _is_a_card_in_hand(entrance[0])])
	check(from != Vector2.INF, "precondition: a point on no card to press", str(from))
	if entrance.size() < 2 or from == Vector2.INF or _is_a_card_in_hand(entrance[0]):
		await _end_fixture()
		return
#THE RELEASE COMES UP OVER THE SPENT SLOT, so the nearest stop of all and the nearest stop HOLDING
#A CARD are different controls -- which is the whole of what this row discriminates.
	var at := _control_centre(entrance[0])
	entrance[entrance.size() - 1].grab_focus()
	await get_tree().process_frame
	await _begin_pan(from, at.x - from.x)
	await _push(_mouse_button(Vector2(at.x, from.y), false), _picture_viewport)
	await _frames(2)
	var owner := _pa.get_viewport().gui_get_focus_owner()
	check(owner != null and _pa.ui_data.has(owner)
			and _pa.upper_zone_right.is_ancestor_of(owner),
			"the release puts the keyboard focus on an Entrance stop", _where_focus_is())
	check(owner != null and _is_a_card_in_hand(owner),
			"...one that HOLDS A CARD, so the first accept from there picks one up -- never the "
			+ "spent slot the pointer came up over", _where_focus_is())
	check(owner == entrance[1],
			"...the nearest card-holding stop to the x the button came up at",
			"%s, wanted stop 1 of %d, released at x %.1f"
			% [_where_focus_is(), entrance.size(), at.x])
	check(owner != null and owner.get_viewport() == _picture_viewport,
			"...and it is focused in the PICTURE's own viewport, where the next arrow is read",
			"%s" % [owner.get_viewport() if owner else null])

#NO STOP HOLDS A CARD AT ALL -- the Entrance between its last placement and its refill. There is
#nothing to prefer, so the chain's own leftmost stop takes the focus.
	for slot : int in _game.state.upper_zone.size():
		_empty_the_entrance_slot(slot)
	await _settle_layout()
	var spent := _entrance_controls()
	check(not spent.is_empty() and not _is_a_card_in_hand(spent[0]),
			"precondition: every Entrance stop is a spent slot now", "%d stop(s)" % spent.size())
	if spent.is_empty():
		await _end_fixture()
		return
	spent[spent.size() - 1].grab_focus()
	await get_tree().process_frame
	var back := _bare_board_point()
	await _begin_pan(back, _control_centre(spent[spent.size() - 1]).x - back.x)
	await _push(_mouse_button(Vector2(_control_centre(spent[0]).x, back.y), false),
			_picture_viewport)
	await _frames(2)
	check(_pa.get_viewport().gui_get_focus_owner() == spent[0],
			"with no card anywhere in the Entrance the LEFTMOST stop takes the focus, which is "
			+ "where the arrow chain starts", _where_focus_is())
	await _end_fixture()

## Empties one Entrance slot the way a show does: its card played, and its stock run dry under it.
func _empty_the_entrance_slot(slot: int) -> void:
	_game.state.upper_zone[slot].datas.clear()
	_game.state.entrance_stocks()[slot].datas.clear()
	_pa.flush_rebuild()

## Does this control draw a card the Entrance still HOLDS -- one an accept could pick up?
func _is_a_card_in_hand(control: Control) -> bool:
	var data : CardData = _pa.ui_data.get(control)
	if data == null: return false
	for column : ArrayCardData in _game.state.upper_zone:
		if column.datas.has(data): return true
	return false

#A PAD OR KEY PAN IS NOT A POINTER GESTURE: the aim moves, the focus does not. `pan_by_grids` is
#the whole of what `grid_pan_left`/`grid_pan_right` do.
func test_a_key_pan_leaves_the_focus_where_it_was() -> void:
	await _start_fixture_grids(3)
	_pa.focus_grid(0)
	await _settle_layout()
	var entrance := _entrance_controls()
	check(entrance.size() >= 2, "precondition: the Entrance offers two or more focus stops",
			"%d stop(s)" % entrance.size())
	if entrance.size() < 2:
		await _end_fixture()
		return
	var held : Control = entrance[entrance.size() - 1]
	held.grab_focus()
	await get_tree().process_frame
	_pa.pan_by_grids(1)
	await _settle_layout()
	check(_pa.get_viewport().gui_get_focus_owner() == held,
			"a key pan re-aims the board and leaves the focus exactly where the player put it",
			"%s, pan_grid %d" % [_where_focus_is(), _pa.pan_grid])
	await _end_fixture()

## Which control holds the board's focus, named for a failure message.
func _where_focus_is() -> String:
	var owner := _pa.get_viewport().gui_get_focus_owner()
	if owner == null: return "focus owner: none"
	var stops := _entrance_controls()
	var at := stops.find(owner)
	if at != -1: return "focus owner: Entrance stop %d of %d" % [at, stops.size()]
	return "focus owner: %s" % owner.name

## How far grid `gi`'s cell block is from the middle of the board's window, drawn.
func _grid_off_centre_px(gi: int) -> float:
	return absf(_drawn_centre_x(_pa._cells_root(_pa.grid_container.get_child(gi) as Control))
			- _drawn_centre_x(_pa.scroll_container))

## Wait for the board's own scroll to stop: the pan eases, and `_settle_layout` alone can return inside it.
func _settle_scroll_x() -> void:
	var last := INF
	var waited := 0.0
	while waited < 3.0:
		await get_tree().physics_frame
		await get_tree().process_frame
		waited += get_process_delta_time()
		if is_equal_approx(_board_content_x(), last): return
		last = _board_content_x()

# ==============================================================================
# THE CANCEL LADDER: HELD CARD, DESCRIPTION, THE EVERY-GRID VIEW, THE WALL.
# ==============================================================================

# ⚠ WHETHER THE WALL TOOK ITS STEP IS THE ONLY HONEST READING of "the board consumed it": the rung
# below the board belongs to the wall, and a press the board kept never reaches it. Boxed in an
# Array because a lambda captures an outer local BY VALUE.
func _watch_for_wall_view() -> Array[bool]:
	var left : Array[bool] = [false]
	_main.wall.wall_view_entered.connect(func() -> void: left[0] = true)
	return left

#ONE RUNG PER PRESS FOR THE SECOND BUTTON: the card, then the description it was read against, then
#the grid itself. Stepping out of the grid is the rung the owner found missing -- without it a
#cancel could not get back to the every-grid view to choose another grid.
func test_the_second_button_cancels_one_rung_per_press() -> void:
	await _start_fixture_grids(3)
	var lifted := await _lift_the_leftmost()
	await _settle_layout()
	check(lifted != null and _pa.locked_data == lifted
			and _pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"precondition: a click left a card held, its description locked, one grid focused",
			"held %s, locked %s, mode %d"
			% [lifted != null, _pa.locked_data != null, _pa.view_mode])
	var quiet := _bare_board_point()
	check(quiet != Vector2.INF, "precondition: a point on no card for the second button",
			str(quiet))
	if lifted == null or quiet == Vector2.INF:
		await _end_fixture()
		return
	var focused := _pa.focused_grid

	await _right_click(quiet, false)
	await _frames(2)
	check(_pa.selected_cards.is_empty() and _pa.locked_data == lifted
			and _pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"RUNG 1 -- the first press lets the card go, and takes neither the description nor "
			+ "the grid with it",
			"held %d, locked %s, mode %d"
			% [_pa.selected_cards.size(), _pa.locked_data != null, _pa.view_mode])

	await _right_click(quiet, false)
	await _frames(2)
	check(_pa.locked_data == null and _pa.view_mode == PlayArea.ViewMode.FOCUSED
			and _pa.focused_grid == focused,
			"RUNG 2 -- the second press takes the description down, and the board is still "
			+ "focused on the same grid",
			"locked %s, mode %d, focused %d"
			% [_pa.locked_data != null, _pa.view_mode, _pa.focused_grid])

	await _right_click(quiet, false)
	await _frames(2)
	check(_pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"RUNG 3 -- the third press steps out of the grid to the EVERY-GRID view, where "
			+ "another grid can be chosen",
			"mode %d, focused %d" % [_pa.view_mode, _pa.focused_grid])
	check(_pa._zoom_out_grid == focused,
			"...and it remembered the grid it left, so Forward returns to it",
			"zoom out grid %d, was focused on %d" % [_pa._zoom_out_grid, focused])
	await _settle_layout()

	await _right_click(quiet, false)
	await _frames(2)
	check(_pa.view_mode == PlayArea.ViewMode.OVERVIEW,
			"RUNG 4 -- a press in the every-grid view takes no board step of its own: the level "
			+ "below the board is the wall's",
			"mode %d" % _pa.view_mode)
	await _end_fixture()

#ESCAPE SPENDS ITSELF ON THE CARD AND THE DESCRIPTION IN ONE PRESS and still leaves for wall view --
#the owner's rule, unchanged. It does NOT step out of the grid on top of that.
func test_an_escape_with_something_to_spend_still_reaches_the_wall() -> void:
	await _start_fixture_grids(3)
	var lifted := await _lift_the_leftmost()
	await _settle_layout()
	check(lifted != null and _pa.locked_data == lifted
			and _pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"precondition: a card held, its description locked, one of three grids focused",
			"held %s, locked %s, mode %d"
			% [lifted != null, _pa.locked_data != null, _pa.view_mode])
	if lifted == null:
		await _end_fixture()
		return
	var left := _watch_for_wall_view()
	await _escape_press()
	check(_pa.selected_cards.is_empty() and _pa.locked_data == null,
			"one Escape lets the card go AND takes the description down, in the same press",
			"held %d, locked %s" % [_pa.selected_cards.size(), _pa.locked_data != null])
	check(_pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"...and does NOT step out of the grid on top of that: the press was already spent",
			"mode %d" % _pa.view_mode)
	check(left[0],
			"...so the wall still hears it and takes its own step out of the screen",
			"wall view entered %s" % left[0])
	await _end_fixture()

#WITH NOTHING TO SPEND, ESCAPE TAKES THE SAME RUNG THE SECOND BUTTON DOES -- and the wall does not
#get that press, because the board still had a level of its own to give.
func test_an_escape_with_nothing_to_spend_steps_out_of_the_grid_first() -> void:
	await _start_fixture_grids(3)
#A THREE-GRID SHOW OPENS ON THE EVERY-GRID VIEW, so the grid this row steps out of is focused here.
	_pa.focus_grid(1)
	await _settle_layout()
	check(_pa.view_mode == PlayArea.ViewMode.FOCUSED and _pa.selected_cards.is_empty()
			and _pa.locked_data == null,
			"precondition: one of three grids focused, nothing held, nothing stuck",
			"mode %d, held %d, locked %s"
			% [_pa.view_mode, _pa.selected_cards.size(), _pa.locked_data != null])
	var focused := _pa.focused_grid
	var left := _watch_for_wall_view()
	await _escape_press()
	check(_pa.view_mode == PlayArea.ViewMode.OVERVIEW and _pa._zoom_out_grid == focused,
			"an Escape with nothing to let go and nothing to dismiss steps out of the grid to the "
			+ "every-grid view", "mode %d, zoom out grid %d" % [_pa.view_mode, _pa._zoom_out_grid])
	check(not left[0],
			"...and the wall does NOT take that press: the board's own level comes first",
			"wall view entered %s" % left[0])
	await _settle_layout()

	await _escape_press()
	check(_pa.view_mode == PlayArea.ViewMode.OVERVIEW and left[0],
			"...and the NEXT press, with no board level left to give, is the wall's",
			"mode %d, wall view entered %s" % [_pa.view_mode, left[0]])
	await _end_fixture()

#ONE GRID IS NOT A LEVEL. The overview frames exactly what the focused view frames, so a cancel on a
#one-grid board has nothing to step out to and the press belongs to the wall.
func test_a_one_grid_board_has_no_grid_to_step_out_of() -> void:
	await _start_fixture()
	check(_pa.grid_container.get_child_count() == 1
			and _pa.view_mode == PlayArea.ViewMode.FOCUSED,
			"precondition: a one-grid show opens focused on its only grid",
			"%d grid(s), mode %d" % [_pa.grid_container.get_child_count(), _pa.view_mode])
	var quiet := _bare_board_point()
	check(quiet != Vector2.INF, "precondition: a point on no card", str(quiet))
	if quiet != Vector2.INF:
		await _right_click(quiet, false)
		await _frames(2)
		check(_pa.view_mode == PlayArea.ViewMode.FOCUSED,
				"a second-button cancel on a one-grid board does not zoom out to an every-grid "
				+ "view of one grid", "mode %d" % _pa.view_mode)
	var left := _watch_for_wall_view()
	await _escape_press()
	check(_pa.view_mode == PlayArea.ViewMode.FOCUSED and left[0],
			"...and Escape still reaches the wall from it, never kept by a level that is not there",
			"mode %d, wall view entered %s" % [_pa.view_mode, left[0]])
	await _end_fixture()

# ==============================================================================
# THE KEYS ALONE — every press a real key pushed into the booted window, no pointer anywhere.
# ==============================================================================

#DOWN OFF THE BOTTOM ROW IS THE ENTRANCE'S DOOR and Up is the way back, at one grid and at two: a
#keyboard player has no other way onto an Entrance card, so without it nothing can be lifted.
func test_the_keys_reach_the_entrance_and_come_back() -> void:
	for n : int in [1, 2]:
		await _open_a_grid_by_keys(n)
		await _tap_to_the_bottom_row()
		await _tap(KEY_RIGHT)
		await _tap(KEY_RIGHT)
		var from := _focus_owner()
		var cell := _pa._coord_of_control(from)
		check(not cell.is_nowhere() and cell.y == _game.state.grids[cell.grid].grid_height - 1,
				"precondition (%d grid(s)): the keys put the focus on a bottom-row cell" % n,
				_where_focus_is())
		var column_x := _control_centre(from).x
		await _tap(KEY_DOWN)
		var landed := _focus_owner()
		check(landed != null and landed == _nearest_card_holding_stop(column_x),
				"Down off the bottom row lands on the Entrance card nearest the column (%d grid(s))"
				% n, _where_focus_is())
		await _tap(KEY_UP)
		check(_focus_owner() == from,
				"...and Up from that card comes back to the cell above it (%d grid(s))" % n,
				_where_focus_is())
		if landed != null and _pa.ui_data.has(landed):
			_empty_the_entrance_slot(_pa._entrance_slot_holding(_game.state, _pa.ui_data[landed]))
			await _settle_layout()
			await _tap(KEY_DOWN)
			var holding := _focus_owner()
			check(holding != null and _is_a_card_in_hand(holding)
					and holding == _nearest_card_holding_stop(column_x),
					"...and with the slot under the column spent, Down takes the nearest stop that "
					+ "still HOLDS a card (%d grid(s))" % n, _where_focus_is())
		await _end_fixture()

#THE WHOLE ROUTE BY KEYS: onto the Entrance, lift, into the grid, onto a legal cell, place -- then
#lift again and cancel.
func test_the_keys_alone_lift_place_and_cancel() -> void:
	for n : int in [1, 2]:
		await _open_a_grid_by_keys(n)
		var card := await _lift_by_keys()
		check(card != null and _held_card() == card,
				"the keys reach an Entrance card and accept lifts it (%d grid(s))" % n,
				"%s, %s" % [_where_focus_is(), _hand_str()])
		if card == null:
			await _end_fixture()
			continue
		var placed_before := _placed_cards().size()
		await _place_by_keys(card)
		check(_held_card() == null and _placed_cards().has(card)
				and _placed_cards().size() == placed_before + 1,
				"Up, the arrows and accept on a cell place the lifted card (%d grid(s))" % n,
				_hand_str())
		var lifted := await _lift_by_keys()
		check(lifted != null and _held_card() == lifted,
				"the keys reach the Entrance again and lift the next card (%d grid(s))" % n,
				_hand_str())
		await _tap(KEY_ESCAPE)
		check(_held_card() == null and _pa._entrance_slot_holding(_game.state, lifted) != -1,
				"...and cancel lets it go, back in the Entrance (%d grid(s))" % n, _hand_str())
		await _end_fixture()

#A CARD IN HAND IS AIMED WITH THE ARROWS: Up from the Entrance goes into the grid and leaves the
#stuck description standing; the X is reached by Left into the sidebar (owner ruling).
func test_up_with_a_card_in_hand_stays_on_the_board() -> void:
	await _open_a_grid_by_keys(1)
	var card := await _lift_by_keys()
	check(card != null and _container.is_locked(),
			"precondition: a key lift holds the card and sticks its description", _hand_str())
	await _tap(KEY_UP)
	var into := _pa._coord_of_control(_focus_owner())
	check(not into.is_nowhere() and not into.is_entrance() and _held_card() == card,
			"Up with a card in hand lands on a grid cell, the card still held",
			"%s, %s" % [_where_focus_is(), _hand_str()])
	check(_viewport.gui_get_focus_owner() == null and _container.is_locked(),
			"...never on the X, and the description stays stuck",
			str(_viewport.gui_get_focus_owner()))
	for _i : int in _grid_width_sum() + 1:
		if _viewport.gui_get_focus_owner() != null: break
		await _tap(KEY_LEFT)
	check(_viewport.gui_get_focus_owner() == _container.get_node(^"%ExitX"),
			"...and Left off the grid's edge reaches the X", str(_viewport.gui_get_focus_owner()))
	await _end_fixture()

#WITH A CARD IN HAND THE AIM STAYS ON THE GRID: Down off the bottom row moves nothing, so the next
#accept still places the held card instead of picking up an Entrance card (owner ruling).
func test_down_with_a_card_in_hand_moves_nothing() -> void:
	await _open_a_grid_by_keys(1)
	var card := await _lift_by_keys()
	await _tap(KEY_UP)
	var bottom := _focus_owner()
	var cell := _pa._coord_of_control(bottom)
	check(card != null and not cell.is_nowhere() and not cell.is_entrance()
			and cell.y == _game.state.grids[cell.grid].grid_height - 1,
			"precondition: a card in hand and the focus on a bottom-row cell", _where_focus_is())
	await _tap(KEY_DOWN)
	check(_focus_owner() == bottom and _held_card() == card,
			"Down off the bottom row with a card in hand leaves the focus on the cell",
			"%s, %s" % [_where_focus_is(), _hand_str()])
	await _end_fixture()

#THE ENTRANCE UNDER ANOTHER GRID IS STILL THE DOOR: Down off this grid's bottom row focuses it and
#brings the view to the grid it is committed to (owner ruling).
func test_down_under_another_grid_carries_the_view_to_the_entrance() -> void:
	await _open_a_grid_by_keys(2)
	var card := await _lift_by_keys()
	if card != null: await _place_by_keys(card)
	check(_game.state.committed_grid == 0 and _held_card() == null,
			"precondition: a key placement committed the Entrance to grid 0",
			"committed %d, %s" % [_game.state.committed_grid, _hand_str()])
	await _tap_until_in_grid(1, KEY_RIGHT)
	await _tap_to_the_bottom_row()
	check(_pa.focused_grid == 1 and _pa._coord_of_control(_focus_owner()).grid == 1,
			"precondition: the keys carried the focus onto grid 1's bottom row", _where_focus_is())
	await _tap(KEY_DOWN)
	await _settle_scroll_x()
	var leftmost : Control = null
	for stop : Control in _entrance_controls():
		if _is_a_card_in_hand(stop):
			leftmost = stop
			break
	check(leftmost != null and _focus_owner() == leftmost,
			"Down off grid 1's bottom row focuses the Entrance's leftmost card", _where_focus_is())
	check(_pa.focused_grid == 0 and _pa.pan_grid == 0 and _grid_off_centre_px(0) <= 1.0,
			"...and the view comes to rest on grid 0, the grid the Entrance is committed to",
			"focused %d, pan_grid %d, grid 0 %.2f px off centre"
			% [_pa.focused_grid, _pa.pan_grid, _grid_off_centre_px(0)])
	await _end_fixture()

#A PAIR IS TWO ACCEPTS ON ONE CARD: a lift and a placement on a cell land inside the tap window when
#played quickly, and they must place, never tap the lifted card back.
func test_a_lift_and_a_quick_placement_never_pair_into_a_tap() -> void:
	await _open_a_grid_by_keys(1)
	var window := PlayArea.settings().card_tap_window_ms
	PlayArea.settings().card_tap_window_ms = PUSHED_PAIR_WINDOW_MS
	var stop := await _tap_down_to_the_entrance()
	var card : CardData = _pa.ui_data[stop] if stop and _is_a_card_in_hand(stop) else null
	var elapsed := INF
	if card != null:
		var lifted_at := Time.get_ticks_msec()
		await _tap(KEY_ENTER)
		await _tap(KEY_UP)
		await _tap_to_a_legal_cell(card)
		elapsed = float(Time.get_ticks_msec() - lifted_at)
		await _tap(KEY_ENTER)
		await _await_the_deal()
	PlayArea.settings().card_tap_window_ms = window
	check(card != null and elapsed <= PUSHED_PAIR_WINDOW_MS and _held_card() == null
			and _placed_cards().has(card) and _taps.is_empty(),
			"a lift and a placement inside the tap window place the card and tap nothing",
			"%.0f ms between the accepts (window %.0f), %s, %d tap(s)"
			% [elapsed, PUSHED_PAIR_WINDOW_MS, _hand_str(), _taps.size()])
	await _end_fixture()

## Down onto the Entrance and accept: the card now in hand, or null when the keys never reached one.
func _lift_by_keys() -> CardData:
	var stop := await _tap_down_to_the_entrance()
	if stop == null or not _is_a_card_in_hand(stop): return null
	var card : CardData = _pa.ui_data[stop]
	await _tap(KEY_ENTER)
	return card

## Up into the grid, the arrows to a cell `card` may land on, and accept.
func _place_by_keys(card: CardData) -> void:
	await _tap(KEY_UP)
	await _tap_to_a_legal_cell(card)
	await _tap(KEY_ENTER)
	await _await_the_deal()

func _tap_until_in_grid(gi: int, code: Key) -> void:
	for _i : int in _grid_width_sum():
		if _pa._coord_of_control(_focus_owner()).grid == gi: return
		await _tap(code)

func _tap(code: Key) -> void:
	_viewport.push_input(_key(code, true))
	await get_tree().process_frame
	_viewport.push_input(_key(code, false))
	await _frames(3)
	await _settle_layout()

func _focus_owner() -> Control:
	return _picture_viewport.gui_get_focus_owner()

## A fresh show on `n` grids, left on grid 0 focused the way a keyboard player gets there.
func _open_a_grid_by_keys(n: int) -> void:
	if n == 1:
		await _start_fixture()
		return
	await _start_fixture_grids(n)
	await _tap(KEY_ENTER)
	check(_pa.view_mode == PlayArea.ViewMode.FOCUSED and _pa.focused_grid == 0,
			"precondition: accept in the overview focuses the selected grid",
			"mode %d, focused %d" % [_pa.view_mode, _pa.focused_grid])

func _tap_to_the_bottom_row() -> void:
	for _i : int in _game.state.grids[0].grid_height:
		var cell := _pa._coord_of_control(_focus_owner())
		if cell.is_nowhere() or cell.y == _game.state.grids[cell.grid].grid_height - 1: return
		await _tap(KEY_DOWN)

func _tap_down_to_the_entrance() -> Control:
	for _i : int in _game.state.grids[0].grid_height + 1:
		if _entrance_controls().has(_focus_owner()): return _focus_owner()
		await _tap(KEY_DOWN)
	return _focus_owner() if _entrance_controls().has(_focus_owner()) else null

## The Entrance stop holding a card whose centre is nearest `x`: the test's own answer.
func _nearest_card_holding_stop(x: float) -> Control:
	var best : Control = null
	var best_dx := INF
	for stop : Control in _entrance_controls():
		if not _is_a_card_in_hand(stop): continue
		var dx := absf(_control_centre(stop).x - x)
		if dx >= best_dx: continue
		best_dx = dx
		best = stop
	return best

func _tap_to_a_legal_cell(card: CardData) -> void:
	var keys := await TestGridFixtures.arrow_keys_to_a_legal_cell(
			_pa._coord_of_control(_focus_owner()), card)
	for key : Key in keys:
		await _tap(key)

func _grid_width_sum() -> int:
	var total := 0
	for grid : GridData in _game.state.grids:
		total += grid.grid_width
	return total

# ==============================================================================
# ONE RIM -- the Entrance card and the grid cell wear the same focus outline
# ==============================================================================

func test_a_focused_entrance_card_wears_the_rim_a_focused_cell_does() -> void:
	await _start_fixture()
	var card : CardData = _pa.ui_data[_entrance_controls()[0]]
	var visual : CardVisual = _pa.data_card[card]
	var own := Vector2i(visual.outline_style().outline_index, visual.outline_style().width)
	check(_rim_ink_and_width(visual) == own,
			"unfocused, an Entrance card wears its own type's rim",
			"%s, own %s" % [_rim_ink_and_width(visual), own])
	await _focus_the_card(card)
	var entrance_rim := _rim_ink_and_width(visual)
	var cell := _reachable_cells()[0]
	cell.grab_focus()
	await get_tree().process_frame
	var cell_rim := _rim_ink_and_width(_pa.data_card[_pa.ui_data[cell]])
	check(entrance_rim == cell_rim and entrance_rim.x == PaletteDB.ROLES.match_rim,
			"a focused Entrance card wears the rim a focused cell wears, ink and width",
			"Entrance %s, cell %s" % [entrance_rim, cell_rim])
	await _end_fixture()

func _rim_ink_and_width(visual: CardVisual) -> Vector2i:
	var mat := CardOutline.material_of(visual.type)
	return Vector2i(mat.get_shader_parameter(&"u_outline_index") as int,
			mat.get_shader_parameter(&"u_outline_width") as int)

# ==============================================================================
# THE FOCUSED CELL'S RIM FOLLOWS WHAT ITS FOCUSED CONTROL NOW SHOWS -- a rebind moves no focus.
# ==============================================================================

func test_a_click_placement_onto_the_focused_cell_rims_the_card() -> void:
	await _start_fixture()
	await _click_the_leftmost_onto_the_origin()
	await _end_fixture()

func test_a_drag_placement_onto_the_focused_cell_rims_the_card() -> void:
	await _start_fixture()
	var entrance := _entrance_controls()
	var dragged : CardData = _pa.ui_data[entrance[0]] if not entrance.is_empty() else null
	var origin := _resting_focus_control()
	if _origin_is_ready(dragged, origin):
		await _drag(_control_centre(entrance[0]), _control_centre(origin))
		_check_the_rim_is_on_the_top_card(dragged, "a drag")
	await _end_fixture()

func test_a_key_placement_onto_the_focused_cell_rims_the_card() -> void:
	await _open_a_grid_by_keys(1)
	var held := await _lift_by_keys()
	await _tap(KEY_UP)
	await _tap_to_the_origin_cell()
	if _origin_is_ready(held, _focus_owner()):
		await _tap(KEY_ENTER)
		await _await_the_deal()
		_check_the_rim_is_on_the_top_card(held, "the keys")
	await _end_fixture()

func test_an_undo_hands_the_focused_cells_rim_back_to_its_mark() -> void:
	await _start_fixture()
	if await _click_the_leftmost_onto_the_origin():
		check(await _click_undo(), "the HUD's Undo button takes a real click", _hand_str())
		await _frames(8)
		_check_the_rim_is_on_the_mark("an undo")
	await _end_fixture()

func test_a_removed_top_card_hands_the_rim_back_to_its_mark() -> void:
	await _start_fixture()
	var held := await _click_the_leftmost_onto_the_origin()
	if held:
		await _game.remove_card_from_grid(held)
		await _frames(8)
		_check_the_rim_is_on_the_mark("a removal")
	await _end_fixture()

## Clicks the leftmost Entrance card onto the origin cell, which holds the focus: the card placed, or null.
func _click_the_leftmost_onto_the_origin() -> CardData:
	var held := await _lift_the_leftmost()
	var origin := _resting_focus_control()
	if not _origin_is_ready(held, origin): return null
	var at := _control_centre(origin)
	await _drag(at, at)
	_check_the_rim_is_on_the_top_card(held, "a click")
	return held

## The rows above place onto the origin cell, where a hand with nothing in it rests the focus.
func _origin_is_ready(card: CardData, origin: Control) -> bool:
	var on_screen := Rect2(Vector2.ZERO, Vector2(_picture_viewport.size))
	var usable := card != null and origin != null and origin == _resting_focus_control() \
			and _is_reachable(origin, on_screen)
	check(usable, "precondition: a card to place and the empty origin cell on screen to place it on",
			"card %s, origin %s, %s" % [card != null, origin, _hand_str()])
	return usable

func _check_the_rim_is_on_the_top_card(placed: CardData, route: String) -> void:
	var cell := _game.state.grid_position_of(placed)
	check(not cell.is_nowhere() and cell.x == 0 and cell.y == 0,
			"%s placed the card onto the origin cell, which held the focus" % route, _hand_str())
	if cell.is_nowhere(): return
	var mark := _game.state.cell_type_at(BoardCoord.new(cell.grid, cell.x, cell.y, 0))
	check(_focus_owner() == _pa.data_ui[placed],
			"...and the focus is on the placed card's own control after %s" % route,
			"%s, placed %s" % [_focus_owner(), _pa.data_ui[placed]])
	check(_pa.data_card[placed].focused and _is_outlined(placed),
			"...so the placed card wears the focus rim after %s" % route,
			"focused %s, outlined %s" % [_pa.data_card[placed].focused, _is_outlined(placed)])
	check(not _pa.data_card[mark].focused and not _is_outlined(mark),
			"...and the mark hidden under it wears none after %s" % route,
			"focused %s, outlined %s" % [_pa.data_card[mark].focused, _is_outlined(mark)])

# An undo restores the board from a copy, so the cell's cards are read back rather than kept.
func _check_the_rim_is_on_the_mark(route: String) -> void:
	var origin := BoardCoord.new(_pa.selected_grid, 0, 0, 0)
	var mark := _game.state.cell_type_at(origin)
	check(_game.state.card_at(origin) == null,
			"%s left the origin cell bare" % route, _hand_str())
	check(_pa.data_card[mark].focused and _is_outlined(mark),
			"...and its mark wears the focus rim again after %s" % route,
			"focused %s, outlined %s, owner %s" % [_pa.data_card[mark].focused, _is_outlined(mark),
			_focus_owner()])
	var rimmed : Array[CardData] = []
	for data : CardData in _pa.data_card:
		if _is_outlined(data) and data != mark: rimmed.append(data)
	check(rimmed.is_empty(), "...and no other card on the board wears it after %s" % route,
			str(rimmed))

## Left, then Up, to the grid's origin cell: the cell a placement leaves the focus resting on.
func _tap_to_the_origin_cell() -> void:
	for _i : int in _game.state.grids[0].grid_width:
		if _pa._coord_of_control(_focus_owner()).x == 0: break
		await _tap(KEY_LEFT)
	for _i : int in _game.state.grids[0].grid_height:
		if _pa._coord_of_control(_focus_owner()).y == 0: break
		await _tap(KEY_UP)

## A real click on the HUD's Undo, in the viewport it is drawn in: true when it pressed.
func _click_undo() -> bool:
	var button := _container.undo_button
	var presses : Array[int] = [0]
	button.pressed.connect(func() -> void: presses[0] += 1, CONNECT_ONE_SHOT)
	var at := button.get_global_rect().get_center()
	_viewport.push_input(_motion(at))
	await get_tree().process_frame
	_viewport.push_input(_mouse_button(at, true))
	await get_tree().process_frame
	_viewport.push_input(_mouse_button(at, false))
	await get_tree().process_frame
	return presses[0] == 1
