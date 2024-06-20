extends Control

const CARD = preload("res://card.tscn")
var containers : Array 
var index_to_card : Dictionary
var card_to_index : Dictionary
@onready var grid_container: GridContainer = $GridContainer
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	containers = grid_container.get_children()
	var cols : int = grid_container.columns
	var i : int = 0
	for c:Control in containers:
		var card : Card = CARD.instantiate()
		card.suit = randi() % 4 + 1
		card.rank = randi() % 13 + 1
		card.clicked.connect(_on_card_clicked)
		var zone : Card = c.get_child(0)
		zone.front.self_modulate.a = 0
		c.add_child(card)
		zone.add_card(card)
		var row := i / cols
		var col := i % cols
		card_to_index[card] = Vector2(row,col)
		index_to_card[Vector2(row,col)] = card
		i+=1
	
	for coord:Vector2 in [Vector2(0,0),Vector2(0,cols-1),Vector2(cols-1,0),Vector2(cols-1,cols-1)]:
		index_to_card[coord].flipped = false
		
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_card_clicked(card : Card) -> void:
	if card.flipped:
		return
	var surroundings : Array[Vector2] = [#Vector2(-1,-1),
										Vector2(0,-1),
										#Vector2(1,-1),
										Vector2(-1,0),
										Vector2(0,0),
										Vector2(1,0),
										#Vector2(-1,1),
										Vector2(0,1),
										#Vector2(1,1)
										]
	for s : Vector2 in surroundings:
		var index : Vector2 = card_to_index[card] + s
		if index in index_to_card:
			var c : Card = index_to_card[index]
			if c.flipped:
				c.flipped = false
			else:
				c.hide()
