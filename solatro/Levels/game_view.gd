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
#The board lives inside this view's own SubViewport and has no reach to the camera outside it.

## Relayed from PlayArea so Main can step its wall camera.
signal overview_pan_requested(grid_index: int)
## Relayed from PlayArea so Main can bounce its wall camera off the board's OVERVIEW edge.
signal overview_bounce_requested(step: int)

# Continue button sizing (win/lose screen) — named, no magic numbers in logic.
const CONTINUE_FONT_SIZE := 40
const CONTINUE_OFFSET_Y := 220.0

var game : Game = null

@onready var play_container: Control = %PlayContainer
@onready var play_area: PlayArea = %PlayArea
@onready var submit_button: Button = %Submit
@onready var undo_button: Button = %Undo
## Opens and closes the marks layer, for the mouse, the keyboard and the controller alike.
@onready var plan_layer_button: Button = %PlanLayer
@onready var deck_ui: Control = %Deck
@onready var discard_ui: Control = %Discard
@onready var rules_ui: Control = %Rules
@onready var win_screen: Label = %WinScreen
@onready var lose_screen: Label = %LoseScreen
@onready var goal_label: Label = %Goal/Label
@onready var total_label: Label = %Total/Label
#⚠ The MultScore label and its Col / x / Row children are the RETIRED act payout's display.
#Nothing in the grid economy writes any of them, so they are emptied at startup and never written
#again: the show's score is exactly two numbers, total_label and combo_label.

#Combo is a CHILD of MultScore, which is why the parent is emptied rather than hidden.
@onready var mult_label: Label = %MultScore
@onready var col_label: Label = %MultScore/Col
@onready var row_label: Label = %MultScore/Row
@onready var mult_x_label: Label = %MultScore/x
@onready var combo_label: Label = %MultScore/Combo
#⚠ The DIRECTOR is created here rather than placed in the scene because it must bind AFTER
#`game` exists: it connects to CardEnvironment.spotlight_cued, and the environment is `game` itself.

## The spotlight's light layer, and the node that feeds it.
@onready var light_layer: LightLayer = %LightLayer
var spotlight_director : SpotlightDirector = null

#The furniture follows the board's pan rather than sitting at a fixed spot on the wide picture
#(owner ruling). It is authored against grid 0's resting position, and PlayArea.pan_grid is the ONE
#writer of which grid the view rests on.

## The Deck, the score column, the skill text and the End, Discard and Rules buttons.
@onready var _furniture : Array[Control] = [deck_ui, discard_ui, rules_ui, submit_button,
		undo_button, plan_layer_button, %Goal, %Total, %MultScore, %Preview]
## Each control's authored x -- fixed forever, read once off the scene.
var _furniture_authored_x : Array[float] = []
#Main is the only writer of both; this view only ever reads them and never computes where the
#camera should be. Null or invalid until bind_wall_camera() runs, which Main.enter_game() does right
#after instantiating this view.

## Main's ONE wall camera, and a live getter for the game picture's rect centre-x.
var _wall_camera : Camera2D = null
var _wall_rect_centre_x : Callable = Callable()

func _ready() -> void:
#The retired act payout's four labels are emptied once here: they are authored with placeholder
#text, and with nothing writing them the player would read a frozen "0 0 x 0" beside the live total.

#⚠ %MultScore IS A FURNITURE CONTROL AND _hud_authored_width() READS ITS LIVE MINIMUM SIZE, which
#for a Label depends on its TEXT, so emptying it feeds the board's centring. Re-check that before
#emptying or re-texting any other furniture label.

#It is safe here only because %MultScore was never the widest: Rules is authored at x 302 and
#%MultScore at 202 plus one digit, so the max is unchanged.
	mult_label.text = ""
	col_label.text = ""
	row_label.text = ""
	mult_x_label.text = ""
#The logic node is created and injected BEFORE it is added to the tree, so its _enter_tree and
#_ready run with the view fully bound.
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
	submit_button.pressed.connect(_on_submit_pressed)
	undo_button.pressed.connect(_on_undo_pressed)
	plan_layer_button.text = TRANSLATION.find('PLAN_LAYER_TOGGLE')
	plan_layer_button.tooltip_text = TRANSLATION.find('PLAN_LAYER_TOGGLE_HINT')
	plan_layer_button.pressed.connect(_on_plan_layer_pressed)
	play_area.data_selected.connect(_on_data_selected)
	play_area.info_requested.connect(func(entry: InfoEntry) -> void: info_requested.emit(entry))
	play_area.overview_pan_requested.connect(
			func(grid_index: int) -> void: overview_pan_requested.emit(grid_index))
	play_area.overview_bounce_requested.connect(
			func(step: int) -> void: overview_bounce_requested.emit(step))
	(deck_ui.get_node(^"Button") as Button).pressed.connect(func() -> void: DeckViewer.show_deck(self, game.state.draw_deck))
	(discard_ui.get_node(^"Button") as Button).pressed.connect(func() -> void: DeckViewer.show_deck(self, game.state.discard_deck))
	(rules_ui.get_node(^"Button") as Button).pressed.connect(func() -> void: DeckViewer.show_deck(self, game.state.rules_deck))

	add_child(game)
	_add_prop_debug_controls()
