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

# `game` is handed this view BEFORE it enters the tree, so its own `_ready()` runs fully bound, and
# its default state bypasses `state_bound`, so it is bound by hand. The board's reveal listens to the
# lights' own section signal, so the two can never disagree which section is up.
func _ready() -> void:
	_bind_hud_container()
	game = Game.new()
	game.view = self
	game.processing_changed.connect(_on_processing_changed)
	game.submit_label_changed.connect(_on_submit_label_changed)
	game.show_resolved.connect(_on_show_resolved)
	game.show_unresolved.connect(_on_show_unresolved)
	game.combo_changed.connect(_on_combo_changed)
	game.game_ended.connect(func() -> void: game_ended.emit())
	game.run_lost.connect(func() -> void: run_lost.emit())
	spotlight_director = SpotlightDirector.new()
	spotlight_director.name = "SpotlightDirector"
	add_child(spotlight_director)
	spotlight_director.bind(light_layer, play_area, game)
	game.spotlight_section_changed.connect(play_area.set_reveal_cards)
	_build_debug_bar()

	game.state_bound.connect(_on_state_bound)
	_bind_state(null, game.state)

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
	hud_container.connect_for_screen(self, hud_container.description_dismissed,
			_on_description_dismissed)
	hud_container.connect_for_screen(self, hud_container.exit_accepted,
			play_area.return_focus_to_board)

# The board wears the locked card's marking, so the view relays the lock ENDING the same way it
# relays the click that starts it. The container owns the lock itself; nothing else may clear it.
func _on_description_dismissed() -> void:
	play_area.locked_data = null

# The board publishes the ASK and the container owns whether there is anything to dismiss; the view
# is what sees both. The dismissal never spends the event -- the board consumes its own second
# button, and Escape is left for the wall's own Back so one press both cancels and steps out.
func _on_description_dismiss_requested() -> void:
	if not hud_container.showing_description(): return
	hud_container.dismiss_description()

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
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)

# ==============================================================================
# STATE BINDING (disconnect old, connect new on every state swap)
# ==============================================================================

# A swapped-in state is a new board, and a swap bumps no revision of its own.
func _on_state_bound(new_state: GameData) -> void:
	_bind_state(_bound_state, new_state)
	_on_board_changed()

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

# Owner ruling: the combo label hides at x1.0 rather than reading a no-op multiplier.
func _refresh_hud() -> void:
	if not is_node_ready() or not game: return
	var state := game.state
	goal_label.text = str(state.goal)
	total_label.text = str(state.live_total())
	var combo := state.combo_mult()
	combo_label.text = TRANSLATION.find('GAME_COMBO') % combo
	combo_label.visible = combo > 1.0
	_mark_goal_met(state.has_met_goal())

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

var _combo_tween : Tween = null

# A new combo class registered this act: the label pulses in the same shape as `BigNumberLabel.anim_pop`.
func _on_combo_changed(_count: int) -> void:
	_refresh_hud()
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
	play_area.picture_to_window_scale = WallPicture.focused_scale(design, window,
			PlayArea.settings().wall_overfill_margin)
	var region := WallPicture.visible_rect_beside(design, window, rect,
			HudContainer.container_is_top(window, PlayArea.settings()))
	play_area.board_inset_left = region.position.x
	play_area.board_inset_top = region.position.y
	play_area.board_visible_crop = design - region.end
	hud_container.resize_preview(play_area.board_card_window_px())

# Where a card leaving the board aims at `pile`: the pile is drawn in the window, the card in this
# picture. `Tests/Engine/test_leak_canary.gd` discards through a view with no `Main`, hence no picture.
func pile_center(pile: Control) -> Vector2:
	var window := hud_container.get_viewport().get_visible_rect().size
	var centre := pile.get_global_rect().get_center()
	if not wall_picture: return centre
	var picture_window := wall_picture.local_rect_beside(window, Rect2(), false)
	return picture_window.position + centre / window * picture_window.size

