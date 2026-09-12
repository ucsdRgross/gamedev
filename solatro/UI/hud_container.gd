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

## The container's own rect at the current window size -- what `PlayArea.board_inset_left`/`board_inset_top` are derived from.
func container_rect() -> Rect2:
	return rect_for_window(get_viewport().get_visible_rect().size, PlayArea.settings())

## Sets this control's own rect to `container_rect()` and tells listeners it moved.
func _apply_container_rect() -> void:
	var rect := container_rect()
	position = rect.position
	size = rect.size
	_fit_piles_to_width(rect.size.x)
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

# Which screen's HUD content shows inside the stack, keyed by `Main`'s own focus id (`&"game"`,
# `&"map"`, `&"start_menu"`, or `&""` for wall view). The container itself hides entirely at wall
# view; the menu shows it with neither child visible.
func set_active_screen(screen: StringName) -> void:
	if screen != _active_screen:
		_stash_description()
		_active_screen = screen
		_restore_description()
	visible = screen != &""
	if not visible: return
	_game_hud.visible = screen == &"game"
	_map_hud.visible = screen == &"map"

# Leaving a screen keeps that screen's own description: the visual is DETACHED rather than freed,
# so the entry is still whole when the player comes back to it.
func _stash_description() -> void:
	_description_panel.detach_entry()
	show_hud()

# Arriving at a screen re-shows what it was reading, immediately and with no animation -- or the
# HUD, when that screen has read nothing yet.
func _restore_description() -> void:
	var remembered : InfoEntry = _entry_by_screen.get(_active_screen)
	if remembered == null:
		show_hud()
		return
	show_description(remembered)

func show_hud() -> void:
	_hud_stack.visible = true
	_description_panel.visible = false

func show_description(entry: InfoEntry) -> void:
	_entry_by_screen[_active_screen] = entry
	_hud_stack.visible = false
	_description_panel.show_entry(entry, container_rect().size - Vector2(0.0, _band_top))

# A stashed visual is a NODE outside the tree that nothing else will collect. The MOUNTED one is
# the panel's own child and goes with the tree, so only the detached ones are freed here.
func _exit_tree() -> void:
	for screen : StringName in _entry_by_screen:
		var visual : Node = _entry_by_screen[screen].visual
		if visual and is_instance_valid(visual) and visual.get_parent() == null:
			visual.queue_free()
	_entry_by_screen.clear()
