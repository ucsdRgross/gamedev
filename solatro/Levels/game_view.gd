extends Control
class_name GameView
## The detachable UI/input layer for a show. Owns every visual: PlayArea, HUD labels, buttons,
## win/lose screens. Holds a headless [Game] logic node (created as a child, injected with
## `game.view = self`) and is the single place that does ALL input, ALL HUD, ALL animation.
##
## Communication (the seam Plan 1 builds on):
##   Game -> view reactive : game.state.state_changed / board_changed, game.processing_changed /
##                           submit_label_changed / show_resolved  (signals, no await)
##   Game -> view paced    : game calls `if view: await view.<m>()` for animation/visual sync
##   View -> Game commands : game.submit() / next() / undo() / try_grab() / try_place()
## Remove this view and the Game still runs a full show headless (every paced call is `if view:`).

## Forwarded from the held Game so Main can bind the view directly (symmetric with the old
## Game-as-scene-root wiring). The view frees with its Game child, so Main frees just the view.
signal game_ended
signal run_lost

# Continue button sizing (win/lose screen) — named, no magic numbers in logic.
const CONTINUE_FONT_SIZE := 40
const CONTINUE_OFFSET_Y := 220.0

var game : Game = null

@onready var play_area: PlayArea = %PlayArea
@onready var submit_button: Button = %Submit
@onready var undo_button: Button = %Undo
@onready var next_button: Button = %Next
@onready var deck_ui: Control = %Deck
@onready var discard_ui: Control = %Discard
@onready var rules_ui: Control = %Rules
@onready var win_screen: Label = %WinScreen
@onready var lose_screen: Label = %LoseScreen
@onready var goal_label: Label = %Goal/Label
@onready var total_label: Label = %Total/Label
@onready var mult_label: Label = %MultScore
@onready var col_label: Label = %MultScore/Col
@onready var row_label: Label = %MultScore/Row
@onready var combo_label: Label = %MultScore/Combo

func _ready() -> void:
	# Create the logic node and inject ourselves BEFORE adding it to the tree, so its _enter_tree
	# (CardEnvironment.CURRENT) and _ready (resume/fresh deal) run with the view fully bound.
	game = Game.new()
	game.view = self
	game.processing_changed.connect(_on_processing_changed)
	game.submit_label_changed.connect(_on_submit_label_changed)
	game.show_resolved.connect(_on_show_resolved)
	game.show_unresolved.connect(_on_show_unresolved)
	game.combo_changed.connect(_on_combo_changed)
	game.game_ended.connect(func() -> void: game_ended.emit())
	game.run_lost.connect(func() -> void: run_lost.emit())
	# Rebind HUD/board signals whenever Game swaps its state (undo/resume replace it) — N9.
	game.state_bound.connect(_on_state_bound)
	_bind_state(null, game.state)  # the initial default state bypasses the setter -> bind by hand

	# Input wiring (all lives in the view now).
	submit_button.pressed.connect(func() -> void: await game.submit())
	next_button.pressed.connect(func() -> void: await game.next())
	undo_button.pressed.connect(_on_undo_pressed)
	play_area.data_selected.connect(_on_data_selected)
	(deck_ui.get_node(^"Button") as Button).pressed.connect(func() -> void: DeckViewer.show_deck(self, game.state.draw_deck))
	(discard_ui.get_node(^"Button") as Button).pressed.connect(func() -> void: DeckViewer.show_deck(self, game.state.discard_deck))
	(rules_ui.get_node(^"Button") as Button).pressed.connect(func() -> void: DeckViewer.show_deck(self, game.state.rules_deck))

	add_child(game)
	_add_prop_debug_controls()
	# _refresh_hud early-returns while _ready runs (node not ready yet); refresh once we are, so
	# a fresh goal / resumed score shows immediately.
	_refresh_hud.call_deferred()

