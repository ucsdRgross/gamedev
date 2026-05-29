class_name ControlCard
extends Control

const CONTROL_CARD := preload("uid://dbmfhito00wc")

var child : CardVisual

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	pass
	
func set_sizes(card_scale:float) -> void:
	if child:
		child.position = CardVisual.CARD_SIZE * card_scale/2.0
		child.scale = Vector2.ONE * card_scale
	self.custom_minimum_size = CardVisual.CARD_SIZE * card_scale
	
static func add_child_control_card(parent:Node,connected_data:CardData) -> ControlCard:
	var new_control : ControlCard = CONTROL_CARD.instantiate()
	var card : CardVisual = CardVisual.add_child_card_visual(new_control, connected_data, true)
	new_control.child = card
	parent.add_child(new_control)
	return new_control
