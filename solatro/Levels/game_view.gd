extends Control
class_name GameView
## The detachable UI/input layer for a show: owns every visual and holds a headless [Game] node; remove this view and the Game still runs headless, since every paced call is `if view: await view.<m>()`.

## Forwarded from the held Game so Main can bind the view directly; frees with its Game child.
signal game_ended
signal run_lost

## Relayed from `PlayArea` so `Main` can put a clicked card on the wall's info card.
signal info_requested(entry: InfoEntry)

## Relayed from `PlayArea` so `Main` can step its wall camera -- the board has no reach to it.
signal overview_pan_requested(grid_index: int)

## Relayed from `PlayArea` so `Main` can bounce its wall camera off the board's OVERVIEW edge.
signal overview_bounce_requested(step: int)

# Continue button sizing (win/lose screen) — named, no magic numbers in logic.
const CONTINUE_FONT_SIZE := 40
const CONTINUE_OFFSET_Y := 220.0

var game : Game = null

@onready var play_container: Control = %PlayContainer
@onready var play_area: PlayArea = %PlayArea
@onready var win_screen: Label = %WinScreen
@onready var lose_screen: Label = %LoseScreen

## The spotlight's light layer; the DIRECTOR binds in `_ready()` since it needs `game` to exist.
@onready var light_layer: LightLayer = %LightLayer
var spotlight_director : SpotlightDirector = null

## Set by `Main.enter_game()` before this view enters the tree; left null, a standalone fixture builds a private instance instead.
var hud_container : HudContainer = null

## Set by `Main` alongside `hud_container`, the same hand-over `Map` and `Menu` get -- lets a viewer opened over this screen convert the container's window px into this picture's own space.
var wall_picture : WallPicture = null

## The HUD controls, reached off `hud_container` in `_bind_hud_container()`, under the same names the scene used to own directly.
var submit_button : Button = null
var undo_button : Button = null
var deck_ui : Control = null
var discard_ui : Control = null
var rules_ui : Control = null
var goal_label : Label = null
var total_label : Label = null
var combo_label : Label = null

## `Main`'s ONE wall camera and a rect-centre-x getter, set once by `bind_wall_camera()`.
var _wall_camera : Camera2D = null
var _wall_rect_centre_x : Callable = Callable()

func _ready() -> void:
	_bind_hud_container()
	## Inject `self` before `game` enters the tree, so its _enter_tree/_ready run fully bound.
	game = Game.new()
	game.view = self
	game.processing_changed.connect(_on_processing_changed)
	game.submit_label_changed.connect(_on_submit_label_changed)
	game.show_resolved.connect(_on_show_resolved)
	game.show_unresolved.connect(_on_show_unresolved)
	game.combo_changed.connect(_on_combo_changed)
	game.game_ended.connect(func() -> void: game_ended.emit())
	game.run_lost.connect(func() -> void: run_lost.emit())
	## Bind the spotlight after `game` exists -- it IS the CardEnvironment the cue comes from.
	spotlight_director = SpotlightDirector.new()
	spotlight_director.name = "SpotlightDirector"
	add_child(spotlight_director)
	spotlight_director.bind(light_layer, play_area, game)
	## The reveal is a second listener on the same signal, so lights and layout can't disagree which section is up.
	game.spotlight_section_changed.connect(play_area.set_reveal_cards)
	_build_debug_bar()

	## Rebind HUD/board signals whenever Game swaps its state (undo/resume replace it).
	game.state_bound.connect(_on_state_bound)
	## The initial default state bypasses the setter, so it is bound by hand here.
	_bind_state(null, game.state)

	## Submit carries the End label; end_show() is the only way to finish the continuous show.
	hud_container.connect_for_screen(self, submit_button.pressed, func() -> void: game.end_show())
	hud_container.connect_for_screen(self, undo_button.pressed, _on_undo_pressed)
	var deck_button := deck_ui.get_node(^"Button") as Button
	hud_container.connect_for_screen(self, deck_button.pressed,
			func() -> void: _open_deck_viewer(sorted_stock_union(game.state), deck_button))
	var discard_button := discard_ui.get_node(^"Button") as Button
	hud_container.connect_for_screen(self, discard_button.pressed,
			func() -> void: _open_deck_viewer(game.state.discard_deck, discard_button))
	var rules_button := rules_ui.get_node(^"Button") as Button
	hud_container.connect_for_screen(self, rules_button.pressed,
			func() -> void: _open_deck_viewer(game.state.rules_deck, rules_button))
	play_area.data_selected.connect(_on_data_selected)
	play_area.card_dragged.connect(_pick_up)
	play_area.card_dropped.connect(_on_card_dropped)
	play_area.card_tapped.connect(_on_card_tapped)
	play_area.info_requested.connect(_relay_info_requested)
	play_area.highlight_cleared.connect(hud_container.return_to_lock)
	play_area.description_dismiss_requested.connect(_on_description_dismiss_requested)
	play_area.overview_pan_requested.connect(
			func(grid_index: int) -> void: overview_pan_requested.emit(grid_index))
	play_area.overview_bounce_requested.connect(
			func(step: int) -> void: overview_bounce_requested.emit(step))

	add_child(game)
	_add_prop_debug_controls()
	## Deferred: _refresh_hud early-returns before _ready finishes, so refresh once ready.
	_refresh_hud.call_deferred()
	_publish_board_inset()

