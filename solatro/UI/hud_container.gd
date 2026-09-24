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
@onready var plan_layer_button : Button = %PlanLayer
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

## The sidebar let the focus go -- the X accepted from the keyboard or pad, or a right press off the last control -- leaving nothing focused, so the screen takes it back.
signal exit_accepted

## The slide reached its aim -- or this container is leaving, which releases its waiters too.
signal slide_settled

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
	_exit_button.pressed.connect(_dismiss_from_the_x)
	_exit_button.gui_input.connect(_on_exit_gui_input)
	_place_panel_controls()
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
	_place_panel_controls()
	_fit_content()

# EVERY CONTROL THAT CHANGES WHAT THE SIDEBAR SHOWS IS ONE TOUCH TARGET. The exit X means go back
# to the HUD, parked in the container's top-right BELOW the overlay's button band, with its column
# keeping the name clear of it.
func _place_panel_controls() -> void:
	var target := WallInput.touch_target_px(get_viewport().get_visible_rect().size,
			PlayArea.settings())
	_exit_button.offset_left = -target
	_exit_button.offset_top = _band_top
	_exit_button.offset_bottom = _band_top + target
	_exit_column.custom_minimum_size.x = target

## The container's own rect at the current window size -- what `PlayArea.board_inset_left`/`board_inset_top` are derived from.
func container_rect() -> Rect2:
	return rect_for_window(get_viewport().get_visible_rect().size, PlayArea.settings())

## How far the container has slid in from its own edge: 0 fully off the window, 1 at its resting rect.
var _slide : float = 1.0

## Where the slide is heading; a reversal rewrites this rather than racing a second mover against it.
var _slide_aim : float = 1.0

## How far in the container has slid -- 1 at rest, 0 off the window.
func slid_fraction() -> float:
	return _slide

# THE CONTAINER OVERLAYS THE PICTURE AND YIELDS ONLY WHAT IT HAS ACTUALLY SLID IN: the screens
# beside it re-fit to this, so before the slide they have the whole picture and the picture's edges
# meet the window's. Scaled along the band's own axis, which is the axis `inset_beside()` reads.
func published_rect() -> Rect2:
	var rect := container_rect()
	if container_is_top(get_viewport().get_visible_rect().size, PlayArea.settings()):
		return Rect2(rect.position, Vector2(rect.size.x, rect.size.y * _slide))
	return Rect2(rect.position, Vector2(rect.size.x * _slide, rect.size.y))

# ⚠ AWAITED BY `Main` BEFORE THE CAMERA MOVES: the sidebar is out before a leave starts and comes
# back only once the picture has landed. A reversal rewrites the aim and the travel runs on from
# where it is, so every request ends at a rest state; one with nothing to show refuses it.

# ⚠ **THE WAIT MUST NOT OUTLIVE ITS OWNER.** A tween's `finished` never came after `kill()`; the
# TREE's frame came after `Main` was freed and resumed on this freed container. A signal THIS node
# owns dies with it, and `_exit_tree()` fires it first, releasing waiters while all is still valid.
func slide_to(target: float) -> void:
	if target > 0.0 and not _wants_container(): return
	_slide_aim = clampf(target, 0.0, 1.0)
	if target > 0.0: visible = true
	if not is_equal_approx(_slide, _slide_aim):
		set_process(true)
		await slide_settled
	visible = _slide_aim > 0.0

# THE ONE WRITER OF WHERE THE CONTAINER SITS: the slide, a screen change and a resize all come
# through here, so the drawn position and the rect the screens yield to cannot disagree.