## Wires `Main`'s ONE wall camera and a rect-centre-x getter. Called once, right after `Main` instantiates this view.
func bind_wall_camera(camera: Camera2D, rect_centre_x: Callable) -> void:
	_wall_camera = camera
	_wall_rect_centre_x = rect_centre_x

func _relay_info_requested(entry: InfoEntry) -> void:
	entry.relay_to(info_requested)

## Every stock as ONE pile in a fixed suit-then-rank order, so neither which slot holds a card nor how soon it will be drawn leaks out of the Deck button.
static func sorted_stock_union(state: GameData) -> Array[CardData]:
	var cards := state.all_stock_cards()
	cards.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.suit.get_suit_index() != b.suit.get_suit_index():
			return a.suit.get_suit_index() < b.suit.get_suit_index()
		return a.rank.value < b.rank.value)
	return cards

# The deck, discard and rules viewers are publishers exactly like the board: they hand their
# highlights to this view, which relays them the same way, and closing one hands the sidebar back
# to whatever was locked behind it.
func _open_deck_viewer(cards: Array[CardData], opener: Button) -> void:
	hud_container.host_viewer(DeckViewer.show_deck(self, cards, opener), wall_picture, info_requested)

# Undo stays enabled while busy: it cancels a live act or rewinds a resolved one, and Game ignores
# the press where it cannot act.
func _on_processing_changed(busy: bool) -> void:
	submit_button.disabled = busy
	hud_container.set_processing(busy)
	if not busy: await _arm_the_entrance()

func _on_submit_label_changed(text: String) -> void:
	submit_button.text = text

## The win/lose overlay covers ONLY the play area: the board is blocked while the rest of the HUD stays clickable -- Undo rewinds the outcome, the deck/discard/rules viewers open.
var _continue_button : Button = null

## The row those two buttons sit in, kept so the outcome's own controls are freed as one.
var _outcome_buttons : HBoxContainer = null

# REACHING THE GOAL ENDS THE SHOW, FULL STOP: the board stops taking input, so the arm is let go
# here too -- otherwise the held card keeps following the cursor over the outcome screen.
func _on_show_resolved(won: bool, score: int, _goal: int) -> void:
	var screen : Label = win_screen if won else lose_screen
	screen.text = TRANSLATION.find('GAME_WIN_FAME') % score if won \
			else TRANSLATION.find('GAME_LOSE')
	screen.show()
	play_area.ungrab_cards()
	play_area.disable_board_focus()
	_outcome_buttons = HBoxContainer.new()
	screen.add_child(_outcome_buttons)
	_continue_button = Button.new()
	_continue_button.text = TRANSLATION.find('GAME_CONTINUE')
	_continue_button.add_theme_font_size_override(&"font_size", CONTINUE_FONT_SIZE)
	_outcome_buttons.add_child(_continue_button)
	_continue_button.pressed.connect(game.exit_show)
	# UNDO IS ON THE OUTCOME SCREEN TOO, and the HUD's own keeps its place for the mouse: focus
	# navigation never leaves the picture's SubViewport, so without this one a pad or keyboard
	# player can see the rewind but never reach it.
	var outcome_undo := Button.new()
	outcome_undo.text = TRANSLATION.find('GAME_UNDO')
	outcome_undo.add_theme_font_size_override(&"font_size", CONTINUE_FONT_SIZE)
	_outcome_buttons.add_child(outcome_undo)
	outcome_undo.pressed.connect(_on_undo_pressed)
	# These two are the whole walk this screen offers, so the pair is linked by hand rather than
	# left to the automatic neighbour search.
	_continue_button.focus_neighbor_right = _continue_button.get_path_to(outcome_undo)
	outcome_undo.focus_neighbor_left = outcome_undo.get_path_to(_continue_button)
	# ⚠ CENTRED ON ITS OWN MINIMUM SIZE, with both buttons already in it: anchoring alone keeps a
	# control where it was built, which parks it in the picture's top-left corner, under the
	# sidebar. Measured: Continue drawn across window x 0..134 while the sidebar ends at 288.
	_outcome_buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER,
			Control.PRESET_MODE_MINSIZE)
	_outcome_buttons.position.y += CONTINUE_OFFSET_Y
	_continue_button.grab_focus()