#_refresh_hud early-returns while _ready runs, so it is refreshed deferred and a fresh goal or a
#resumed score shows immediately.
	_refresh_hud.call_deferred()
	_capture_furniture_authored_x()

#Debug prop stepping (owner tool): the toggle holds every finished prop tick open through
#PropLayer.manual_step, pausing the whole run_props loop at its SYNC await, and the step button
#releases exactly one tick, so a prop run can be watched tick by tick.

#Mouse-only (FOCUS_NONE) so keyboard and controller navigation never lands on them.
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

#A NEW combo class registered this act: refresh and pulse the combo label. combo_classes.append()
#does not emit state_changed, so this signal is the live path; sync_scores() and state_changed
#re-run _refresh_hud after apply_act_score clears the set.
var _combo_tween : Tween = null

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

#Runs once; the scene's own offsets never change afterwards.

## Reads each furniture control's authored x straight off the scene.
func _capture_furniture_authored_x() -> void:
	_furniture_authored_x.clear()
	_furniture_authored_y.clear()
	for control : Control in _furniture:
		_furniture_authored_x.append(control.position.x)
		_furniture_authored_y.append(control.position.y)
	_publish_hud_reserve()

#⚠ Needed because the HUD SCALES: _process rewrites x every frame, but y is written once per
#picture size and would otherwise compound.

## Each control's authored y, captured with its x.
var _furniture_authored_y : Array[float] = []

#How much the HUD is drawn larger than it was authored: the picture's width over the reference
#viewport's. SceneRoot fills the picture, so without this the furniture keeps its authored size on a
#canvas a third wider again and reads as a small cluster in one corner.

#⚠ ONLY THE HUD SCALES (owner ruling). The board is NOT scaled with it: the board lays out in
#PICTURE pixels and game_picture_design_size() IS its own span, so scaling it too would render a
#1495-wide board inside a 1495-wide picture at 1940 px.

#⚠ THE WINDOW'S SHAPE NEVER REACHES THIS. The picture is a fixed aspect, so the HUD's canvas is
#the same shape whatever the screen is (owner: *"hud does not matter for picture... window
#proportions shouldnt affect hud layout for portrait vs landscape view"*).
func hud_scale() -> float:
	var authored := _hud_authored_width()
	if authored <= 0.0: return 1.0
	var design := float(PlayArea.game_picture_design_size(SettingsManager.settings).x)
	return SettingsManager.settings.hud_width_fraction * design / authored

#Hands the board the width the HUD's rectangle takes on the left, so the grid centres in what is
#LEFT of the screen rather than on the screen (owner: *"center of screen for stuff like grid should
#be center of remaining space not taken by the hud"*).

#⚠ THE AUTHORED x, NEVER THE LIVE ONE. _process() slides every furniture control by the board's
#pan, so a reserve read off `position` would breathe in and out with every pan and drag the board
#with it. The authored offsets are the HUD's real footprint and they never move.
func _publish_hud_reserve() -> void:
	if not is_instance_valid(play_area): return
	var k := hud_scale()
	for i : int in _furniture.size():
		var control : Control = _furniture[i]
		if not is_instance_valid(control): continue
		control.scale = Vector2.ONE * k
		control.position.y = _furniture_authored_y[i] * k
	play_area.board_inset_left = _hud_authored_width() * k

#⚠ AUTHORED, NEVER LIVE, for the same reason _publish_hud_reserve reads the authored offsets.

## The furniture's own width at its AUTHORED offsets, before any scaling.
func _hud_authored_width() -> float:
	var right := 0.0
	for i : int in _furniture.size():
		var control : Control = _furniture[i]
		if not is_instance_valid(control): continue
		right = maxf(right, _furniture_authored_x[i] + control.get_combined_minimum_size().x)
	return right

#OVERVIEW furniture tracks the camera's CURRENT position every frame instead of the pan_grid index
#it was set from: the camera's own tween runs on a separate clock, so following the index desyncs
#for the length of every pan. Called once, right after Main instantiates this view.
func bind_wall_camera(camera: Camera2D, rect_centre_x: Callable) -> void:
	_wall_camera = camera
	_wall_rect_centre_x = rect_centre_x