# ⚠ THE SHOW'S CONTAINER STATE DIES WITH THE SHOW: `Main` reuses one screen id for every show, so
# the view leaving the tree hands back its memory, its lock and its cascade flag.
func _bind_hud_container() -> void:
	hud_container = HudContainer.ensure(hud_container, self)
	tree_exiting.connect(hud_container.release_screen.bind(HudContainer.GAME_SCREEN))
	submit_button = hud_container.submit_button
	undo_button = hud_container.undo_button
	deck_ui = hud_container.deck_ui
	discard_ui = hud_container.discard_ui
	rules_ui = hud_container.rules_ui
	goal_label = hud_container.goal_label
	total_label = hud_container.total_label
	combo_label = hud_container.combo_label
	hud_container.connect_for_screen(self, hud_container.container_rect_changed, _publish_board_inset)
	hud_container.connect_for_screen(self, hud_container.container_rect_changed, _fit_open_viewer)
	hud_container.connect_for_screen(self, hud_container.description_dismissed,
			_on_description_dismissed)

# The board wears the locked card's marking, so the view relays the lock ENDING the same way it
# relays the click that starts it. The container owns the lock itself; nothing else may clear it.
func _on_description_dismissed() -> void:
	play_area.locked_data = null

# The board publishes the ASK and the container owns whether there is anything to dismiss; the view
# is what sees both. The dismissal never spends the event -- the board consumes its own second
# button, and Escape is left for the wall's own Back so one press both cancels and steps out.
func _on_description_dismiss_requested() -> void:
	if not hud_container.showing_description(): return
	hud_container.show_hud()

## Debug prop stepping (owner tool): a toggle holds every finished tick open, and a step button releases exactly one, so a prop run can be watched tick by tick.
func _add_prop_debug_controls() -> void:
	var box := HBoxContainer.new()
	box.name = "PropDebug"
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.text = TRANSLATION.find('DEBUG_PROP_STEP_MODE')
	toggle.focus_mode = Control.FOCUS_NONE
	var step := Button.new()
	step.text = TRANSLATION.find('DEBUG_PROP_STEP_TICK')
	step.focus_mode = Control.FOCUS_NONE
	step.disabled = true
	toggle.toggled.connect(func(on: bool) -> void:
		play_area.prop_layer.manual_step = on
		step.disabled = not on)
	step.pressed.connect(func() -> void: play_area.prop_layer.step())
	box.add_child(toggle)
	box.add_child(step)
	add_child(box)
	## Bottom-right corner, growing up/left so the content never leaves the screen.
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)

# ==============================================================================
# STATE BINDING (disconnect old, connect new on every state swap)
# ==============================================================================

func _on_state_bound(new_state: GameData) -> void:
	_bind_state(_bound_state, new_state)

var _bound_state : GameData = null

func _bind_state(old_state: GameData, new_state: GameData) -> void:
	if old_state:
		if old_state.state_changed.is_connected(_refresh_hud):
			old_state.state_changed.disconnect(_refresh_hud)
		if old_state.board_changed.is_connected(_on_board_changed):
			old_state.board_changed.disconnect(_on_board_changed)
	_bound_state = new_state
	new_state.state_changed.connect(_refresh_hud)
	new_state.board_changed.connect(_on_board_changed)
	_refresh_hud()

