extends Control
class_name GameView
#Communication: Game -> view reactive is state_changed / board_changed / processing_changed /
#submit_label_changed / show_resolved; Game -> view paced is `if view: await view.<m>()`; view ->
#Game is a command - end_show, next, undo, try_grab, try_place.

#Remove this view and the Game still runs a full show headless, every paced call being `if view:`.

## The detachable UI and input layer for a show: it owns every visual and holds a headless Game.

#The view frees with its Game child, so Main frees just the view.

## Forwarded from the held Game so Main can bind the view directly.
signal game_ended
signal run_lost
#The board has no business knowing whether Info mode wants a card shown.

## Relayed from PlayArea so Main can put a clicked card on the wall's info card.
signal info_requested(entry: InfoEntry)

# Continue button sizing (win/lose screen) — named, no magic numbers in logic.
const CONTINUE_FONT_SIZE := 40
const CONTINUE_OFFSET_Y := 220.0

var game : Game = null

@onready var scene_root: Control = $SceneRoot
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
## Opens and closes the marks layer, for the mouse, the keyboard and the controller alike.
var plan_layer_button : Button = null
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
#⚠ A PICTURE-HOSTED SHOW HOLDS ITS SCENE UNTIL THE PICTURE GOES LIVE, so the deal and the board's
#grow start where the player first sees them, on the zoom-in (owner ruling). A standalone view has
#no picture and runs at once.
	if wall_picture:
		scene_root.process_mode = Node.PROCESS_MODE_DISABLED
		wall_picture.went_live.connect(_start_on_screen)
	game = Game.new()
	game.view = self
	game.processing_changed.connect(_on_processing_changed)
	game.submit_label_changed.connect(_on_submit_label_changed)
	game.show_resolved.connect(_on_show_resolved)
	game.show_unresolved.connect(_on_show_unresolved)
	game.combo_changed.connect(_on_combo_changed)
	game.game_ended.connect(func() -> void: game_ended.emit())
	game.run_lost.connect(func() -> void: run_lost.emit())
#THE SPOTLIGHT WIRE. Bound after `game` is built - it IS the CardEnvironment the cue comes from -
#and before the deal, so the first placement of the run is already lit.
	spotlight_director = SpotlightDirector.new()
	spotlight_director.name = "SpotlightDirector"
	add_child(spotlight_director)
	spotlight_director.bind(light_layer, play_area, game)
#THE REVEAL IS THE BOARD'S HALF OF THE SAME BEAT, deliberately a second listener on the same
#signals rather than something the director calls: the director owns LIGHTS and the play area owns
#LAYOUT, and both derive from one signal, so they cannot disagree about which section is up.
	game.spotlight_section_changed.connect(play_area.set_reveal_cards)
#⚠ The rows close on the ACT's release, an empty section, not on spotlight_reveal_ended: that
#fires per section to fade the show, and closing there would slam every row shut between sections
#and re-open it. An empty `cards` array already routes through set_reveal_cards and closes all.
	_build_debug_bar()

#HUD and board signals are rebound whenever Game swaps its state, which undo and resume do. The
#initial default state bypasses the setter, so it is bound by hand.
	game.state_bound.connect(_on_state_bound)
	_bind_state(null, game.state)

#⚠ THE SUBMIT BUTTON ENDS THE SHOW and carries the End label. A show is one continuous
#performance with no act to submit and nothing that resolves one on its own, so end_show() is the
#only thing that can finish it; bound to the retired submit act it does nothing a player can see.
	hud_container.connect_for_screen(self, submit_button.pressed, _on_submit_pressed)
	hud_container.connect_for_screen(self, undo_button.pressed, _on_undo_pressed)
	plan_layer_button.text = TRANSLATION.find('PLAN_LAYER_TOGGLE')
	plan_layer_button.tooltip_text = TRANSLATION.find('PLAN_LAYER_TOGGLE_HINT')
	hud_container.connect_for_screen(self, plan_layer_button.pressed, _on_plan_layer_pressed)
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
	play_area.hand_released.connect(_finish_with_the_card)
	play_area.card_tapped.connect(_on_card_tapped)
	play_area.info_requested.connect(_relay_info_requested)
	play_area.highlight_cleared.connect(hud_container.highlight_gone)
	play_area.description_dismiss_requested.connect(_on_description_dismiss_requested)
	play_area.sidebar_requested.connect(hud_container.focus_sidebar)

	add_child(game)
	_add_prop_debug_controls()
#_refresh_hud early-returns while _ready runs, so it is refreshed deferred and a fresh goal or a
#resumed score shows immediately.
	_refresh_hud.call_deferred()
	_publish_board_inset()