#Slides every furniture control from its authored (grid-0) x. FOCUSED: the scroller pans there, the
#camera never moves and pan_grid updates synchronously with it. OVERVIEW: the wall camera's LIVE
#position, read fresh every frame, because Main tweens that camera on its own clock.

#⚠ Physics interpolation forces Camera2D onto the physics tick, so its rendered position on an
#idle frame differs from the raw `.position` this reads: the furniture holds the board through a pan
#but still shivers against it.

#⚠ get_global_transform_interpolated() DOES NOT EXIST in Godot 4.7.2 (checked against
#ClassDB.class_get_method_list); calling it stops this script compiling, which cascades into
#card_data.gd and pip_suit.gd and leaves the map unable to enter a game.
func _process(_delta: float) -> void:
	if not is_instance_valid(play_area) or _furniture_authored_x.size() != _furniture.size():
		return
	var pitch := PlayArea.grid_position_size_px(SettingsManager.settings).x
	var shift : float = play_area.pan_grid * pitch
	if play_area.view_mode == PlayArea.ViewMode.OVERVIEW and is_instance_valid(_wall_camera) \
			and _wall_rect_centre_x.is_valid():
		shift = pitch * play_area.resting_grid() \
				+ (_wall_camera.position.x \
						- (_wall_rect_centre_x.call() as float))
	for i : int in _furniture.size():
		var control : Control = _furniture[i]
#⚠ The authored x is scaled; the PAN is not. The pan is already a picture-pixel quantity, from
#grid_position_size_px, while the authored offsets are in the reference viewport's.
		if is_instance_valid(control):
			control.position.x = _furniture_authored_x[i] * hud_scale() + shift

func _on_processing_changed(busy: bool) -> void:
	submit_button.disabled = busy
#Undo stays ENABLED while busy: pressing it mid-act cancels the act, and at the win/lose screen it
#rewinds the final Submit. Game ignores the press in the states where undo cannot act.

func _on_submit_label_changed(text: String) -> void:
	submit_button.text = text

#The win/lose overlay covers ONLY the play area, living inside PlayContainer: the board underneath
#is blocked, by the overlay's STOP filter for the mouse and by dropping the card controls' focus for
#keyboard and controller.

#The rest of the HUD stays clickable - Undo rewinds the outcome and the viewers still open - while
#Submit and Next stay disabled, processing holding true with no more card logic.
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
	_continue_button.position.y += CONTINUE_OFFSET_Y
	_continue_button.pressed.connect(game.exit_show)
	_continue_button.grab_focus()

#The Game follows up with the normal undo rebuild, whose fresh board controls restore card focus.

## Undo at the win/lose screen: drop the overlay.
func _on_show_unresolved() -> void:
	win_screen.hide()
	lose_screen.hide()
#The undo's rebuild follows and re-derives header focus.
	play_area.enable_board_focus()
	if _continue_button and is_instance_valid(_continue_button):
		_continue_button.queue_free()
	_continue_button = null
#Keyboard and controller: focus was on the freed Continue button.
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

#The held-cards guard is the view's job -- the selection state lives in PlayArea -- and a board
#being looked at is not rewound either.
func _on_undo_pressed() -> void:
	if play_area.selected_cards or not _board_is_playable(): return
	game.undo()

#ONE CONTROL EVERY INPUT MODE REACHES THE SAME WAY: a focusable button answers a mouse click, a
#keyboard accept and a controller accept without any of the three being wired on its own. Refused
#while the board resolves, the way a selection is: the rebuild that cascade ends in closes it.
func _on_plan_layer_pressed() -> void:
	if game.processing: return
	play_area.plan_layer_open = not play_area.plan_layer_open

func _on_data_selected(data: CardData) -> void:
	if game.processing: return
	if play_area.selected_cards:
		var held0 := play_area.selected_cards[0]
		if (data == held0
				or game.find_data_vec3(data) == game.find_data_vec3(held0) - Vector3i(0, 0, 1)):
			play_area.ungrab_cards()
		elif data not in play_area.selected_cards:
			var placed := await game.try_place(play_area.selected_cards, data)
			if placed:
				play_area.ungrab_cards()
	else:
		var grabbed := await game.try_grab(data)
		play_area.grab_cards(grabbed)


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
#Focus is never stolen from the board's keyboard and controller navigation.
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
#Every channel, because a playtest bug can be anywhere.
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
#A real skill is never replaced - that would change the act.
		if data.skill != null: continue
		data.with_skill(SpotlightProbe.new())
		if data.skill.is_spotlit():
			chosen = data
			break
#Put back exactly as it was.
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