# ==============================================================================
# GAME -> VIEW REACTIVE (signal-driven; no awaiting)
# ==============================================================================

func _refresh_hud() -> void:
	if not is_node_ready() or not game: return
	var state := game.state
	goal_label.text = str(state.goal)
	## The score is DERIVED (grid totals times the combo); there is no banked total to store.
	total_label.text = str(state.live_total())
	var combo := state.combo_mult()
	combo_label.text = TRANSLATION.find('GAME_COMBO') % combo
	## Owner ruling: the combo label hides at x1.0 rather than reading a no-op multiplier.
	combo_label.visible = combo > 1.0
	_mark_goal_met(state.has_met_goal())
	_refresh_end_reveal()

# The Goal reads as reached the instant the running total passes it, which is one beat before the
# show resolves. A palette role, never a literal, so a palette swap carries it.
func _mark_goal_met(met: bool) -> void:
	if met:
		goal_label.add_theme_color_override(&"font_color",
				PaletteDB.color(PaletteDB.ROLES.goal_met))
	else:
		goal_label.remove_theme_color_override(&"font_color")

# End is the way to finish a show that can no longer be won, so it stays hidden until the show
# CAN stop progressing: nothing left to draw anywhere, or no empty tile left to place into.
func _refresh_end_reveal() -> void:
	var state := game.state
	submit_button.visible = state.stocks_are_empty() or state.grids_are_full()

## A new combo class registered this act: refresh + pulse the combo label.
var _combo_tween : Tween = null

func _on_combo_changed(_count: int) -> void:
	_refresh_hud()
	## Pulse: same shape as BigNumberLabel.anim_pop.
	var delay := game.get_delay()
	if _combo_tween and _combo_tween.is_running():
		_combo_tween.custom_step(INF)
	combo_label.pivot_offset = combo_label.size / 2.0
	_combo_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_combo_tween.tween_property(combo_label, "scale", Vector2.ONE * 1.15, delay * .3)
	_combo_tween.tween_property(combo_label, "scale", Vector2.ONE, delay * .2)

# Board mutated (revision bump) -> coalesced rebuild at end of frame.
func _on_board_changed() -> void:
	play_area.queue_rebuild()
	_refresh_end_reveal()

# ⚠ TWO SCALES OUT OF ONE WINDOW, AND BOTH ARE RIGHT. `board_inset_*` reserves BOARD SPACE, so it
# divides by the unmargined ratio; `picture_to_window_scale` is DRAWN PIXELS, the camera's resting
# zoom, which the preview must match -- re-drawn last, once the inset has settled the board's zoom.
func _publish_board_inset() -> void:
	var window := hud_container.get_viewport().get_visible_rect().size
	var rect := hud_container.container_rect()
	var design := Vector2(PlayArea.game_picture_design_size(PlayArea.settings()))
	var picture_scale := maxf(window.x / design.x, window.y / design.y)
	play_area.picture_to_window_scale = WallPicture.focused_scale(design, window,
			PlayArea.settings().wall_overfill_margin)
	if HudContainer.container_is_top(window, PlayArea.settings()):
		play_area.board_inset_top = rect.size.y / picture_scale
		play_area.board_inset_left = 0.0
	else:
		play_area.board_inset_left = rect.size.x / picture_scale
		play_area.board_inset_top = 0.0
	hud_container.resize_preview(play_area.board_card_window_px())

## Wires `Main`'s ONE wall camera and a rect-centre-x getter. Called once, right after `Main` instantiates this view.
func bind_wall_camera(camera: Camera2D, rect_centre_x: Callable) -> void:
	_wall_camera = camera
	_wall_rect_centre_x = rect_centre_x

func _relay_info_requested(entry: InfoEntry) -> void:
	entry.relay_to(info_requested)

# The deck, discard and rules viewers are publishers exactly like the board: they hand their
# highlights to this view, which relays them the same way, and closing one hands the sidebar back
# to whatever was locked behind it.
## Every stock as ONE pile in a fixed suit-then-rank order, so neither which slot holds a card nor how soon it will be drawn leaks out of the Deck button.
static func sorted_stock_union(state: GameData) -> Array[CardData]:
	var cards := state.all_stock_cards()
	cards.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.suit.get_suit_index() != b.suit.get_suit_index():
			return a.suit.get_suit_index() < b.suit.get_suit_index()
		return a.rank.value < b.rank.value)
	return cards