# ⚠ ALREADY THERE MEANS WRITE NOTHING. This announces the rect, a hosted viewer re-publishes its
# highlight on that announcement, and the publication comes straight back into `show_description()`
# -- a loop that overflows the stack the moment the menu's picker opens one.
func _write_slide(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(_slide, next): return
	_slide = next
	_apply_container_rect()

# The slide's own step, and the scroll stick's, on the one `_process` this control owns. Both are
# per-frame integrations of a held value, and `set_process` stays on while either is live.
func _process(delta: float) -> void:
	_advance_the_slide(delta)
	_description_panel.scroll_by_pages(
			_scroll_stick * delta * PlayArea.settings().sidebar_scroll_pages_per_second)
	if is_equal_approx(_slide, _slide_aim) and is_zero_approx(_scroll_stick):
		set_process(false)

# A JUMP, NOT A TRAVEL: the aim moves with it, or the per-frame step would carry the container
# straight back toward wherever the last request had aimed it.
func _jump_slide(value: float) -> void:
	_slide_aim = clampf(value, 0.0, 1.0)
	_write_slide(_slide_aim)

## Moves the slide one frame toward its aim at the authored speed -- a whole width per `container_slide_duration`.
func _advance_the_slide(delta: float) -> void:
	if is_equal_approx(_slide, _slide_aim): return
	var duration := PlayArea.settings().container_slide_duration
	if duration <= 0.0: _write_slide(_slide_aim)
	else: _write_slide(move_toward(_slide, _slide_aim, delta / duration))
	if is_equal_approx(_slide, _slide_aim): slide_settled.emit()

## How far off its resting place the slide has pushed the container, along the band's own axis.
func _slide_offset(rect: Rect2) -> Vector2:
	var out := 1.0 - _slide
	if container_is_top(get_viewport().get_visible_rect().size, PlayArea.settings()):
		return Vector2(0.0, -out * rect.size.y)
	return Vector2(-out * rect.size.x, 0.0)

# Whether any screen wants this container at all: never in wall view, and on the menu only while a
# description is actually up, since the menu carries no HUD of its own.
func _wants_container() -> bool:
	if _active_screen == &"": return false
	if _active_screen == MENU_SCREEN: return showing_description()
	return true

## The space left beside this container inside `picture`'s own space -- the one conversion every hosted screen insets by; a fixture with no picture falls back to the plain window rect.
func rect_beside(picture: WallPicture) -> Rect2:
	return _space_beside(picture, published_rect())

# WHAT A SCREEN FITS TO: where the container RESTS, never where the slide has it this instant. A
# viewer's cards stay reachable once the description they publish brings the sidebar in, and the
# map keeps one scale through the slide, which only shifts it.
func resting_rect_beside(picture: WallPicture) -> Rect2:
	return _space_beside(picture, container_rect())

## The space left beside `rect` inside `picture`'s own space; a fixture with no picture falls back to the plain window rect.
func _space_beside(picture: WallPicture, rect: Rect2) -> Rect2:
	var window := get_viewport().get_visible_rect().size
	var top := container_is_top(window, PlayArea.settings())
	if picture: return picture.local_rect_beside(window, rect, top)
	var inset := WallPicture.inset_beside(rect, top, 1.0)
	return Rect2(inset, window - inset)

## How big a window pixel is against one of `picture`'s own -- what a screen inside it converts its own card sizes through to match this container's.
func window_scale(picture: WallPicture) -> float:
	return picture.window_scale(get_viewport().get_visible_rect().size) if picture else 1.0

## Hosts a `DeckViewer` or `ChoiceViewer` that `screen` opened in `picture`: relays its highlights to `relay`, returns to the lock on close, fits it beside this container.
func host_viewer(viewer: Node, picture: WallPicture, relay: Signal, screen: StringName) -> void:
	viewer.connect(&"info_requested", func(entry: InfoEntry) -> void: entry.relay_to(relay))
	viewer.connect(&"highlight_cleared", _close_hosted_viewer.bind(viewer))
	viewer.tree_exiting.connect(_forget_hosted_viewer.bind(viewer))
	if viewer is DeckViewer: (viewer as DeckViewer).fallback_focus = _exit_button
	var cards : CardsViewer = viewer.call(&"cards")
	cards.sticky_changed.connect(_follow_the_viewers_sticky)
	cards.sidebar_requested.connect(_exit_button.grab_focus)
	cards.highlight_left.connect(highlight_gone)
	var hosted := _HostedViewer.new()
	hosted.viewer = viewer
	hosted.screen = screen
	hosted.suspended_lock = _locked_entry_by_screen.get(screen)
	_locked_entry_by_screen.erase(screen)
	if screen == _active_screen and showing_description():
		hosted.covered = _entry_by_screen.get(screen)
	_hosted_viewers.append(hosted)
	var fit := func() -> void: _fit_viewer(viewer, picture)
	connect_for_screen(viewer, container_rect_changed, fit)
	fit.call()
	_refresh_exit_button()

# ⚠ ONE PER VIEWER, FILED UNDER THE SCREEN THAT OPENED IT: the run deck opens over the pack chooser
# and must hand the chooser's stuck card back, and a viewer left up behind an overlay Back must
# neither take the next screen's keys nor give its lock back to that screen.
class _HostedViewer extends RefCounted:
	var viewer : Node
	var screen : StringName
	## The screen's lock, set aside so this viewer's sticky card can take the one lock; closing gives it back.
	var suspended_lock : InfoEntry = null
	## What the sidebar was reading when this viewer opened, where a highlight that goes puts it back.
	var covered : InfoEntry = null

## Every viewer this container hosts, oldest first; the X, the keys and a lost highlight answer to the newest one on the screen shown.
var _hosted_viewers : Array[_HostedViewer] = []

## The newest viewer up on the screen being shown, or null: one left up on another screen answers nothing here.
func _shown_hosted_viewer() -> _HostedViewer:
	for index : int in range(_hosted_viewers.size() - 1, -1, -1):
		if _hosted_viewers[index].screen == _active_screen: return _hosted_viewers[index]
	return null

# A HIGHLIGHT NOTHING CLICKED LEAVES NOTHING BEHIND -- that is what makes it a highlight.
## Board and viewer alike, the pointer or focus is on nothing this describes: back to the stuck card, else what the viewer covered, else the HUD.
func highlight_gone() -> void:
# A TEARDOWN IS NOT A POINTER MOVE: Godot fires `mouse_exited` on the hovered card as the tree
# comes apart, and this container is already out of it by then -- measured, one SCRIPT ERROR a run.
	if not is_inside_tree(): return
	var hosted := _shown_hosted_viewer()
	if is_locked(): return_to_lock()
	elif hosted and hosted.covered: show_description(hosted.covered)
	else:
		_release_shown_entry()
		_release_remembered_entry(_active_screen, null)
		_swap_to_hud()
		_follow_the_menus_own_content()
	_refresh_exit_button()

# ⚠ A FROZEN SHOW'S BOARD STILL LOSES ITS FOCUS: a press on the map's Travel, or a viewer closing
# there, takes it -- measured -- so only the screen being shown may hand the sidebar back.
## The game board lost its highlight: `highlight_gone()` while the game screen is the one shown, else nothing.
func board_highlight_gone() -> void:
	if _active_screen == GAME_SCREEN: highlight_gone()

# STICKY IS THE LOCK, on every surface: a clicked viewer card pins the sidebar exactly as a clicked
# board card does, and letting it go leaves the highlight free again.
func _follow_the_viewers_sticky(stuck: bool) -> void:
	if stuck: lock_to(_entry_by_screen[_active_screen])
	else: clear_lock()

# A VIEWER CLOSING TAKES ITS CARD OUT OF ITS OWN SCREEN'S SIDEBAR and gives back the lock it set
# aside -- on a screen not shown, as what coming back to it shows. Not through `show_hud()`, a
# dismissal, which the map reads as dropping its pick.
func _close_hosted_viewer(viewer: Node) -> void:
	var hosted := _hosted_viewers[_hosted_viewers.find_custom(_hosts.bind(viewer))]
	_release_locked_entry(hosted.screen)
	if hosted.suspended_lock: _locked_entry_by_screen[hosted.screen] = hosted.suspended_lock
	hosted.suspended_lock = null
	if hosted.screen == _active_screen: highlight_gone()
	else:
		var back : InfoEntry = _locked_entry_by_screen.get(hosted.screen, hosted.covered)
		_release_remembered_entry(hosted.screen, back)
		if back: _entry_by_screen[hosted.screen] = back
	_hosted_viewers.erase(hosted)
	if hosted.covered and hosted.covered != _entry_by_screen.get(hosted.screen):
		_free_detached_visual(hosted.covered)

# A VIEWER FREED WITH ITS SCREEN NEVER CLOSES -- a show torn down takes its open deck viewer with
# it -- so leaving the tree is the last moment its record, and what it covered, can go.
func _forget_hosted_viewer(viewer: Node) -> void:
	var index := _hosted_viewers.find_custom(_hosts.bind(viewer))
	if index < 0: return
	_release_what_the_viewer_covered(_hosted_viewers[index])
	_hosted_viewers.remove_at(index)

static func _hosts(hosted: _HostedViewer, viewer: Node) -> bool:
	return hosted.viewer == viewer

# THE X PROMISES THE DESCRIPTION WILL STAY: a highlight nothing has clicked will not, wherever it
# was published, so it carries no X until a click locks it.
func _refresh_exit_button() -> void:
	_join_focus_while_shown(_exit_button,
			showing_description()
			and (is_locked() or not _description_panel.current_entry.transient))

# A VIEWER IS A SCREEN OCCUPANT LIKE THE BOARD, re-fitted after its screen's own inset. It republishes
# only while a description is UP, redrawing the preview at its own card size: a dismissal is the
# player's act and a window change is not one.
func _fit_viewer(viewer: Node, picture: WallPicture) -> void:
	viewer.call(&"fit_beside", resting_rect_beside(picture), window_scale(picture))
	if showing_description(): viewer.call(&"republish_highlight")

## Sets this control's own rect to `container_rect()` offset by the slide, and tells listeners it moved.
func _apply_container_rect() -> void:
	var rect := container_rect()
	position = rect.position + _slide_offset(rect)
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

# The cap is a rule about SHAPE, not about pixel count: it bites only where the band's own axis
# outruns the project's reference window shape, so a window of that shape keeps the authored inset
# at any size and only an ultrawide -- or an ultratall under the top band -- clamps.
static func _container_px(window: Vector2, top: bool, settings_res: PlayerSettings) -> float:
	var px := settings_res.container_size_fraction * (window.y if top else window.x)
	var reference := PlayArea.reference_window_size()
	var band_axis_outruns_reference := (window.y * reference.x > window.x * reference.y) if top 			else (window.x * reference.y > window.y * reference.x)
	if not band_axis_outruns_reference: return px
	return minf(px, settings_res.container_size_max_px)

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
# A screen that wants nothing shown gets the container OFF THE WINDOW AT ONCE, never tweened: the
# leave already awaited the way out, and wall view arrives after it.
	if not _wants_container(): _jump_slide(0.0)
	visible = _wants_container() and _slide > 0.0
	_game_hud.visible = screen == GAME_SCREEN
	_map_hud.visible = screen == MAP_SCREEN
	_description_panel.show_buttons(screen == MAP_SCREEN)

# THE MENU CARRIES NO HUD, so on that one screen the container's own content decides whether it is
# there at all: the deck picker publishing a description slides it in, dismissing slides it out.
# Every other screen is driven by `Main` landing on it and leaving it.
func _follow_the_menus_own_content() -> void:
	if _active_screen != MENU_SCREEN: return
	slide_to(1.0 if showing_description() else 0.0)

func show_hud() -> void:
	_swap_to_hud()
	clear_lock()
	description_dismissed.emit()
	_follow_the_menus_own_content()

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
	_dismiss_from_the_x()
	exit_accepted.emit()

# THE X IS THE SAME CANCEL AS EVERY OTHER: over a viewer it unsticks and closes together, rather
# than dismissing a description the viewer would republish a moment later.
func _dismiss_from_the_x() -> void:
	var hosted := _shown_hosted_viewer()
	if hosted:
		hosted.viewer.call(&"close_from_sidebar")
		return
	dismiss_description()

# ⚠ A SCREEN CHANGE IS NOT A DISMISSAL: the screen being left keeps its lock, and its board keeps
# the marking on the locked card, so coming back finds what was being read exactly as it was. Every
# other route to the HUD is `show_hud()`, the one place the lock is cleared and the drop announced.
func _swap_to_hud() -> void:
	_hud_stack.visible = true
	_description_panel.visible = false
	_join_focus_while_shown(_exit_button, false)
	_aim_scroll_stick(0.0)

# The locked entry is what a lost highlight comes BACK to, so a hover that displaces it takes its
# visual OUT rather than freeing it. A publication arriving mid-cascade is dropped instead, and it
# owns the live preview the board built for it, which nothing else would collect.
func show_description(entry: InfoEntry) -> void:
	if _screen_is_processing():
		_free_detached_visual(entry)
		return
# ⚠ THE PANEL FREES WHATEVER IT IS HOLDING when another entry replaces it, so anything the
# container still means to come back to is taken out first -- a lock waiting under a viewer is no
# less kept than a live one.
	var shown : InfoEntry = _description_panel.current_entry
	if shown and shown != entry and (shown == _locked_entry_by_screen.get(_active_screen)
			or _held_by_a_viewer(shown)):
		_description_panel.detach_entry()
	_release_remembered_entry(_active_screen, entry)
	_entry_by_screen[_active_screen] = entry
	_hud_stack.visible = false
	_description_panel.show_entry(entry, _content_size())
	_refresh_exit_button()
	_follow_the_menus_own_content()

## Hangs a screen's own row of buttons above the description body. The screen builds the row, decides when it shows and owns the node.
func mount_description_buttons(row: Control) -> void:
	_description_panel.mount_buttons(row)

## Whether the description is what shows -- `GameView` asks before spending a cancel on dismissing it.
func showing_description() -> bool:
	return _description_panel.visible

# ⚠ A PANEL CONTROL JOINS KEYBOARD/PAD NAVIGATION FOR EXACTLY AS LONG AS IT IS UP: a pad player
# must always be able to dismiss what is shown, since a viewer's own opening highlight can hide the
# button that opened it. Back on the HUD, nothing here is in anyone's focus chain.
func _join_focus_while_shown(button: Button, shown: bool) -> void:
	button.visible = shown
	button.focus_mode = Control.FOCUS_ALL if shown else Control.FOCUS_NONE

# A lock survives leaving and returning, exactly as the remembered entry does, and a lost highlight
# comes back to the entry held here.
## The entry each screen's description is LOCKED to, and the only record that the screen is locked at all.
var _locked_entry_by_screen : Dictionary[StringName, InfoEntry] = {}

## Pins the description to `entry`: it stays the sidebar's subject until a dismissal takes the container back to the HUD.
func lock_to(entry: InfoEntry) -> void:
	_release_locked_entry(_active_screen)
	_locked_entry_by_screen[_active_screen] = entry
	show_description(entry)

func clear_lock() -> void:
	_release_locked_entry(_active_screen)
	_refresh_exit_button()

func is_locked() -> bool:
	return _locked_entry_by_screen.has(_active_screen)

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
	if remembered and remembered != keeping and not _held_by_a_viewer(remembered) \
			and remembered != _locked_entry_by_screen.get(screen):
		_free_detached_visual(remembered)
	_entry_by_screen.erase(screen)

# ⚠ A SCREEN'S CONTAINER STATE BELONGS TO THE CONTENT THAT PUBLISHED IT, NOT TO THE SCREEN ID:
# `Main` reuses one id for every show, so a show that is torn down has to hand back its memory,
# its lock, its cascade flag and its hand, or the next one inherits them.
func release_screen(screen: StringName) -> void:
	if screen == _active_screen:
		_release_shown_entry()
		_swap_to_hud()
	for hosted : _HostedViewer in _hosted_viewers:
		if hosted.screen == screen: _release_what_the_viewer_covered(hosted)
	_release_remembered_entry(screen, null)
	_release_locked_entry(screen)
	if screen != GAME_SCREEN: return
	_game_processing = false
	_game_card_in_hand = false

# ⚠ WHAT A VIEWER COVERS IS IN NEITHER DICTIONARY: `host_viewer` takes the screen's lock out of
# `_locked_entry_by_screen` to hold it there, so every other release walks straight past it and its
# preview is the one thing left alive. This is the only owner that can free the pair.
func _release_what_the_viewer_covered(hosted: _HostedViewer) -> void:
	for entry : InfoEntry in [hosted.suspended_lock, hosted.covered] as Array[InfoEntry]:
		if entry: _free_detached_visual(entry)
	hosted.suspended_lock = null
	hosted.covered = null

func _held_by_a_viewer(entry: InfoEntry) -> bool:
	return _hosted_viewers.any(func(hosted: _HostedViewer) -> bool:
		return entry == hosted.suspended_lock or entry == hosted.covered)

# ⚠ FREED HERE AND NOT LEFT TO THE DICTIONARIES: on a whole-tree teardown this container's own
# `_exit_tree()` has already run and cleared them, so a visual taken out of the panel afterwards
# would be in no dictionary and no tree -- measured, 24 orphaned previews across the suite.
func _release_shown_entry() -> void:
	var shown : InfoEntry = _description_panel.current_entry
	_description_panel.detach_entry()
	for hosted : _HostedViewer in _hosted_viewers:
		if hosted.covered == shown: hosted.covered = null
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

## Whether the game screen's player holds a card -- relayed by `GameView`, like `_game_processing`.
var _game_card_in_hand : bool = false

## Relayed by `GameView` from `PlayArea.hand_changed`: while a card is in hand, Up and Down aim it on the board.
func set_card_in_hand(held: bool) -> void:
	_game_card_in_hand = held

## Whether the screen now showing is the one mid-cascade -- any other screen's container behaves as it always does.
func _screen_is_processing() -> bool:
	return _game_processing and _active_screen == GAME_SCREEN

# THE SIDEBAR READS ITS KEYS IN `_input`, BEFORE THE GUI PASS: the viewport's focus-neighbour
# search consumes any arrow that finds a neighbour, so an arrow read any later never arrives while
# a board cell holds the focus. Page keys scroll whenever the description shows, arrows once locked.

# ⚠ A CARD IN HAND IS AIMED WITH UP AND DOWN, so neither scrolls the stuck description nor climbs to
# its X then; Left into the sidebar still reaches the X.
func _input(event: InputEvent) -> void:
	if _enters_the_hosted_viewer(event):
		get_viewport().set_input_as_handled()
		return
	if _the_arrows_belong_to_the_hosted_viewer(event): return
	if _leaves_the_sidebar_for_the_picture(event):
		get_viewport().gui_get_focus_owner().release_focus()
		exit_accepted.emit()
		get_viewport().set_input_as_handled()
		return
	if not showing_description(): return
	if (_game_card_in_hand and _active_screen == GAME_SCREEN
			and (event.is_action(&"ui_up") or event.is_action(&"ui_down"))): return
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

# ⚠ THE VIEWER OPENS WITH NOTHING FOCUSED so the HUD stays reachable, and it is in another
# viewport, where the overlay's own focus search would never look: the first navigation press is
# handed to it here, ahead of the GUI pass that would walk the HUD buttons instead.
func _enters_the_hosted_viewer(event: InputEvent) -> bool:
	var hosted := _shown_hosted_viewer()
	if hosted == null: return false
	for action : StringName in CardsViewer.NAVIGATION:
		if event.is_action_pressed(action, true):
			return (hosted.viewer.call(&"cards") as CardsViewer).focus_first()
	return false

# A DESCRIPTION NOTHING STUCK IS ALREADY ON ITS WAY OUT, the focus having left the card it
# describes, so the HUD is brought back first and its own controls are what the press lands on.
## The sidebar takes the focus: the X while a stuck description holds the panel, else the HUD's first control.
func focus_sidebar() -> void:
	if showing_description() and not is_locked(): highlight_gone()
	var target := _exit_button if showing_description() else _hud_stack.find_next_valid_focus()
# ⚠ THE ONE PRODUCER OF AN OFF-SCREEN TARGET is the board asking while a viewer is hosted, which
# hides the HUD stack the search just walked. The board should not be asking at all from under a
# viewer; until it stops, the press is dropped rather than parked on a control nobody can see.
	if not target.is_visible_in_tree(): return
	target.grab_focus()

# ⚠ THE PICTURE IS IN ANOTHER VIEWPORT, so the engine's neighbour search can never step back into
# it and the last control in the row would strand a pad player. Which control is last is asked of
# that same search rather than written down here, so the two can never disagree.

# ⚠ A HOSTED VIEWER IS THE FOCUS, so the board behind it is no door; an EMPTY one lists nothing
# for `_enters_the_hosted_viewer` to take the press into, and it would reach the board here.
func _leaves_the_sidebar_for_the_picture(event: InputEvent) -> bool:
	if _shown_hosted_viewer() != null: return false
	if not event.is_action_pressed(&"ui_right", true): return false
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null or not is_ancestor_of(owner): return false
	return owner.find_valid_focus_neighbor(SIDE_RIGHT) == null

# ⚠ A FOCUSED VIEWER OWNS THE ARROWS. Read before the GUI pass, the page scroll and the up-to-the-X
# would answer a grid key the viewer's own neighbour search can use, and a stuck card could never
# change rows. Only an arrow that finds no neighbour comes back, as `sidebar_requested`.
func _the_arrows_belong_to_the_hosted_viewer(event: InputEvent) -> bool:
	var hosted := _shown_hosted_viewer()
	if hosted == null: return false
	if not (hosted.viewer.call(&"cards") as CardsViewer).focus_is_inside(): return false
	for action : StringName in CardsViewer.NAVIGATION:
		if event.is_action_pressed(action, true): return true
	return false

# ⚠ A SCREEN'S CONTROLS AND THE EXIT X SIT IN DIFFERENT VIEWPORTS, and Godot's focus search never
# crosses one, so the sidebar carries up, off the top of a description, onto the X itself. The
# board's must be locked first; the map never locks, so any it shows counts while no viewer is up.
func _navigates_to_exit(event: InputEvent) -> bool:
	var map_without_a_viewer := _active_screen == MAP_SCREEN and _shown_hosted_viewer() == null
	return (is_locked() or map_without_a_viewer) \
			and event.is_action_pressed(&"ui_up", true) and _description_panel.at_top()

## The scroll stick's last reported deflection, integrated per frame while it is off centre.
var _scroll_stick : float = 0.0

# A STICK REPORTS ONLY WHEN IT MOVES, so its deflection is held and integrated per frame rather
# than scrolled once. Inside the action's own deadzone it is at rest, which stops the scroll.
func _aim_scroll_stick(axis_value: float) -> void:
	var deadzone := InputMap.action_get_deadzone(&"sidebar_scroll")
	_scroll_stick = axis_value if absf(axis_value) >= deadzone else 0.0
	if not is_zero_approx(_scroll_stick): set_process(true)

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
	slide_settled.emit()
	for screen : StringName in _entry_by_screen:
		_free_detached_visual(_entry_by_screen[screen])
	for screen : StringName in _locked_entry_by_screen:
		_free_detached_visual(_locked_entry_by_screen[screen])
	_entry_by_screen.clear()
	_locked_entry_by_screen.clear()
	for hosted : _HostedViewer in _hosted_viewers:
		_release_what_the_viewer_covered(hosted)
	_hosted_viewers.clear()

# One entry can be both a screen's remembered one and its locked one, so a visual already on its
# way out is left alone rather than queued a second time.
func _free_detached_visual(entry: InfoEntry) -> void:
	var visual : Node = entry.visual
	if visual and visual.get_parent() == null and not visual.is_queued_for_deletion():
		visual.queue_free()
