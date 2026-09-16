class_name HudContainer
extends PanelContainer
## The one container on the wall overlay: shows the HUD or the description, never both.

@onready var _hud_stack : Control = %HudStack
@onready var _description_margin : MarginContainer = %DescriptionMargin
@onready var _description_panel : DescriptionPanel = %DescriptionPanel
@onready var _game_hud_margin : MarginContainer = %HudStack/GameHudMargin
@onready var _game_hud : Control = %GameHud
@onready var _map_hud : Control = %MapHud
@onready var _piles : HBoxContainer = %GameHud/Piles
@onready var _exit_button : Button = %ExitX
@onready var _exit_column : Control = _description_panel.get_node(^"%ExitColumn")

@onready var submit_button : Button = %Submit
@onready var undo_button : Button = %Undo
@onready var deck_ui : Control = %Deck
@onready var discard_ui : Control = %Discard
@onready var rules_ui : Control = %Rules
@onready var goal_label : Label = %Goal/Label
@onready var total_label : Label = %Total/Label
@onready var combo_label : Label = %Combo

@onready var fame_label : Label = %FameLabel
@onready var lap_label : Label = %LapLabel
@onready var luck_label : Label = %LuckLabel
@onready var map_deck_button : Button = %MapDeckButton

## The container's own rect changed (start or resize); `GameView` re-publishes the board insets off it.
signal container_rect_changed

## The container went back to the HUD; the board drops the locked card's marking on it.
signal description_dismissed

## A different screen is showing; the map drops the name it had pinned to a dot on its own picture.
signal active_screen_changed

## The X was accepted from the keyboard or pad; hiding it left nothing focused, so the screen takes the focus back.
signal exit_accepted

const SCENE := preload("res://UI/hud_container.tscn")

## One home for the "a standalone fixture with no `Main` gets a private instance" fallback every screen used to repeat.
static func ensure(existing: HudContainer, parent: Node) -> HudContainer:
	if existing:
		return existing
	var container := SCENE.instantiate() as HudContainer
	parent.add_child(container)
	return container

## How far the overlay's button row reaches down into the container -- BOTH contents start below it.
var _band_top : float = 0.0

# ⚠ KEYED BY THE SCREEN THAT MADE THEM, NEVER ONE FLAT LIST: this container outlives every screen
# on the wall and they tear down one at a time, so a finished show dropping the whole list would
# take the map's Deck button and the menu's inset with it.
var _screen_connections : Dictionary[Node, Array] = {}

## Connects `sig` to `callable` and remembers the pair under `screen`, whose own teardown drops it.
func connect_for_screen(screen: Node, sig: Signal, callable: Callable) -> void:
	if not _screen_connections.has(screen):
		screen.tree_exiting.connect(disconnect_for_screen.bind(screen), CONNECT_ONE_SHOT)
	sig.connect(callable)
	var pairs : Array = _screen_connections.get_or_add(screen, [])
	pairs.append([sig, callable])

## Drops every connection `screen` made through `connect_for_screen()` -- fired once, by `screen` leaving the tree.
func disconnect_for_screen(screen: Node) -> void:
	var pairs : Array = _screen_connections.get(screen, [])
	for pair : Array in pairs:
		var sig : Signal = pair[0] as Signal
		var callable : Callable = pair[1] as Callable
		if sig.is_connected(callable):
			sig.disconnect(callable)
	_screen_connections.erase(screen)

func _ready() -> void:
	(get_theme_stylebox("panel") as StyleBoxFlat).bg_color = PaletteDB.color(PaletteDB.ROLES.hud_background)
	_exit_button.tooltip_text = TRANSLATION.find('SIDEBAR_CLOSE')
	_exit_button.pressed.connect(dismiss_description)
	_exit_button.gui_input.connect(_on_exit_gui_input)
	_place_exit_button()
	show_hud()
	var overlay := get_parent() as WallOverlay
	if overlay:
		var follow_the_band := func() -> void:
			_position_below_overlay_buttons()
			get_viewport().size_changed.connect(_position_below_overlay_buttons)
		overlay.ready.connect(follow_the_band, CONNECT_ONE_SHOT)
	get_viewport().size_changed.connect(_apply_container_rect)
	PlayArea.settings().settings_changed.connect(_apply_container_rect)
	_apply_container_rect()