## Debug prop stepping (owner tool, 2026-07-13): a toggle that holds every finished prop tick
## open (PropLayer.manual_step — the whole run_props loop pauses at its SYNC await), and a
## step button that releases exactly one tick, so a prop run can be watched tick by tick.
## Mouse-only (FOCUS_NONE) so keyboard/controller navigation never lands on them.
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
	# Bottom-right corner, growing up/left so the content never leaves the screen.
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)

# ==============================================================================
# STATE BINDING (N9: disconnect old, connect new on every state swap)
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
	total_label.text = str(state.total_score)
	mult_label.text = str(state.mult_score)
	col_label.text = str(state.col_total)
	row_label.text = str(state.row_total)
	var combo := state.combo_mult()
	combo_label.text = TRANSLATION.find('GAME_COMBO') % combo
	combo_label.visible = combo > 1.0   # owner ruling 2026-07-17: hidden at x1.0

## A NEW combo class registered this act (§15a): refresh + pulse the combo label.
## combo_classes.append() doesn't emit state_changed — this signal is the live path;
## sync_scores()/state_changed re-run _refresh_hud after apply_act_score clears the set.
var _combo_tween : Tween = null

func _on_combo_changed(_count: int) -> void:
	_refresh_hud()
	# pulse: same shape as BigNumberLabel.anim_pop (UI/big_number_label.gd:21-26)
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

func _on_processing_changed(busy: bool) -> void:
	submit_button.disabled = busy
	next_button.disabled = busy
	# Undo stays ENABLED while busy: pressing it mid-act cancels the act (Game.undo requests
	# the cancel; the act restores the pre-act board), and at the win/lose screen it rewinds
	# the final Submit. Game ignores the press in the states where undo can't act.

func _on_submit_label_changed(text: String) -> void:
	submit_button.text = text

## The win/lose overlay covers ONLY the play area (it lives inside PlayContainer): the board
## underneath is blocked (mouse by the overlay's STOP filter, keyboard/controller by dropping
## the card controls' focus), while the rest of the HUD stays clickable — Undo rewinds the
## outcome, the deck/discard/rules viewers still open; Submit/Next stay disabled (processing
## holds true, no more card logic).
var _continue_button : Button = null

func _on_show_resolved(won: bool, score: int, _goal: int) -> void:
	var screen : Label = win_screen if won else lose_screen
	screen.text = TRANSLATION.find('GAME_WIN_FAME') % score if won \
			else TRANSLATION.find('GAME_LOSE')
	screen.show()
	play_area.hide_focus_info()
	play_area.disable_board_focus()
	_continue_button = Button.new()
	_continue_button.text = TRANSLATION.find('GAME_CONTINUE')
	_continue_button.add_theme_font_size_override(&"font_size", CONTINUE_FONT_SIZE)
	screen.add_child(_continue_button)
	_continue_button.set_anchors_preset(Control.PRESET_CENTER)
	_continue_button.position.y += CONTINUE_OFFSET_Y  # sit below the big win/lose text
	_continue_button.pressed.connect(game.exit_show)
	_continue_button.grab_focus()

## Undo at the win/lose screen: drop the overlay. The Game follows up with the normal undo
## rebuild (fresh board controls restore card focus), so nothing else needs restoring here.
func _on_show_unresolved() -> void:
	win_screen.hide()
	lose_screen.hide()
	play_area.enable_board_focus()  # the undo's rebuild follows and re-derives header focus
	if _continue_button and is_instance_valid(_continue_button):
		_continue_button.queue_free()
	_continue_button = null
	undo_button.grab_focus()  # keyboard/controller: focus was on the freed Continue

# ==============================================================================
# GAME -> VIEW PACED (injected view; Game calls `if view: await view.<m>()`)
# ==============================================================================
## Force a synchronous board rebuild (undo: the state reverted, no revision bump to ride).
func rebuild() -> void:
	play_area.setup_gui()

## Repopulate the row/col score gutters from state.scores_* (after apply_act_score clears them).
func sync_scores() -> void:
	play_area.update_score_controls()