func _start_on_screen() -> void:
	scene_root.process_mode = Node.PROCESS_MODE_INHERIT
	play_area.ease_the_opening_in()

# ⚠ THE SHOW'S CONTAINER STATE DIES WITH THE SHOW: `Main` reuses one screen id for every show, so
# the view leaving the tree hands back its memory, its lock and its cascade flag.
func _bind_hud_container() -> void:
	hud_container = HudContainer.ensure(hud_container, self)
	tree_exiting.connect(hud_container.release_screen.bind(HudContainer.GAME_SCREEN))
	submit_button = hud_container.submit_button
	undo_button = hud_container.undo_button
	plan_layer_button = hud_container.plan_layer_button
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
#Bottom-right corner, growing up and left so the content never leaves the screen.
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)

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

func _refresh_hud() -> void:
	if not is_node_ready() or not game: return
	var state := game.state
	goal_label.text = str(state.goal)
#The show's score is DERIVED, every grid's total times the combo, and always current: there is no
#act payout and no banking moment, so there is no stored total to show.
	total_label.text = str(state.live_total())
	var combo := state.combo_mult()
	combo_label.text = TRANSLATION.find('GAME_COMBO') % combo
#Hidden at x1.0 (owner ruling).
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

#A NEW combo class registered this act: refresh and pulse the combo label. combo_classes.append()
#does not emit state_changed, so this signal is the live path; sync_scores() and state_changed
#re-run _refresh_hud after apply_act_score clears the set.
var _combo_tween : Tween = null

# A new combo class registered this act: the label pulses in the same shape as `BigNumberLabel.anim_pop`.
func _on_combo_changed(_count: int) -> void:
	_refresh_hud()
#The pulse has the same shape as BigNumberLabel.anim_pop.
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

# ⚠ THE RESERVE IS THE SIDEBAR'S RESTING RECT, NEVER THE SLIDING ONE: the board's size and zoom are
# fitted against where the sidebar comes to REST, and only its position follows the slide, through
# `board_slide_offset`. A shift, not a re-scale.
func _publish_board_inset() -> void:
	var window := hud_container.get_viewport().get_visible_rect().size
	var design := Vector2(PlayArea.game_picture_design_size(PlayArea.settings()))
	var top := HudContainer.container_is_top(window, PlayArea.settings())
	play_area.picture_to_window_scale = WallPicture.focused_scale(design, window,
			PlayArea.settings().wall_overfill_margin)
	var region := WallPicture.visible_rect_beside(design, window,
			hud_container.container_rect(), top)
	var slid := WallPicture.visible_rect_beside(design, window,
			hud_container.published_rect(), top)
	play_area.board_inset_left = region.position.x
	play_area.board_inset_top = region.position.y
	play_area.board_visible_crop = design - region.end
	play_area.board_slide_offset = slid.position - region.position
	hud_container.resize_preview(CardVisual.preview_window_px(play_area.picture_to_window_scale))

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
	var viewer := DeckViewer.show_deck(self, cards, opener)
	if viewer: hud_container.host_viewer(viewer, wall_picture, info_requested)

# Undo stays enabled while busy: it cancels a live act or rewinds a resolved one, and Game ignores
# the press where it cannot act.
func _on_processing_changed(busy: bool) -> void:
	submit_button.disabled = busy
	hud_container.set_processing(busy)
	if not busy: _rest_the_board_focus()

func _on_submit_label_changed(text: String) -> void:
	submit_button.text = text

#The win/lose overlay covers ONLY the play area, living inside PlayContainer: the board underneath
#is blocked, by the overlay's STOP filter for the mouse and by dropping the card controls' focus for
#keyboard and controller.

#The rest of the HUD stays clickable - Undo rewinds the outcome and the viewers still open - while
#Submit and Next stay disabled, processing holding true with no more card logic.
var _continue_button : Button = null

## The row those two buttons sit in, kept so the outcome's own controls are freed as one.
var _outcome_buttons : HBoxContainer = null

