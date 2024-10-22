extends Control

const CARD = preload("res://Cards/card.tscn")
const CARD_CONTROL = preload("res://card_control.tscn")

var deck: Array[CardData]

@onready var flow_container: FlowContainer = %FlowContainer

func _on_add_card_pressed() -> void:
	var card : Card = CARD.instantiate()
	card.data = CardData.new()\
					.with_suit(randi() % 4 + 1)\
					.with_rank(randi() % 13 + 1)
	card.can_move_anim = false
	#card.clicked.connect(_on_card_clicked)
	#card.hover_entered.connect(_on_card_hover_entered)
	#var zone : Card = c.get_child(0)
	var control : Control = CARD_CONTROL.instantiate()
	control.add_child(card)
	flow_container.add_child(control)
	#zone.front.self_modulate.a = 0
	#c.add_child(card)
	#zone.add_card(card)
	#var row := i / cols
	#var col := i % cols
	#card_to_index[card] = Vector2i(row,col)
	#index_to_card[Vector2i(row,col)] = card
