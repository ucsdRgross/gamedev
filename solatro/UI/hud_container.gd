class_name HudContainer
extends PanelContainer
## The one container on the wall overlay: shows the HUD or the description, never both.

@onready var _hud_stack : Control = %HudStack
@onready var _description_panel : DescriptionPanel = %DescriptionPanel
@onready var _game_hud_margin : MarginContainer = %HudStack/GameHudMargin
@onready var _piles : HBoxContainer = %GameHud/Piles

@onready var submit_button : Button = %Submit
@onready var undo_button : Button = %Undo
@onready var deck_ui : Control = %Deck
@onready var discard_ui : Control = %Discard
@onready var rules_ui : Control = %Rules
@onready var goal_label : Label = %Goal/Label
@onready var total_label : Label = %Total/Label
@onready var combo_label : Label = %Combo

## The container's own rect changed (start or resize); `GameView` re-publishes the board insets off it.
signal container_rect_changed

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
	_game_hud_margin.add_theme_constant_override("margin_top", ceili(overlay.button_band_bottom()))

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

func show_hud() -> void:
	_hud_stack.visible = true
	_description_panel.visible = false

func show_description(entry: InfoEntry) -> void:
	_hud_stack.visible = false
	_description_panel.visible = true