# REACHING THE GOAL ENDS THE SHOW, FULL STOP: the hand is let go so the held card stops following
# the cursor. Undo sits BESIDE Continue because focus navigation never leaves the picture's
# SubViewport. ⚠ The row is centred on its OWN MINIMUM SIZE: anchoring alone leaves it top-left.
func _on_show_resolved(won: bool, score: int, _goal: int) -> void:
	var screen : Label = win_screen if won else lose_screen
	screen.text = TRANSLATION.find('GAME_WIN_FAME') % score if won \
			else TRANSLATION.find('GAME_LOSE')
	screen.show()
	play_area.ungrab_cards()
	play_area.disable_board_focus()
	_outcome_buttons = HBoxContainer.new()
	screen.add_child(_outcome_buttons)
	_continue_button = _add_outcome_button(_outcome_buttons, &'GAME_CONTINUE', game.exit_show)
	_add_outcome_button(_outcome_buttons, &'GAME_UNDO', _on_outcome_undo_pressed)
	_outcome_buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER,
			Control.PRESET_MODE_MINSIZE)
	_outcome_buttons.position.y += CONTINUE_OFFSET_Y
	_continue_button.grab_focus()

func _add_outcome_button(row: HBoxContainer, key: StringName, handler: Callable) -> Button:
	var button := Button.new()
	button.text = TRANSLATION.find(key)
	button.add_theme_font_size_override(&"font_size", CONTINUE_FONT_SIZE)
	button.pressed.connect(handler)
	row.add_child(button)
	return button

# The outcome's Undo is pressed INSIDE the picture's SubViewport, and freeing its row leaves that
# viewport with no focus owner: the HUD's Undo the rewind hands the focus to lives in the root,
# where a pad's navigation cannot reach it, so the pad player is rested back on the board.
func _on_outcome_undo_pressed() -> void:
	_on_undo_pressed()
	play_area.rest_focus_on_board()

## Undo at the win/lose screen: drop the overlay, and hand the freed buttons' focus to the HUD's Undo.
func _on_show_unresolved() -> void:
	win_screen.hide()
	lose_screen.hide()
	play_area.enable_board_focus()
	assert(_outcome_buttons)
	_outcome_buttons.queue_free()
	_outcome_buttons = null
	_continue_button = null
	undo_button.grab_focus()

#A rebuild mid-grab strands held-card visual state, and the player's selection cannot survive a
#round change anyway.

## Drop any live grab before the Game mutates the board underneath it.
func release_grab() -> void:
	play_area.ungrab_cards()

## Wait for a just-placed card to finish travelling to its cell.
func await_card_settled(card: CardData) -> void:
	await play_area.await_card_settled(card)

## Force a synchronous board rebuild (undo: the state reverted, no revision bump to ride).
func rebuild() -> void:
	play_area.setup_gui()
	_rest_the_board_focus()

# A key or pad player needs a control to move from, so a board that settles with NOTHING in the
# picture holding the focus takes it back -- the opening deal, and any rebuild that freed the
# control that had it. It waits for the visuals, and never takes the focus off the player.
func _rest_the_board_focus() -> void:
	if _the_focus_is_elsewhere(): return
	if not play_area.visuals_ready(): await play_area.board_visuals_ready
	if _the_focus_is_elsewhere(): return
	play_area.rest_focus_on_board()

# ⚠ AN OPEN VIEWER IS THE FOCUS, and the button that opened it holds the key focus in the sidebar's
# viewport, which this one's owner never reports: a rest under it would walk the board unseen and
# its lost focus would clear the first card the viewer describes.
func _the_focus_is_elsewhere() -> bool:
	return get_viewport().gui_get_focus_owner() != null \
			or get_children().any(func(child: Node) -> bool: return child is DeckViewer)

## Deal the opening plan onto the board cell by cell (show start only).
func reveal_plan() -> void:
	await play_area.reveal_plan()

## Repopulate the row/col score gutters from state.scores_* (after apply_act_score clears them).
func sync_scores() -> void:
	play_area.update_score_controls()

#The board is only "ready" once the cards AND the row/col gutters reflect the loaded state: the
#normal rebuild path does not touch the gutters, so a resumed show would show empty gutters despite
#the scores being restored in state.

## Rebuild EVERY board visual from the restored GameData, which is what a resume needs.
func load_board_visuals() -> void:
#The gutters are created FIRST, so the containers reserve their space before the cards lay out.
#Adding them afterwards shifts the board down after the cards are positioned, and a resumed
#mid-submit show would then play its scoring jump from the old, higher spot.
	play_area.update_score_controls()
	play_area.flush_rebuild()
#CardVisuals enter the tree via call_deferred, the deferral being what keeps board rebuilds from
#flying in from the origin, so they are ready one frame later. The check comes first in case the
#build already finished; otherwise board_visuals_ready fires when the deferred adds land.
	if not play_area.visuals_ready():
		await play_area.board_visuals_ready
	print("[resume] cards ready: %d card visual(s), visuals_ready=%s"
			% [play_area.data_card.size(), play_area.visuals_ready()])
