class_name ControlCard
extends Control

const CONTROL_CARD := preload("uid://dbmfhito00wc")

var child : CardVisual

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	SettingsManager.settings_changed.connect(set_min_size)
	set_min_size()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:	
	pass

func set_min_size() -> void:
	if child:
		custom_minimum_size = child.card_size

static func add_child_control_card(parent:Node,connected_data:CardData, context:CardVisual.DisplayContext) -> ControlCard:
	var new_control : ControlCard = CONTROL_CARD.instantiate()
	var card : CardVisual = CardVisual.add_child_card_visual(
		new_control, connected_data, context, new_control)
	new_control.child = card
	new_control.set_min_size()
	parent.add_child(new_control)
	return new_control