func _open_deck_viewer(cards: Array[CardData], opener: Button) -> void:
	_deck_viewer = DeckViewer.show_deck(self, cards, opener)
	_deck_viewer.info_requested.connect(_relay_info_requested)
	_deck_viewer.highlight_cleared.connect(hud_container.return_to_lock)
	_fit_open_viewer()

## The viewer open over this screen, if any -- one at a time, the same one `DeckViewer` itself keeps.
var _deck_viewer : DeckViewer = null

# A VIEWER IS A SCREEN OCCUPANT LIKE THE BOARD: the container moving under it re-fits it, and a
# description that is UP is re-published at the size it now draws its cards at -- `_publish_board_inset()`
# has just re-drawn it at the BOARD's. A closed viewer leaves its reference behind.
func _fit_open_viewer() -> void:
	if not is_instance_valid(_deck_viewer): return
	_deck_viewer.fit_beside(hud_container.rect_beside(wall_picture),
			hud_container.window_scale(wall_picture))
	if hud_container.showing_description(): _deck_viewer.republish_highlight()

func _on_processing_changed(busy: bool) -> void:
	submit_button.disabled = busy
	## Undo stays enabled while busy: it cancels a live act or rewinds a resolved one, and Game ignores the press where it can't act.
	hud_container.set_processing(busy)
	if not busy: await _arm_the_entrance()

func _on_submit_label_changed(text: String) -> void:
	submit_button.text = text

## The win/lose overlay covers ONLY the play area: the board is blocked while the rest of the HUD stays clickable -- Undo rewinds the outcome, the deck/discard/rules viewers open.
var _continue_button : Button = null

# REACHING THE GOAL ENDS THE SHOW, FULL STOP: the board stops taking input, so the arm is let go
# here too -- otherwise the held card keeps following the cursor over the outcome screen.
func _on_show_resolved(won: bool, score: int, _goal: int) -> void:
	var screen : Label = win_screen if won else lose_screen
	screen.text = TRANSLATION.find('GAME_WIN_FAME') % score if won \
			else TRANSLATION.find('GAME_LOSE')
	screen.show()
	play_area.ungrab_cards()
	play_area.disable_board_focus()
	_continue_button = Button.new()
	_continue_button.text = TRANSLATION.find('GAME_CONTINUE')
	_continue_button.add_theme_font_size_override(&"font_size", CONTINUE_FONT_SIZE)
	screen.add_child(_continue_button)
	_continue_button.set_anchors_preset(Control.PRESET_CENTER)
	## Sit below the big win/lose text.
	_continue_button.position.y += CONTINUE_OFFSET_Y
	_continue_button.pressed.connect(game.exit_show)
	_continue_button.grab_focus()

## Undo at the win/lose screen: drop the overlay. The Game's normal undo rebuild restores focus.
func _on_show_unresolved() -> void:
	win_screen.hide()
	lose_screen.hide()
	## The undo's rebuild follows and re-derives header focus.
	play_area.enable_board_focus()
	if _continue_button and is_instance_valid(_continue_button):
		_continue_button.queue_free()
	_continue_button = null
	## Keyboard/controller: focus was on the freed Continue button.
	undo_button.grab_focus()

# ==============================================================================
# GAME -> VIEW PACED (injected view; Game calls `if view: await view.<m>()`)
# ==============================================================================

## Drop any live grab before the Game mutates the board underneath it.
func release_grab() -> void:
	play_area.ungrab_cards()

## Wait for a just-placed card to finish travelling to its cell.
func await_card_settled(card: CardData) -> void:
	await play_area.await_card_settled(card)

## Force a synchronous board rebuild (undo: the state reverted, no revision bump to ride).
func rebuild() -> void:
	play_area.setup_gui()
	await _arm_the_entrance()

## True once the show has rested the focus on its first armed card; it never rests it again.
var _rested_the_focus : bool = false

# THE ENTRANCE IS ALWAYS ARMED: every time the board settles with nothing held, the leftmost card
# is picked up for the player through the very pickup a click makes. A card's LIFT lives on its
# visual, so the arm waits for the deal's visuals the way a resume does.
func _arm_the_entrance() -> void:
	play_area.flush_rebuild()
	if not play_area.visuals_ready(): await play_area.board_visuals_ready
	await play_area.arm_leftmost()
	if _rested_the_focus or play_area.selected_cards.is_empty(): return
	_rested_the_focus = play_area.rest_focus_on_armed()

