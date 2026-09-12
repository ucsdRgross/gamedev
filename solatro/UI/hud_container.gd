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

## Connections a screen made on this container, dropped by `disconnect_for_screen()` when that screen tears down.
var _screen_connections : Array[Array] = []

## Connects `sig` to `callable` and remembers the pair for `disconnect_for_screen()`.
func connect_for_screen(sig: Signal, callable: Callable) -> void:
	sig.connect(callable)
	_screen_connections.append([sig, callable])

## Drops every connection a screen made through `connect_for_screen()` -- called from that screen's own `_exit_tree()`.
func disconnect_for_screen() -> void:
	for pair : Array in _screen_connections:
		var sig : Signal = pair[0] as Signal
		var callable : Callable = pair[1] as Callable
		if sig.is_connected(callable):
			sig.disconnect(callable)
	_screen_connections.clear()

func _ready() -> void:
	(get_theme_stylebox("panel") as StyleBoxFlat).bg_color = PaletteDB.color(PaletteDB.ROLES.hud_background)
	_exit_button.tooltip_text = TRANSLATION.find('SIDEBAR_CLOSE')
	_exit_button.pressed.connect(show_hud)
	_place_exit_button()
	show_hud()
	var overlay := get_parent() as WallOverlay
	if overlay:
		overlay.ready.connect(_position_below_overlay_buttons, CONNECT_ONE_SHOT)
		get_viewport().size_changed.connect(_position_below_overlay_buttons)
	get_viewport().size_changed.connect(_apply_container_rect)
	_apply_container_rect()

# Waits for the OVERLAY's own `ready` signal, which fires after `WallOverlay._ready()` has grown
# its button row -- `HudContainer` is that row's CHILD, so its own `_ready()` runs first otherwise.
# Only mounted under a `WallOverlay` in `wall.tscn`; a standalone instance (as the tests build) never connects.
func _position_below_overlay_buttons() -> void:
	var overlay := get_parent() as WallOverlay
	_band_top = overlay.button_band_bottom()
	_game_hud_margin.add_theme_constant_override("margin_top", ceili(_band_top))
	_description_margin.add_theme_constant_override("margin_top", ceili(_band_top))
	_place_exit_button()

# The exit X means GO BACK TO THE HUD, so it is the touch affordance for that: grown to the same
# minimum every overlay control is grown to, in the container's top-right, and parked BELOW the
# overlay's own button band so it never hides under one.
func _place_exit_button() -> void:
	var target := WallInput.touch_target_px(DisplayServer.screen_get_dpi(), PlayArea.settings())
	_exit_button.offset_left = -target
	_exit_button.offset_top = _band_top
	_exit_button.offset_bottom = _band_top + target

## The container's own rect at the current window size -- what `PlayArea.board_inset_left`/`board_inset_top` are derived from.
func container_rect() -> Rect2:
	return rect_for_window(get_viewport().get_visible_rect().size, PlayArea.settings())

## Sets this control's own rect to `container_rect()` and tells listeners it moved.
func _apply_container_rect() -> void:
	var rect := container_rect()
	position = rect.position
	size = rect.size
	_fit_piles_to_width(rect.size.x)
	if _description_panel.visible: _description_panel.resize_to(_description_size())
	container_rect_changed.emit()

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
	return (window.x - _container_px(window.x, settings_res)) / window.y < 1.0

# Pure arithmetic seam for `container_rect()`, so a headless test can drive the production
# formula without booting a window. Flush against the INNER edge of its band when clamped,
# leaving the empty space outboard of it.
static func rect_for_window(window: Vector2, settings_res: PlayerSettings) -> Rect2:
	if container_is_top(window, settings_res):
		var px := _container_px(window.y, settings_res)
		var inner_edge := settings_res.container_size_fraction * window.y
		return Rect2(0.0, inner_edge - px, window.x, px)
	var px := _container_px(window.x, settings_res)
	var inner_edge := settings_res.container_size_fraction * window.x
	return Rect2(inner_edge - px, 0.0, px, window.y)

