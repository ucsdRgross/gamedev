class_name HudContainer
extends PanelContainer
## The one container on the wall overlay: shows the HUD or the description, never both.

# The one instance every screen shares, found through this group rather than a hand-carried ref.
# `wall.tscn` authors membership on its OWN instance declaratively (scene-file `groups=`) -- a
# `GameView`'s private fallback instance must stay OUT of it, or a concurrent `GameView` steals it.
const GROUP := &"hud_container"

@onready var _hud_stack : Control = %HudStack
@onready var _description_panel : DescriptionPanel = %DescriptionPanel

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

func show_hud() -> void:
	_hud_stack.visible = true
	_description_panel.visible = false

func show_description(entry: InfoEntry) -> void:
	_hud_stack.visible = false
	_description_panel.visible = true
