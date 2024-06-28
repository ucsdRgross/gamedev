extends Control
class_name Map

signal card_clicked(card:Card)

const CARD = preload("res://card.tscn")
var containers : Array 
var index_to_card : Dictionary
var card_to_index : Dictionary
var tween_transition : Tween
@onready var grid_container: GridContainer = $GridContainer

func _ready() -> void:
	containers = grid_container.get_children()
	var cols : int = grid_container.columns
	var i : int = 0
	for c:Control in containers:
		var card : Card = CARD.instantiate()
		card.suit = randi() % 4 + 1
		card.rank = randi() % 13 + 1
		card.can_move_anim = false
		card.clicked.connect(_on_card_clicked)
		var zone : Card = c.get_child(0)
		zone.front.self_modulate.a = 0
		c.add_child(card)
		zone.add_card(card)
		var row := i / cols
		var col := i % cols
		card_to_index[card] = Vector2i(row,col)
		index_to_card[Vector2i(row,col)] = card
		i+=1
	
	for coord:Vector2i in [Vector2i(0,0),Vector2i(0,cols-1),Vector2i(cols-1,0),Vector2i(cols-1,cols-1)]:
		index_to_card[coord].flipped = false

func _on_card_clicked(card : Card) -> void:
	if card.flipped or (tween_transition and tween_transition.is_running()):
		return
	var surroundings : Array[Vector2i] = [#Vector2(-1,-1),
										Vector2i(0,-1),
										#Vector2(1,-1),
										Vector2i(-1,0),
										#Vector2(0,0),
										Vector2i(1,0),
										#Vector2(-1,1),
										Vector2i(0,1),
										#Vector2(1,1)
										]
	card.z_index = card.num_cards
	tween_transition = create_tween()
	tween_transition.tween_property(card, 'scale', Vector2(2,2), 1).as_relative()
	var cols : int = grid_container.columns
	tween_transition.parallel().tween_property(card, 'global_position', (index_to_card[Vector2i(cols/2,cols/2)] as Card).global_position, 1)
	tween_transition.tween_callback(card.hide)
	tween_transition.tween_callback(func()->void: card_clicked.emit(card))
	#tween_transition.tween_callback(card.queue_free)
	
	for s : Vector2i in surroundings:
		var index : Vector2i = card_to_index[card] + s
		if index in index_to_card:
			var c : Card = index_to_card[index]
			if c.flipped:
				c.flipped = false
			else:
				c.flipped = true
				var tween_hide := create_tween()
				tween_hide.tween_property(c, 'rotation', (1 if randi() % 2 == 0 else -1) * TAU, 0.5).as_relative()
				tween_hide.parallel().tween_property(c, "scale", Vector2(0.1,0.1), 0.5)
				tween_hide.tween_callback(c.hide)
	#await tween_transition.finished
	