## The fraction of `reference`, capped at the pixel ceiling.
static func _container_px(reference: float, settings_res: PlayerSettings) -> float:
	return minf(settings_res.container_size_fraction * reference, settings_res.container_size_max_px)

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
		if remembered == null or _screen_is_processing(): show_hud()
		else: show_description(remembered)
	visible = screen != &""
	if not visible: return
	_game_hud.visible = screen == &"game"
	_map_hud.visible = screen == &"map"

func show_hud() -> void:
	_hud_stack.visible = true
	_description_panel.visible = false
	_exit_button.visible = false
	clear_lock()
	description_dismissed.emit()

func show_description(entry: InfoEntry) -> void:
	if _drops_publication(entry): return
	_detach_locked_entry(entry)
	_entry_by_screen[_active_screen] = entry
	_hud_stack.visible = false
	_exit_button.visible = true
	_description_panel.show_entry(entry, _description_size())

## Whether the description is what shows -- `GameView` asks before spending a cancel on dismissing it.
func showing_description() -> bool:
	return _description_panel.visible

## The card each screen's description is LOCKED to -- a lock survives leaving and returning, exactly as the remembered entry does.
var _lock_by_screen : Dictionary[StringName, CardData] = {}

## The entry that lock is showing, so losing the highlight can come back to the locked card itself.
var _locked_entry_by_screen : Dictionary[StringName, InfoEntry] = {}

## Pins the description to `target`: it stays the sidebar's subject until a dismissal takes the container back to the HUD.
func lock_to(entry: InfoEntry, target: CardData) -> void:
	if _drops_publication(entry): return
	_release_locked_entry()
	_lock_by_screen[_active_screen] = target
	_locked_entry_by_screen[_active_screen] = entry
	show_description(entry)

func clear_lock() -> void:
	_lock_by_screen.erase(_active_screen)
	_release_locked_entry()

func is_locked() -> bool:
	return _lock_by_screen.has(_active_screen)

## Nothing is highlighted any more: a locked description returns to its own card, an unlocked one keeps the entry it has.
func return_to_lock() -> void:
	if not is_locked(): return
	var locked : InfoEntry = _locked_entry_by_screen[_active_screen]
	if _description_panel.current_entry == locked: return
	show_description(locked)

# The locked entry is what a lost highlight comes BACK to, so a hover that displaces it takes its
# visual OUT rather than freeing it -- the same detach the per-screen memory is returned through.
func _detach_locked_entry(replacement: InfoEntry) -> void:
	var locked : InfoEntry = _locked_entry_by_screen.get(_active_screen)
	if locked and locked != replacement and _description_panel.current_entry == locked:
		_description_panel.detach_entry()

# A LOCK LEAVING IS THE LAST MOMENT ANYTHING CAN FREE ITS VISUAL: a displaced entry is out of the
# panel and, once the next lock replaces it, in no dictionary either.
func _release_locked_entry() -> void:
	var locked : InfoEntry = _locked_entry_by_screen.get(_active_screen)
	if locked: _free_detached_visual(locked)
	_locked_entry_by_screen.erase(_active_screen)

## The one screen whose cascade the rule below covers: the map has none worth watching, so its container never swaps on one.
const PROCESSING_SCREEN : StringName = &"game"

## Which screen is mid-cascade, or `&""` while none is.
var _processing_screen : StringName = &""

## Relayed by `GameView` from `Game.processing`: true reverts to the HUD and drops the lock for good, and once it ends the HUD holds until the next publication.
func set_processing(busy: bool) -> void:
	_processing_screen = PROCESSING_SCREEN if busy else &""
	if _screen_is_processing(): show_hud()

## Whether the screen now showing is the one mid-cascade -- any other screen's container behaves as it always does.
func _screen_is_processing() -> bool:
	return _processing_screen != &"" and _processing_screen == _active_screen

# The HUD is what a cascade is watched in, its own numbers being what animates, so a publication
# arriving mid-cascade is dropped rather than shown. A dropped entry still owns the live preview
# the board built for it, which nothing else will collect.
func _drops_publication(entry: InfoEntry) -> bool:
	if not _screen_is_processing(): return false
	_free_detached_visual(entry)
	return true

## The room the description has: the container minus the overlay's button band, which both contents start below.
func _description_size() -> Vector2:
	return container_rect().size - Vector2(0.0, _band_top)

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