## Rebuild EVERY board visual from the restored GameData (resume). The board is only "ready"
## once the cards AND the row/col gutters reflect the loaded state — the normal rebuild path
## (revision bump -> set_card_zones) does NOT touch the gutters, so a resumed show would
## otherwise show empty gutters despite the scores being restored in state.
func load_board_visuals() -> void:
	# Create the row/col score gutters (incl. the row buffer control) FIRST, so the containers
	# reserve their space before the cards lay out. Otherwise the cards build into an
	# unbuffered layout, and adding the gutters afterwards shifts the board down AFTER the
	# cards are already positioned — so a resumed mid-submit show plays its scoring jump from
	# the old (higher, pre-buffer) spot, misaligned with the board. A fresh show avoids this
	# because setup_gui() builds the buffer up-front, before any card exists.
	play_area.update_score_controls()  # populate the row/col score gutters from state.scores_*
	play_area.flush_rebuild()  # build the card controls + CardVisuals now (they add_child deferred)
	# CardVisuals enter the tree via call_deferred (the deferral lets the container lay out first,
	# which is what keeps board rebuilds from flying in from the origin), so they're ready one
	# frame later. Wait on PlayArea's board_visuals_ready signal instead of polling — check first
	# in case the build already finished, else the signal fires when the deferred adds land.
	if not play_area.visuals_ready():
		await play_area.board_visuals_ready
	print("[resume] cards ready: %d card visual(s), visuals_ready=%s"
			% [play_area.data_card.size(), play_area.visuals_ready()])
	# Refresh the gutter values now the board is fully laid out (idempotent; the space was
	# already reserved above so this no longer shifts the board).
	play_area.update_score_controls()
	print("[resume] score gutters loaded from state: rows upper=%d lower=%d, cols=%d"
			% [game.state.scores_row_upper.size(), game.state.scores_row_lower.size(),
					game.state.scores_col.size()])

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

## Start one prop-simulation tick's visuals and return a signal the Game awaits for completion
## (data is one step ahead of the view — SUIT_PROPS_PLAN §1.3). Delegates to the PropLayer,
## which animates every live prop and emits its `tick_done` once they've all reached target.
func begin_prop_tick(live: Array, spawned: Array, movers: Array, relocated: Array) -> Signal:
	return play_area.prop_layer.begin_prop_tick(live, spawned, movers, relocated)

## Undo cancelled a resolving act: the prop simulation stopped mid-run, so free every prop
## visual immediately (no later tick will prune them).
func abort_props() -> void:
	play_area.prop_layer.abort_all()

## True while the started visual tick is still animating. The Game's SYNC step awaits
## `tick_done` only while this holds — if the events phase outlasted the animation, the
## emission already fired and awaiting it now would hang (persistent-signal race, see
## PropLayer.tick_pending).
func prop_tick_pending() -> bool:
	return play_area.prop_layer.tick_pending()

# ==============================================================================
# VIEW -> GAME INPUT (selection UI here; data queries/moves are Game commands)
# ==============================================================================
func _on_undo_pressed() -> void:
	# The held-cards guard is the view's job (selection state lives in PlayArea).
	if play_area.selected_cards: return
	game.undo()

func _on_data_selected(data: CardData) -> void:
	if game.processing: return
	# if already holding cards
	if play_area.selected_cards:
		var held0 := play_area.selected_cards[0]
		# do nothing if position unchanged
		if (data == held0
				or game.find_data_vec3(data) == game.find_data_vec3(held0) - Vector3i(0, 0, 1)):
			play_area.ungrab_cards()
		# dont place within own stack
		elif data not in play_area.selected_cards:
			# attempt placing cards, do nothing if no result
			var placed := await game.try_place(play_area.selected_cards, data)
			if placed:
				play_area.ungrab_cards()
	else:
		var grabbed := await game.try_grab(data)
		play_area.grab_cards(grabbed)
