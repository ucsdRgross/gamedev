extends Node2D
class_name CardPlayer

signal card_betted

const CARD = preload("res://CardGame/Cards/card.tscn")

@export var deck_info : Deck
var deck : Array[CardInfo]
var health : int = 100
var held_card : Card = null

@onready var mouse_pin: PinJoint2D = $MousePin
@onready var cards: Node2D = $Cards
@onready var card_discard_deck: Area2D = $CardDiscardDeck
@onready var hand_zone: CardZone = $HandZone
@onready var bet_zone: CardZone = $BetZone
@onready var check_zone: CardZone = $CheckZone
@onready var card_deck: Area2D = $CardDeck

func _ready() -> void:
	for zone : CardZone in [hand_zone, bet_zone, check_zone]:
		zone.cards_z_index_changed.connect(sort_cards_tree)
	deck = deck_info.cards_info
	deck.shuffle()

func _physics_process(_delta: float) -> void:
	mouse_pin.global_position = get_global_mouse_position()
	if held_card and held_card.parent_zone:
		held_card.parent_zone.arrange_cards()
	
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
	if held_card.parent_zone:
		if held_card.parent_zone == bet_zone:
			card_betted.emit()
	else:
		hand_zone.add_card(held_card, hand_zone.get_closest_empty_space(held_card.global_position))
	held_card.parent_zone.position_cards()
	held_card = null
	mouse_pin.node_b = NodePath()
	#print('release')

func _input(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == 1 and not mouse_event.pressed:
			if held_card:
				drop_held_card()

func _on_card_deck_card_drawn() -> void:
	if hand_zone.can_add_card():
		var card : Card = CARD.instantiate()
		card.set_card_info(deck.pop_back())
		cards.add_child(card)
		card.global_position = card_deck.global_position
		hand_zone.add_card(card, hand_zone.get_closest_empty_space(card.global_position))

func _on_card_discard_deck_discard_card(card: Card) -> void:
	if held_card == card:
		held_card.drop()
		held_card = null
		mouse_pin.node_b = NodePath()

func bet_round() -> void:
	bet_zone.max_cards += 1
	
func check_round() -> void:
	check_zone.max_cards = 2

func reset() -> void:
	for card:Node2D in bet_zone.cards:
		if card is Card:
			card_discard_deck.delete_card(card)
	bet_zone.max_cards = 0
	
	for card:Node2D in check_zone.cards:
		if card is Card:
			card_discard_deck.delete_card(card)
	check_zone.max_cards = 0
	
func sort_cards_z(a:CanvasItem, b:CanvasItem) -> bool:
	if a.z_index == b.z_index:
		if a.get_index() < b.get_index():
			return true
	elif a.z_index < b.z_index:
		return true
	return false
	
func sort_cards_tree() -> void:
	var sorted_nodes : Array[Node] = cards.get_children()
	sorted_nodes.sort_custom(sort_cards_z)
	for i:int in range(sorted_nodes.size()):
		cards.move_child(sorted_nodes[i],i)
	
