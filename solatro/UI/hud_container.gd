class_name HudContainer
extends PanelContainer
## The one container on the wall overlay: shows the HUD or the description, never both.

@onready var _hud_stack : Control = %HudStack
@onready var _description_panel : DescriptionPanel = %DescriptionPanel

func _ready() -> void:
	(get_theme_stylebox("panel") as StyleBoxFlat).bg_color = PaletteDB.color(PaletteDB.ROLES.hud_background)
	show_hud()

func show_hud() -> void:
	_hud_stack.visible = true
	_description_panel.visible = false

func show_description(entry: InfoEntry) -> void:
	_hud_stack.visible = false
	_description_panel.visible = true
