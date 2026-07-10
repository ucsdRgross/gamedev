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

func _ready() -> void:
	# Create the logic node and inject ourselves BEFORE adding it to the tree, so its _enter_tree
	# (CardEnvironment.CURRENT) and _ready (resume/fresh deal) run with the view fully bound.
	game = Game.new()
	game.view = self
	game.processing_changed.connect(_on_processing_changed)
	game.submit_label_changed.connect(_on_submit_label_changed)
	game.show_resolved.connect(_on_show_resolved)
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
	# _refresh_hud early-returns while _ready runs (node not ready yet); refresh once we are, so
	# a fresh goal / resumed score shows immediately.
	_refresh_hud.call_deferred()

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

# Board mutated (revision bump) -> coalesced rebuild at end of frame.
func _on_board_changed() -> void:
	play_area.queue_rebuild()

func _on_processing_changed(busy: bool) -> void:
	submit_button.disabled = busy
	next_button.disabled = busy
	undo_button.disabled = busy

func _on_submit_label_changed(text: String) -> void:
	submit_button.text = text

func _on_show_resolved(won: bool, score: int, _goal: int) -> void:
	var screen : Label = win_screen if won else lose_screen
	if won:
		screen.text = "Fame +%d" % score
	screen.show()
	var cont := Button.new()
	cont.text = "Continue"
	cont.add_theme_font_size_override(&"font_size", CONTINUE_FONT_SIZE)
	screen.add_child(cont)
	cont.set_anchors_preset(Control.PRESET_CENTER)
	cont.position.y += CONTINUE_OFFSET_Y  # sit below the big win/lose text
	cont.pressed.connect(game.exit_show)
	cont.grab_focus()

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
	play_area.flush_rebuild()  # build the card controls + CardVisuals now (they add_child deferred)
	# CardVisuals enter the tree via call_deferred (the deferral lets the container lay out first,
	# which is what keeps board rebuilds from flying in from the origin), so they're ready one
	# frame later. Wait on PlayArea's board_visuals_ready signal instead of polling — check first
	# in case the build already finished, else the signal fires when the deferred adds land.
	if not play_area.visuals_ready():
		await play_area.board_visuals_ready
	print("[resume] cards ready: %d card visual(s), visuals_ready=%s"
			% [play_area.data_card.size(), play_area.visuals_ready()])
	play_area.update_score_controls()  # populate the row/col score gutters from state.scores_*
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
