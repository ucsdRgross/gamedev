@tool
class_name TriangleMap
extends Control

signal card_clicked(card:Card)
signal card_hovered(card:Card)
signal deck_clicked(card:Card)

const CARD = preload("res://Cards/card.tscn")

@export_range(2, 10) var rows : int = 3:
	set(value):
		rows = max(value, 2)
		if not is_node_ready():
			await ready
		grid_container.columns = (rows - 1) * 2 + 1
		var squares := grid_container.get_child_count()
		var grids : int = rows * grid_container.columns
		if grids > squares:
			for i:int in grids - squares:
				var control := Control.new()
				control.custom_minimum_size = card_control.size
				grid_container.add_child(control)
				control.owner = self
		else:
			for i:int in squares - grids:
				grid_container.get_child(-1).free()
		
		for card : Node2D in child_cards.get_children():
			if is_instance_valid(card):
				card.free()
		cards.clear()
		
		for i in rows ** 2:
			var card : Card = new_card()
			cards.append(card)
			child_cards.add_child(card)
			card.owner = self
		
		await get_tree().process_frame
		var i := 0
		for y in rows:
			for x in grid_container.columns - y * 2:
				var control : Control = grid_container.get_child(xyi(x + y, y))
				cards[i].global_position = control.global_position + control.size / 2
				cards[i].move_to(control.global_position + control.size / 2)
				i += 1
		set_options()

@export var cards : Array[Card]

@onready var grid_container: GridContainer = %GridContainer
@onready var card_control: Control = %CardControl
@onready var child_cards: Control = $ChildCards
@onready var deck: Card = $Deck

func _ready() -> void:
	deck.clicked.connect(func(c:Card)->void:deck_clicked.emit(c))

func set_options() -> void:
	#for card : Card in [cards[-2], cards[-3], cards[-4]]:
	cards[-2].clicked.connect(new_triangle.bind(1))
	cards[-3].clicked.connect(new_triangle.bind(0))
	cards[-4].clicked.connect(new_triangle.bind(-1))

func new_triangle(clicked_card:Card, offset:int) -> void:
	card_clicked.emit(clicked_card)
	var new_cards : Array[Card]
	for i in grid_container.columns:
		var card : Card = new_card()
		new_cards.append(card)
		child_cards.add_child(card)
		var control : Control = grid_container.get_child(i)
		card.global_position = control.global_position + control.size / 2
	for y in rows - 1:
		for x in grid_container.columns - (y+1) * 2:
			var i := xyi(x+y+offset+1, y) - y ** 2
			new_cards.append(cards[i])
	for card in cards:
		if card not in new_cards:
			remove_card(card)
	cards = new_cards
	var i := 0
	for y in rows:
		for x in grid_container.columns - y * 2:
			var control : Control = grid_container.get_child(xyi(x + y, y))
			cards[i].move_to(control.global_position + control.size / 2)
			i += 1
	set_options()

func new_card() -> Card:
	var card : Card = CARD.instantiate()
	card.add_data(CardData.new().with_rank(randi() % 13 + 1).with_suit(randi() % 4 + 1))
	card.flipped = false
	card.can_rot_anim = false
	
	var tween := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)
	card.modulate.a = 0
	tween.tween_property(card, "modulate:a", 1, 0.5)
	card.hover_entered.connect(card_hovered.emit)
	return card

func remove_card(c: Card) -> void:
	c.z_index = -1
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween.tween_property(c, "modulate:a", 0, 0.5)
	tween.parallel().tween_property(c, "scale", Vector2(0.1,0.1), 0.5)
	tween.tween_callback(c.queue_free)
	
func ixy(i:int) -> Vector2i:
	var x := i / grid_container.columns
	var y := i / rows
	return Vector2i(x, y)
	
func xyi(x: int, y :int) -> int:
	return x + y * grid_container.columns
