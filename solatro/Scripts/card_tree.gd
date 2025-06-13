class_name CardTree
extends Resource

var card_tree : Dictionary[Vector2i,CardSpaceArray]

func _init() -> void:
	setup_columns(5)
	
func setup_columns(cols : int) -> void:
	for i in cols:
		var card_space_array := CardSpaceArray.new()
		card_tree[Vector2i(i,0)] = CardSpaceArray.new()

func add_zone(position:Vector2i, card_data:CardData) -> void:
	pass

func stack_card_on_pos(position:Vector2i, card_data:CardData) -> void:
	pass

func stack_card_on_card(card_data:CardData) -> void:
	pass
	
class CardSpaceArray:
	var cards : Array[CardSpace]

class CardSpace:
	var position : Vector2i
	var card_data : CardData
	
