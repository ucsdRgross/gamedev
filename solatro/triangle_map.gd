@tool
extends Control

const CARD = preload("res://Cards/card.tscn")

@export_range(1, 10) var rows : int = 3:
	set(value):
		rows = value
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
				
		for card in cards:
			card.free()
		cards.clear()
		
		for i in rows ** 2:
			var card : Card = CARD.instantiate()
			card.add_data(CardData.new().with_rank(randi() % 13 + 1).with_suit(randi() % 4 + 1))
			#card.can_move_anim = false
			card.flipped = false
			cards.append(card)
		
		var i := 0
		for y in rows:
			for x in grid_container.columns - y * 2:
				var control : Control = grid_container.get_child(xyi(x + y, y))
				control.add_child(cards[i])
				cards[i].owner = self
				cards[i].move_to(control.position)
				i += 1

@onready var grid_container: GridContainer = %GridContainer
@onready var card_control: Control = %CardControl

var cards : Array[Card]

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	for card in cards:
		var control : Control = card.get_parent()
		card.move_to(control.global_position + control.size / 2)

func down() -> void:
	pass
	
func left() -> void:
	pass

func right() -> void:
	pass
	
func ixy(i:int) -> Vector2i:
	var x := i / grid_container.columns
	var y := i / rows
	return Vector2i(x, y)
	
func xyi(x: int, y :int) -> int:
	return x + y * grid_container.columns