# Reads the band only after the OVERLAY has grown its row, at start and on every resize: this
# container is that row's CHILD, so its own `_ready()` and resize listener would run first.
# Only mounted under a `WallOverlay` in `wall.tscn`; a standalone instance (as the tests build) never connects.
func _position_below_overlay_buttons() -> void:
	var overlay := get_parent() as WallOverlay
	_band_top = overlay.button_band_bottom()
	var inset := roundi(overlay.button_band_inset())
	for margin : MarginContainer in [_game_hud_margin, _description_margin] as Array[MarginContainer]:
		margin.add_theme_constant_override("margin_top", ceili(_band_top))
		margin.add_theme_constant_override("margin_left", inset)
		margin.add_theme_constant_override("margin_right", inset)
	_place_exit_button()
	_fit_content()

# The exit X means GO BACK TO THE HUD: grown to every overlay control's touch target, parked in the
# container's top-right BELOW the overlay's button band, and its column is kept clear of the name.
func _place_exit_button() -> void:
	var target := WallInput.touch_target_px(get_viewport().get_visible_rect().size,
			PlayArea.settings())
	_exit_button.offset_left = -target
	_exit_button.offset_top = _band_top
	_exit_button.offset_bottom = _band_top + target
	_exit_column.custom_minimum_size.x = target

## The container's own rect at the current window size -- what `PlayArea.board_inset_left`/`board_inset_top` are derived from.
func container_rect() -> Rect2:
	return rect_for_window(get_viewport().get_visible_rect().size, PlayArea.settings())

## The space left beside this container inside `picture`'s own space -- the one conversion every hosted screen insets by; a fixture with no picture falls back to the plain window rect.
func rect_beside(picture: WallPicture) -> Rect2:
	var window := get_viewport().get_visible_rect().size
	var rect := container_rect()
	var top := container_is_top(window, PlayArea.settings())
	if picture: return picture.local_rect_beside(window, rect, top)
	var inset := WallPicture.inset_beside(rect, top, 1.0)
	return Rect2(inset, window - inset)

## How big a window pixel is against one of `picture`'s own -- what a screen inside it converts its own card sizes through to match this container's.
func window_scale(picture: WallPicture) -> float:
	return picture.window_scale(get_viewport().get_visible_rect().size) if picture else 1.0

## Hosts a `DeckViewer` or `ChoiceViewer` opened in `picture`: relays its highlights to `relay`, returns to the lock on close, fits it beside this container.
func host_viewer(viewer: Node, picture: WallPicture, relay: Signal) -> void:
	viewer.connect(&"info_requested", func(entry: InfoEntry) -> void: entry.relay_to(relay))
	viewer.connect(&"highlight_cleared", return_to_lock)
	if viewer is DeckViewer: (viewer as DeckViewer).fallback_focus = _exit_button
	var fit := func() -> void: _fit_viewer(viewer, picture)
	connect_for_screen(viewer, container_rect_changed, fit)
	fit.call()

# A VIEWER IS A SCREEN OCCUPANT LIKE THE BOARD, re-fitted after its screen's own inset. It republishes
# only while a description is UP, redrawing the preview at its own card size: a dismissal is the
# player's act and a window change is not one.
func _fit_viewer(viewer: Node, picture: WallPicture) -> void:
	viewer.call(&"fit_beside", rect_beside(picture), window_scale(picture))
	if showing_description(): viewer.call(&"republish_highlight")

## Sets this control's own rect to `container_rect()` and tells listeners it moved.
func _apply_container_rect() -> void:
	var rect := container_rect()
	position = rect.position
	size = rect.size
	_fit_content()
	container_rect_changed.emit()

## Lays both contents out inside the margins: the pile row shares their width and a shown description re-wraps to it.
func _fit_content() -> void:
	var content := _content_size()
	_fit_piles_to_width(content.x)
	if _description_panel.visible: _description_panel.resize_to(content)

## The pile row's own width comes off the container's real size, never a literal, so Deck/Discard/Rules keep sharing it evenly however narrow the container gets.
func _fit_piles_to_width(width: float) -> void:
	var count := _piles.get_child_count()
	if count == 0: return
	var gaps := _piles.get_theme_constant("separation") * (count - 1)
	var each := _floored_even_share(width - gaps, count)
	for pile : Control in _piles.get_children():
		pile.custom_minimum_size.x = each

## Floored, never the exact share -- the layout pass rounds each child's box to whole pixels, and rounding a fractional minimum UP would push the row past its width.
static func _floored_even_share(available: float, count: int) -> float:
	return maxf(floorf(available / float(count)), 0.0)

