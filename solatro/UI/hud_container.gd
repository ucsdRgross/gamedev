class_name HudContainer
extends PanelContainer
## The one container on the wall overlay: shows the HUD or the description, never both.

@onready var _hud_stack : Control = %HudStack
@onready var _description_panel : DescriptionPanel = %DescriptionPanel
@onready var _game_hud_margin : MarginContainer = %HudStack/GameHudMargin

@onready var submit_button : Button = %Submit
@onready var undo_button : Button = %Undo
@onready var deck_ui : Control = %Deck
@onready var discard_ui : Control = %Discard
@onready var rules_ui : Control = %Rules
@onready var goal_label : Label = %Goal/Label
@onready var total_label : Label = %Total/Label
@onready var combo_label : Label = %Combo

func _ready() -> void:
	(get_theme_stylebox("panel") as StyleBoxFlat).bg_color = PaletteDB.color(PaletteDB.ROLES.hud_background)
	show_hud()
	var overlay := get_parent() as WallOverlay
	if overlay: overlay.ready.connect(_position_below_overlay_buttons, CONNECT_ONE_SHOT)

# Waits for the OVERLAY's own `ready` signal, which fires after `WallOverlay._ready()` has grown
# its button row -- `HudContainer` is that row's CHILD, so its own `_ready()` runs first otherwise.
# Only mounted under a `WallOverlay` in `wall.tscn`; a standalone instance (as the tests build) never connects.
func _position_below_overlay_buttons() -> void:
	var overlay := get_parent() as WallOverlay
	_game_hud_margin.add_theme_constant_override("margin_top", ceili(overlay.button_band_bottom()))

func show_hud() -> void:
	_hud_stack.visible = true
	_description_panel.visible = false

func show_description(entry: InfoEntry) -> void:
	_hud_stack.visible = false
	_description_panel.visible = true