## Repopulate the row/col score gutters from state.scores_* (after apply_act_score clears them).
func sync_scores() -> void:
	play_area.update_score_controls()

## Rebuild EVERY board visual from the restored GameData (resume) -- the normal revision-bump rebuild path never touches the gutters, so a resume must populate both explicitly.
func load_board_visuals() -> void:
	## The gutters reserve their space FIRST, so the cards lay out against the final height rather than shifting down once the gutters are added afterwards.
	play_area.update_score_controls()
	play_area.flush_rebuild()
	## CardVisuals enter via call_deferred, so they're ready one frame later than the build call.
	if not play_area.visuals_ready():
		await play_area.board_visuals_ready
	print("[resume] cards ready: %d card visual(s), visuals_ready=%s"
			% [play_area.data_card.size(), play_area.visuals_ready()])
	play_area.update_score_controls()
	print("[resume] score gutters loaded from state: rows upper=%d lower=%d, cols=%d"
			% [game.state.scores_row_upper.size(), game.state.scores_row_lower.size(),
					game.state.scores_col_legacy.size()])

## Jump the scored cards; returns after the animation settles.
func animate_meld(result: Scoring.Result) -> void:
	await play_area.popup_meld(result)

## Floating "meld name + score" popup over the scored cards.
func show_meld_score(result: Scoring.Result) -> void:
	await play_area.popup_score(result)

## Return the scored cards to their resting position.
func reset_meld(result: Scoring.Result) -> void:
	play_area.reset_meld(result)

## Animate one gutter label to its new accumulated score.
func update_line_score(zone: Array[BigNumber], index: int, score: BigNumber) -> void:
	play_area.update_score(zone, index, score)

## The grid board's equivalent, since the legacy zone-array path can't reach keyed grid buckets.
func pop_grid_line_score(section: ScoringSection) -> void:
	play_area.pop_grid_score_label(section)

## Start one prop-simulation tick's visuals and return a signal the Game awaits for completion.
func begin_prop_tick(live: Array, spawned: Array, movers: Array, relocated: Array) -> Signal:
	return play_area.prop_layer.begin_prop_tick(live, spawned, movers, relocated)

## Undo cancelled a resolving act: free every prop visual immediately, since no later tick will.
func abort_props() -> void:
	play_area.prop_layer.abort_all()

## True while the started visual tick is still animating, so the Game's SYNC step knows whether awaiting `tick_done` would hang on an emission that already fired.
func prop_tick_pending() -> bool:
	return play_area.prop_layer.tick_pending()

# ==============================================================================
# VIEW -> GAME INPUT (selection UI here; data queries/moves are Game commands)
# ==============================================================================

func _on_undo_pressed() -> void:
	## What is held is the arm, and the arm is view-only: it is dropped here and re-derived from whatever board the undo restores.
	play_area.ungrab_cards()
	game.undo()
	await _arm_the_entrance()

# ONE CLICK, BOTH OUTCOMES: it locks the description to the card it landed on AND performs the
# board action. A landed placement finishes the interaction and takes the container back to the
# HUD; a REFUSED one leaves the description up and falls through to picking that card up instead.
func _on_data_selected(data: CardData) -> void:
	if game.processing:
		play_area.stop_following()
		return
	hud_container.lock_to(PlayArea.card_info(data, play_area.board_card_window_px()), data)
	play_area.locked_data = data
	if play_area.selected_cards:
		if data in play_area.selected_cards: return
		if await _place_held_onto(data): return
	await _pick_up(data)

# THE DRAG'S RELEASE IS ANOTHER WAY TO REACH THE SAME PLACEMENT, and nothing downstream can tell
# which route was taken. A release the board refuses returns the card instead, so a failed drag
# leaves the player where they started.
func _on_card_dropped(data: CardData) -> void:
	if game.processing: return
	if not await _place_held_onto(data): play_area.stop_following()

# A TAP UNDOES THE GRAB THE PRESS BEFORE IT MADE: the card goes back and the Entrance re-derives
# its arm, so a tap on the armed card leaves that card armed. Then the board hears the tap, which
# is all it does in v1 -- no shipped card listens for it.
func _on_card_tapped(data: CardData) -> void:
	if play_area.selected_cards:
		play_area.ungrab_cards()
		await _arm_the_entrance()
	await game.run_all_mods(&"on_card_tapped", data)