## Whether `window` puts the container on the TOP band instead of the SIDE (the side case's own width decides).
static func container_is_top(window: Vector2, settings_res: PlayerSettings) -> bool:
	return (window.x - _container_px(window, false, settings_res)) / window.y < 1.0

# Pure arithmetic seam for `container_rect()`, so a headless test can drive the production
# formula without booting a window. Flush against the INNER edge of its band when clamped,
# leaving the empty space outboard of it.
static func rect_for_window(window: Vector2, settings_res: PlayerSettings) -> Rect2:
	if container_is_top(window, settings_res):
		var px := _container_px(window, true, settings_res)
		var inner_edge := settings_res.container_size_fraction * window.y
		return Rect2(0.0, inner_edge - px, window.x, px)
	var px := _container_px(window, false, settings_res)
	var inner_edge := settings_res.container_size_fraction * window.x
	return Rect2(inner_edge - px, 0.0, px, window.y)

## The fraction of the band's own axis of `window`, capped only where that axis outruns the reference shape.
static func _container_px(window: Vector2, top: bool, settings_res: PlayerSettings) -> float:
	var px := settings_res.container_size_fraction * (window.y if top else window.x)
	if not _band_axis_outruns_reference(window, top): return px
	return minf(px, settings_res.container_size_max_px)

# The cap is a rule about SHAPE, not about pixel count: it bites only where the band's own axis
# outruns the project's reference window shape, so a window of that shape keeps the authored inset
# at any size and only an ultrawide -- or an ultratall under the top band -- clamps.
static func _band_axis_outruns_reference(window: Vector2, top: bool) -> bool:
	var reference := PlayArea.reference_window_size()
	if top: return window.y * reference.x > window.x * reference.y
	return window.x * reference.y > window.y * reference.x

## The description each screen was last showing, so coming back returns to what you were reading rather than the HUD.
var _entry_by_screen : Dictionary[StringName, InfoEntry] = {}
## Which screen's description is on the panel now -- the key a new one is remembered under.
var _active_screen : StringName = &""

# Keyed by `Main`'s own focus id: `&"game"`, `&"map"`, `&"start_menu"` (shown, neither HUD up) and
# `&""` for wall view (hidden). Leaving a screen DETACHES its description rather than freeing it,
# so coming back re-shows exactly what was being read.
func set_active_screen(screen: StringName) -> void:
	if screen != _active_screen:
		_description_panel.detach_entry()
		_active_screen = screen
		var remembered : InfoEntry = _entry_by_screen.get(_active_screen)
		if remembered == null or _screen_is_processing(): _swap_to_hud()
		else: show_description(remembered)
		active_screen_changed.emit()
	visible = screen != &""
	if not visible: return
	_game_hud.visible = screen == GAME_SCREEN
	_map_hud.visible = screen == MAP_SCREEN

func show_hud() -> void:
	_swap_to_hud()
	clear_lock()
	description_dismissed.emit()

# A DISMISSAL ENDS WHAT WAS BEING READ, so the screen forgets it: leaving and coming back finds the
# HUD. The cascade's hold is not a dismissal and goes through `show_hud()`, keeping the memory.
func dismiss_description() -> void:
	_release_shown_entry()
	_release_remembered_entry(_active_screen, null)
	show_hud()

# A KEY/PAD ACCEPT ON THE X IS TAKEN HERE, before the button's own press: hiding the X leaves nothing
# focused, and only that player needs the focus back. A mouse click also focuses the X, so it stays
# the button's own press and leaves the focus where the pointer put it.
func _on_exit_gui_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_accept"): return
	_exit_button.accept_event()
	dismiss_description()
	exit_accepted.emit()

# ⚠ A SCREEN CHANGE IS NOT A DISMISSAL: the screen being left keeps its lock, and its board keeps
# the marking on the locked card, so coming back finds what was being read exactly as it was. Every
# other route to the HUD is `show_hud()`, the one place the lock is cleared and the drop announced.
func _swap_to_hud() -> void:
	_hud_stack.visible = true
	_description_panel.visible = false
	_exit_button.visible = false
	_aim_scroll_stick(0.0)
	_refresh_exit_focus()

# The locked entry is what a lost highlight comes BACK to, so a hover that displaces it takes its
# visual OUT rather than freeing it. A publication arriving mid-cascade is dropped instead, and it
# owns the live preview the board built for it, which nothing else would collect.
func show_description(entry: InfoEntry) -> void:
	if _screen_is_processing():
		_free_detached_visual(entry)
		return
	var locked : InfoEntry = _locked_entry_by_screen.get(_active_screen)
	if locked and locked != entry and _description_panel.current_entry == locked:
		_description_panel.detach_entry()
	_release_remembered_entry(_active_screen, entry)
	_entry_by_screen[_active_screen] = entry
	_hud_stack.visible = false
	_exit_button.visible = true
	_refresh_exit_focus()
	_description_panel.show_entry(entry, _content_size())

