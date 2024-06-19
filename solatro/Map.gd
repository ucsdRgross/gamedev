extends Control

const CARD = preload("res://card.tscn")
var containers : Array 
@onready var grid_container: GridContainer = $GridContainer
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	containers = grid_container.get_children()
	for c:Control in containers:
		var card : Card = CARD.instantiate()
		card.suit = randi() % 4 + 1
		card.rank = randi() % 13 + 1
		var zone : Card = c.get_child(0)
		zone.front.frame = 54
		grid_container.add_child(card)
		zone.add_card(card)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