## Undo at the win/lose screen: drop the overlay, and hand the freed buttons' focus to the HUD's Undo.
func _on_show_unresolved() -> void:
	win_screen.hide()
	lose_screen.hide()
	play_area.enable_board_focus()
	if _outcome_buttons:
		_outcome_buttons.queue_free()
	_outcome_buttons = null
	_continue_button = null
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

# A placement arms once, AFTER its refill, whether a click or a resume's replay drove it: the
# cascade's own unlock can arm a card the refill then leaves out of place, so the hand is re-derived.
func arm_after_placement() -> void:
	play_area.ungrab_cards()
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

# A resume rebuilds EVERY board visual from the restored GameData: the revision-bump rebuild never
# touches the gutters. They reserve their space FIRST, so the cards lay out against the final height.
func load_board_visuals() -> void:
	play_area.update_score_controls()
	play_area.flush_rebuild()
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

# What is held is the arm, and the arm is view-only: it is dropped here and re-derived from whatever
# board the undo restores.
func _on_undo_pressed() -> void:
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

# A landed placement finishes the interaction: the container goes back to the HUD. The placement
# itself has already armed the Entrance's next card.
func _place_held_onto(data: CardData) -> bool:
	if not await game.try_place(play_area.selected_cards, data): return false
	hud_container.dismiss_description()
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

# Top-right and parented to the VIEW like the prop debug box, so the two debug surfaces never
# collide. The bar itself IGNOREs the mouse: a full-width bar would eat drags across the top.
func _build_debug_bar() -> void:
	if not OS.is_debug_build(): return
	_debug_bar = HBoxContainer.new()
	_debug_bar.name = "DebugBar"
	_debug_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_record_button = _add_debug_button(TRANSLATION.find('DEBUG_RECORD'), _on_debug_record)
	_add_debug_button(TRANSLATION.find('DEBUG_UNDO'), _on_debug_undo)
	_add_debug_button(TRANSLATION.find('DEBUG_REDO'), _on_debug_redo)
	_add_debug_button(TRANSLATION.find('DEBUG_CUE'), _on_debug_cue)
	add_child(_debug_bar)
	_debug_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_debug_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT,
			Control.PRESET_MODE_MINSIZE, 8)

func _add_debug_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	_debug_bar.add_child(b)
	return b

# The capture records every channel, since a playtest bug can be anywhere. Stopping WRITES it and
# prints the folder, so the owner has a path to send.
func _on_debug_record() -> void:
	if EventLog.enabled:
		EventLog.end()
		var dir := EventLog.save("playtest_%d" % Time.get_unix_time_from_system())
		_record_button.text = TRANSLATION.find('DEBUG_RECORD')
		print("=== EventLog written ===\n%s\n%s" % [dir, EventLog.summary()])
	else:
		EventLog.begin()
		_record_button.text = TRANSLATION.find('DEBUG_RECORD_STOP')

# The cue is unreachable without a skill implementing `on_spotlight`, so this stamps `SpotlightProbe`
# on the first skill-free card that answers it is ACTUALLY spotlit -- a covered one says no -- and
# runs the REAL sweep, so what shows is what a real activation looks like.
func _on_debug_cue() -> void:
	if not game or not game.state: return
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
	await game.skill_spotlight_check()

func _on_debug_undo() -> void:
	if not game.debug_undo():
		print("debug_undo: nothing left to rewind to")

func _on_debug_redo() -> void:
	if not game.debug_redo():
		print("debug_redo: nothing to replay")