## Whether the description is what shows -- `GameView` asks before spending a cancel on dismissing it.
func showing_description() -> bool:
	return _description_panel.visible

## The card each screen's description is LOCKED to -- a lock survives leaving and returning, exactly as the remembered entry does.
var _lock_by_screen : Dictionary[StringName, CardData] = {}

## The entry that lock is showing, so losing the highlight can come back to the locked card itself.
var _locked_entry_by_screen : Dictionary[StringName, InfoEntry] = {}

## Pins the description to `target`: it stays the sidebar's subject until a dismissal takes the container back to the HUD.
func lock_to(entry: InfoEntry, target: CardData) -> void:
	_release_locked_entry(_active_screen)
	_lock_by_screen[_active_screen] = target
	_locked_entry_by_screen[_active_screen] = entry
	show_description(entry)

func clear_lock() -> void:
	_lock_by_screen.erase(_active_screen)
	_release_locked_entry(_active_screen)

func is_locked() -> bool:
	return _lock_by_screen.has(_active_screen)

## Nothing is highlighted any more: a locked description returns to its own card, an unlocked one keeps the entry it has.
func return_to_lock() -> void:
	if not is_locked(): return
	var locked : InfoEntry = _locked_entry_by_screen[_active_screen]
	if _description_panel.current_entry == locked: return
	show_description(locked)

# A LOCK LEAVING IS THE LAST MOMENT ANYTHING CAN FREE ITS VISUAL: a displaced entry is out of the
# panel and, once the next lock replaces it, in no dictionary either.
func _release_locked_entry(screen: StringName) -> void:
	var locked : InfoEntry = _locked_entry_by_screen.get(screen)
	if locked: _free_detached_visual(locked)
	_locked_entry_by_screen.erase(screen)

# ONE OWNER FOR A REPLACED MEMORY: a remembered entry that is neither mounted, nor holding this
# screen's lock, nor the one about to show is in no dictionary and no tree once it is overwritten,
# and nothing else would ever collect the preview it carries.
func _release_remembered_entry(screen: StringName, keeping: InfoEntry) -> void:
	var remembered : InfoEntry = _entry_by_screen.get(screen)
	if remembered and remembered != keeping \
			and remembered != _locked_entry_by_screen.get(screen):
		_free_detached_visual(remembered)
	_entry_by_screen.erase(screen)

# ⚠ A SCREEN'S CONTAINER STATE BELONGS TO THE CONTENT THAT PUBLISHED IT, NOT TO THE SCREEN ID:
# `Main` reuses one id for every show, so a show that is torn down has to hand back its memory,
# its lock and its cascade flag or the next one inherits them.
func release_screen(screen: StringName) -> void:
	if screen == _active_screen:
		_release_shown_entry()
		_swap_to_hud()
	_release_remembered_entry(screen, null)
	_release_locked_entry(screen)
	_lock_by_screen.erase(screen)
	if screen == GAME_SCREEN: _game_processing = false

# ⚠ FREED HERE AND NOT LEFT TO THE DICTIONARIES: on a whole-tree teardown this container's own
# `_exit_tree()` has already run and cleared them, so a visual taken out of the panel afterwards
# would be in no dictionary and no tree -- measured, 24 orphaned previews across the suite.
func _release_shown_entry() -> void:
	var shown : InfoEntry = _description_panel.current_entry
	_description_panel.detach_entry()
	if shown: _free_detached_visual(shown)

## The game screen's own focus id: the one screen with a cascade to watch, and the one whose content is replaced show by show.
const GAME_SCREEN : StringName = &"game"

## The map's own focus id: its content is the run, which a new run replaces on the same map.
const MAP_SCREEN : StringName = &"map"

## The start menu's own focus id: its content is the deck picker, and what the picker described closes with it.
const MENU_SCREEN : StringName = &"start_menu"

## Whether the game screen is mid-cascade -- the one screen with a cascade.
var _game_processing : bool = false

## Relayed by `GameView` from `Game.processing`: true reverts to the HUD and drops the lock for good, and once it ends the HUD holds until the next publication.
func set_processing(busy: bool) -> void:
	_game_processing = busy
	if _screen_is_processing(): show_hud()