#The gutter values are refreshed now the board is fully laid out. Idempotent, and the space was
#already reserved above, so this no longer shifts the board.
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

#The grid buckets are keyed dictionaries rather than the legacy zone arrays, so they cannot go
#through update_line_score - but a score the player cannot see arrive is the same defect either way.

## Pop the row, column, special or height label a grid line just banked into.
func pop_grid_line_score(section: ScoringSection) -> void:
	play_area.pop_grid_score_label(section)

#The data is one step ahead of the view, so this returns a signal the Game awaits for completion.
#The PropLayer animates every live prop and emits tick_done once they have all reached target.

## Start one prop-simulation tick's visuals.
func begin_prop_tick(live: Array, spawned: Array, movers: Array, relocated: Array) -> Signal:
	return play_area.prop_layer.begin_prop_tick(live, spawned, movers, relocated)

#The prop simulation stopped mid-run, so no later tick will prune the visuals.

## Undo cancelled a resolving act: free every prop visual immediately.
func abort_props() -> void:
	play_area.prop_layer.abort_all()

#The Game's SYNC step awaits tick_done only while this holds: if the events phase outlasted the
#animation the emission already fired, and awaiting it now would hang.

## True while the started visual tick is still animating.
func prop_tick_pending() -> bool:
	return play_area.prop_layer.tick_pending()


#THE LAYER VIEW IS A VIEWER: while the board draws its marks it is looked at and never played,
#so every command that would mutate it is refused rather than queued.
func _board_is_playable() -> bool:
	return not play_area.plan_layer_open

#THE ONE THING THAT FINISHES A SHOW, and not something a viewer does from inside the layer it
#opened to look at the board.
func _on_submit_pressed() -> void:
	if not _board_is_playable(): return
	game.end_show()

#Held cards are RELEASED rather than the undo refused, because the selection state lives in
#PlayArea and is the view's job; a board being looked at is not rewound at all.
func _on_undo_pressed() -> void:
	if not _board_is_playable(): return
	play_area.ungrab_cards()
	game.undo()

#ONE CONTROL EVERY INPUT MODE REACHES THE SAME WAY: a focusable button answers a mouse click, a
#keyboard accept and a controller accept without any of the three being wired on its own. Refused
#while the board resolves, the way a selection is: the rebuild that cascade ends in closes it.
func _on_plan_layer_pressed() -> void:
	if game.processing: return
	play_area.plan_layer_open = not play_area.plan_layer_open

func _on_data_selected(data: CardData) -> void:
	if game.processing:
		play_area.stop_following()
		return
	hud_container.lock_to(PlayArea.card_info(data,
			CardVisual.preview_window_px(play_area.picture_to_window_scale)))
	play_area.locked_data = data
	if play_area.selected_cards:
		if data in play_area.selected_cards: return
		if await _place_held_onto(data): return
	await _pick_up(data)

# THE DRAG'S RELEASE IS ANOTHER WAY TO REACH THE SAME PLACEMENT, and nothing downstream can tell
# which route was taken. A release the board refuses lets the card go instead: the player ACTED with
# it either way, so either way the card is finished with.
func _on_card_dropped(data: CardData) -> void:
	if game.processing or not await _place_held_onto(data):
		play_area.ungrab_cards()
		_finish_with_the_card()

# A TAP UNDOES THE GRAB THE PRESS BEFORE IT MADE: the card goes back to its slot. Then the board
# hears the tap, which is all it does in v1 -- no shipped card listens for it.
func _on_card_tapped(data: CardData) -> void:
	play_area.ungrab_cards()
	await game.run_all_mods(&"on_card_tapped", data)

# A landed placement finishes the interaction.
func _place_held_onto(data: CardData) -> bool:
	if not await game.try_place(play_area.selected_cards, data): return false
	_finish_with_the_card()
	return true

# THE PLAYER ACTED WITH THE CARD, so they are done reading it: the description goes back to the HUD,
# which puts End, Undo and Marks back within reach, and the card gives up the focus that outlines it.
# A cancel is not an act -- it keeps both, and closes the description on its own second press.

# ⚠ The placement that reaches the goal ends the show before `try_place` returns, so this can run
# with no board left to rest on. `rest_focus_on_board` owns that answer for every caller.
func _finish_with_the_card() -> void:
	hud_container.dismiss_description()
	play_area.rest_focus_on_board()

# THE ONE PICKUP ROUTE: a click's last resort and a drag's first act. A card no rule grabs leaves
# the hand exactly as it was, and drops the drag's promise that the grab it asked for would follow
# the cursor -- otherwise the next card taken up is born following.
func _pick_up(data: CardData) -> void:
	var grabbed := await game.try_grab(data)
	if not grabbed:
		play_area.stop_following()
		return
	play_area.grab_cards(grabbed)
