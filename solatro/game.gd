extends Node2D

const CARD = preload("res://card.tscn")

var held_card : Card = null
var held_card_offset : Vector2

func _ready() -> void:
	randomize()

func _process(delta: float) -> void:
	if held_card:
		held_card.global_position = get_global_mouse_position() + held_card_offset

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			#print("clicked")
			if held_card:
				drop_held_card()

func _on_child_entered_tree(node: Node) -> void:
	if node is Card:
		(node as Card).clicked.connect(_on_card_clicked)

func _on_card_clicked(card : Card) -> void:
	if held_card:
		card.add_card(held_card)
		drop_held_card()
	elif not held_card:
		if card.is_zone:
			pass
		else:
			card.pickup()
			held_card = card
			held_card_offset = held_card.global_position - get_global_mouse_position()
		
func drop_held_card() -> void:
	held_card.drop()
	held_card = null

func _on_button_pressed() -> void:
	for zone : Card in [$Zone, $Zone2, $Zone3, $Zone4]:
		var card : Card = CARD.instantiate()
		card.suit = randi() % 4
		card.rank = randi() % 13
		add_child(card)
		zone.add_card(card)