## Whether the screen now showing is the one mid-cascade -- any other screen's container behaves as it always does.
func _screen_is_processing() -> bool:
	return _game_processing and _active_screen == GAME_SCREEN

# THE SIDEBAR READS ITS KEYS IN `_input`, BEFORE THE GUI PASS: the viewport's focus-neighbour
# search consumes any arrow that finds a neighbour, so an arrow read any later never arrives while
# a board cell holds the focus. Page keys scroll whenever the description shows, arrows once locked.
func _input(event: InputEvent) -> void:
	if not showing_description(): return
	var stick := event as InputEventJoypadMotion
	if stick and stick.is_action(&"sidebar_scroll"):
		_aim_scroll_stick(stick.axis_value)
		return
	if _navigates_to_exit(event):
		_exit_button.grab_focus()
		get_viewport().set_input_as_handled()
		return
	var pages := 0.0
	if event.is_action_pressed(&"ui_page_down", true): pages = 1.0
	elif event.is_action_pressed(&"ui_page_up", true): pages = -1.0
	elif not is_locked(): return
	elif event.is_action_pressed(&"ui_down", true): pages = DescriptionPanel.WHEEL_STEP_PAGES
	elif event.is_action_pressed(&"ui_up", true): pages = -DescriptionPanel.WHEEL_STEP_PAGES
	if is_zero_approx(pages): return
	_description_panel.scroll_by_pages(pages)
	get_viewport().set_input_as_handled()

# ⚠ THE BOARD'S CELLS AND THE EXIT X SIT IN DIFFERENT VIEWPORTS, and Godot's focus search never
# crosses one, so the sidebar carries navigation onto the X itself: up, off the top of a locked
# description, is the press that has nothing left to scroll and leaves its content upward.
func _navigates_to_exit(event: InputEvent) -> bool:
	return is_locked() and event.is_action_pressed(&"ui_up", true) and _description_panel.at_top()

## The scroll stick's last reported deflection, integrated per frame while it is off centre.
var _scroll_stick : float = 0.0

# A STICK REPORTS ONLY WHEN IT MOVES, so its deflection is held and integrated per frame rather
# than scrolled once. Inside the action's own deadzone it is at rest, which stops the scroll.
func _aim_scroll_stick(axis_value: float) -> void:
	var deadzone := InputMap.action_get_deadzone(&"sidebar_scroll")
	_scroll_stick = axis_value if absf(axis_value) >= deadzone else 0.0
	set_process(not is_zero_approx(_scroll_stick))

func _process(delta: float) -> void:
	_description_panel.scroll_by_pages(
			_scroll_stick * delta * PlayArea.settings().sidebar_scroll_pages_per_second)

# ⚠ A PAD PLAYER MUST ALWAYS BE ABLE TO DISMISS WHAT IS SHOWN: the X joins keyboard/pad
# navigation for as long as it is up, since a viewer's own opening highlight can hide the button
# that opened it. Back on the HUD, nothing here is in anyone's focus chain.
func _refresh_exit_focus() -> void:
	_exit_button.focus_mode = Control.FOCUS_ALL if _exit_button.visible else Control.FOCUS_NONE

## Re-draws the description's preview at `card_px`: the size a board card is drawn at moves with the window, and the preview reads as the same object only while it matches.
func resize_preview(card_px: Vector2) -> void:
	_description_panel.resize_preview(card_px)

## The room both contents share: the container minus its margins, which are the same for the HUD and the description.
func _content_size() -> Vector2:
	var left := _description_margin.get_theme_constant(&"margin_left")
	var right := _description_margin.get_theme_constant(&"margin_right")
	return container_rect().size - Vector2(left + right, _description_margin.get_theme_constant(&"margin_top"))

# A stashed visual is a NODE outside the tree that nothing else will collect. The MOUNTED one is
# the panel's own child and goes with the tree, so only the detached ones are freed here.
func _exit_tree() -> void:
	for screen : StringName in _entry_by_screen:
		_free_detached_visual(_entry_by_screen[screen])
	for screen : StringName in _locked_entry_by_screen:
		_free_detached_visual(_locked_entry_by_screen[screen])
	_entry_by_screen.clear()
	_locked_entry_by_screen.clear()

# One entry can be both a screen's remembered one and its locked one, so a visual already on its
# way out is left alone rather than queued a second time.
func _free_detached_visual(entry: InfoEntry) -> void:
	var visual : Node = entry.visual
	if visual and visual.get_parent() == null and not visual.is_queued_for_deletion():
		visual.queue_free()