# A landed placement finishes the interaction: the hand is empty, the container goes back to the
# HUD, and the Entrance arms its next card.
func _place_held_onto(data: CardData) -> bool:
	if not await game.try_place(play_area.selected_cards, data): return false
	play_area.ungrab_cards()
	hud_container.show_hud()
	await _arm_the_entrance()
	return true

# THE ONE PICKUP ROUTE: a click's last resort and a drag's first act. A card no rule grabs leaves
# the hand exactly as it was, and drops the click's promise that the grab it asked for would
# follow the cursor -- otherwise the next auto-armed card is born following.
func _pick_up(data: CardData) -> void:
	var grabbed := await game.try_grab(data)
	if grabbed: play_area.grab_cards(grabbed)
	else: play_area.stop_following()


# THE DEBUG BAR (owner tool, debug builds only): Record toggles an EventLog capture and writes it
# on stop; Undo/Redo step the uncapped debug history so a bug's setup is always reachable and the
# action repeatable while recording. EventLog stays off by default; Record is the only way it turns on.

var _debug_bar : HBoxContainer = null
var _record_button : Button = null

func _build_debug_bar() -> void:
	if not OS.is_debug_build(): return
	_debug_bar = HBoxContainer.new()
	_debug_bar.name = "DebugBar"
	## Top-right, away from the board and the HUD. IGNORE on the container so only the buttons themselves take clicks, or a full-width bar would eat drags across the top.
	_debug_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_record_button = _add_debug_button(TRANSLATION.find('DEBUG_RECORD'), _on_debug_record)
	_add_debug_button(TRANSLATION.find('DEBUG_UNDO'), _on_debug_undo)
	_add_debug_button(TRANSLATION.find('DEBUG_REDO'), _on_debug_redo)
	_add_debug_button(TRANSLATION.find('DEBUG_CUE'), _on_debug_cue)
	add_child(_debug_bar)
	## TOP-right, growing left, parented to the VIEW like the prop debug box, so the two debug surfaces live in one place and never collide.
	_debug_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_debug_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT,
			Control.PRESET_MODE_MINSIZE, 8)

func _add_debug_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	## Mouse-only: never steal focus from the board's keyboard/controller navigation.
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	_debug_bar.add_child(b)
	return b

## Toggle the capture. Stopping WRITES it and prints the folder, so the owner has a path to send.
func _on_debug_record() -> void:
	if EventLog.enabled:
		EventLog.end()
		var dir := EventLog.save("playtest_%d" % Time.get_unix_time_from_system())
		_record_button.text = TRANSLATION.find('DEBUG_RECORD')
		print("=== EventLog written ===\n%s\n%s" % [dir, EventLog.summary()])
	else:
		## Every channel: a playtest bug can be anywhere.
		EventLog.begin()
		_record_button.text = TRANSLATION.find('DEBUG_RECORD_STOP')

## Stamps `SpotlightProbe` onto an uncovered, skill-free board card and re-runs the sweep, since the cue is otherwise unreachable without a skill implementing `on_spotlight` on the board.
func _on_debug_cue() -> void:
	if not game or not game.state: return
	## Stamp, then ask the card whether it is ACTUALLY spotlit, and unstamp if not: a covered card answers no, so the choice has to come from asking rather than guessing.
	var chosen : CardData = null
	for data : CardData in play_area.data_card.keys():
		if data.skill != null: continue
		data.with_skill(SpotlightProbe.new())
		if data.skill.is_spotlit():
			chosen = data
			break
		data.with_skill(null)
	if chosen == null:
		print("[debug cue] no UNCOVERED, skill-free board card to stamp — uncover one and retry")
		return
	print("[debug cue] probe -> %s; watch for the circle, the beam and the shallower casual dim"
			% chosen.log_str())
	## The REAL sweep, not a hand-built emit, so what you see is what a real activation looks like.
	await game.skill_spotlight_check()

func _on_debug_undo() -> void:
	if not game.debug_undo():
		print("debug_undo: nothing left to rewind to")

func _on_debug_redo() -> void:
	if not game.debug_redo():
		print("debug_redo: nothing to replay")