#AFTER the grab, never before: the grab measures the pointer against the cell the card came out of,
#and aiming the board first would move that cell out from under the cursor.
	play_area.focus_the_grid_in_view()


#THE DEBUG BAR - three buttons serving one workflow. Owner: *"If I see an issue during playtest, I
#can undo, press record, then repeat the action, and then send log for debugging."* Record captures
#an EventLog and writes it on stop, debug undo rewinds uncapped, debug redo steps forward again.

#⚠ DEBUG BUILDS ONLY. The bar is not built at all in an exported game, where Game's debug
#history does not exist either, so two of the three buttons would be dead controls.

#⚠ RECORD IS DELIBERATELY THE ONLY WAY THIS TURNS ON IN A REAL SESSION. EventLog is off by
#default and costs one static bool when off; a log that recorded every session would be a
#performance cost paid forever to capture mostly nothing.

var _debug_bar : HBoxContainer = null
var _record_button : Button = null

# Top-right and parented to the VIEW like the prop debug box, so the two debug surfaces never
# collide. The bar itself IGNOREs the mouse: a full-width bar would eat drags across the top.
func _build_debug_bar() -> void:
	if not OS.is_debug_build(): return
	_debug_bar = HBoxContainer.new()
	_debug_bar.name = "DebugBar"
#Top-right, away from the board and the HUD. MOUSE_FILTER_IGNORE on the CONTAINER so only the
#buttons themselves take clicks - a full-width bar would otherwise eat drags across the top.
	_debug_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_record_button = _add_debug_button(TRANSLATION.find('DEBUG_RECORD'), _on_debug_record)
	_add_debug_button(TRANSLATION.find('DEBUG_UNDO'), _on_debug_undo)
	_add_debug_button(TRANSLATION.find('DEBUG_REDO'), _on_debug_redo)
	_add_debug_button(TRANSLATION.find('DEBUG_CUE'), _on_debug_cue)
	add_child(_debug_bar)
#TOP-right, growing left - the same shape as the bottom-right prop-debug box, which is why the two
#do not collide. Parented to the VIEW rather than to SceneRoot, exactly as that box is, so the two
#debug surfaces live in one place in the tree.
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

#Stopping WRITES the capture and prints the folder, so the owner has a path to send without hunting.

## Toggle the capture.
func _on_debug_record() -> void:
	if EventLog.enabled:
		EventLog.end()
		var dir := EventLog.save("playtest_%d" % Time.get_unix_time_from_system())
		_record_button.text = TRANSLATION.find('DEBUG_RECORD')
		print("=== EventLog written ===\n%s\n%s" % [dir, EventLog.summary()])
	else:
		EventLog.begin()
		_record_button.text = TRANSLATION.find('DEBUG_RECORD_STOP')

#⚠ THE CUE IS OTHERWISE UNREACHABLE IN THE RUNNING GAME, AND THAT IS A CONTENT FACT, NOT A BUG:
#spotlight_cued is filtered to skills implementing on_spotlight, and the only other one is a RULES
#card with no CardVisual, so the light set is always empty. See SpotlightProbe's header.

#⚠ IT PICKS A CARD THAT IS NOT ALREADY SPOTLIT, WHICH IS THE WHOLE TRICK: the cue fires on the
#EDGE, skill_spotlight_check announcing only a card that TRANSITIONED into spotlit. An uncovered
#card is spotlit the instant the sweep runs, so pressing again lands on the next card.

## Stamp SpotlightProbe onto a board card and re-run the sweep, so the cue actually fires.
func _on_debug_cue() -> void:
	if not game or not game.state: return
#⚠ STAMP, THEN ASK THE CARD WHETHER IT IS ACTUALLY SPOTLIT, AND UNSTAMP IF NOT. Picking the
#first skill-free board card is not enough: a ZONE-stage column header is reported by
#_blocked_from_above() as covered, so is_spotlit() is false and the sweep correctly ignores it.

#Only an UNCOVERED card transitions, so the choice has to be made by asking, not by guessing which
#stage is on top.
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
#The REAL sweep, not a hand-built emit, so what you see is what a real activation looks like.
	await game.skill_spotlight_check()

func _on_debug_undo() -> void:
	if not game.debug_undo():
		print("debug_undo: nothing left to rewind to")

func _on_debug_redo() -> void:
	if not game.debug_redo():
		print("debug_redo: nothing to replay")
