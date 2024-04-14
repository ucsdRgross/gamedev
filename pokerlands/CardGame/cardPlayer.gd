extends Node2D
class_name CardPlayer

@onready var mouse_pin: PinJoint2D = $MousePin

@onready var card_spaces: Array[CardSpace] = [$CardSpace1, $CardSpace2, $CardSpace3, $CardSpace4, $CardSpace5]
@onready var cards: Node2D = $Cards
@onready var card_zone: Area2D = $CardZone

var held_card : Card = null

func _physics_process(_delta: float) -> void:
	mouse_pin.global_position = get_global_mouse_position()
	
func _on_cards_child_entered_tree(card : Card) -> void:
	card.clicked.connect(_on_card_clicked)
		
func _on_card_clicked(card : Card) -> void:
	if !held_card:
		card.pickup()
		held_card = card
		mouse_pin.node_b = mouse_pin.get_path_to(held_card)
		cards.move_child(card,-1)
		
func drop_held_card() -> void:
	held_card.drop()
	held_card = null
	mouse_pin.node_b = NodePath()
	print('release')
	card_zone.position_cards()

func _input(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == 1 and not mouse_event.pressed:
			if held_card:
				drop_held_card()

func _on_card_deck_draw_card(card_info: PackedScene, deck_position: Vector2, event: InputEvent) -> void:
	var card : Card = card_info.instantiate()
	cards.add_child(card)
	card.global_position = deck_position
	
	var colors = [Color(1.0, 0.0, 0.0, 1.0),
				Color(0.0, 1.0, 0.0, 1.0),
				Color(0.0, 0.0, 1.0, 1.0)]
	randomize()
	card.modulate = colors[randi() % colors.size()]
	
	card.process_event(event)

func _on_card_discard_deck_discard_card(card: Card) -> void:
	if held_card == card:
		drop_held_card()

func reset() -> void:
	for space:CardSpace in card_spaces:
		space.active = false
		if space.held_card:
			space.held_card.queue_free()
			space.held_card = null
