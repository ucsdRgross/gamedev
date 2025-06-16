class_name CardBoard
extends Resource

# First row is always zone cards
var input_row : Array[CardColumn] = []
var card_board : Array[CardColumn] = []

class CardColumn:
	var cards : Array[Card]
	
func setup_columns(cols : int) -> void:
	for i in cols:
		card_board.append(CardColumn.new())

func add_card_to_col(col:int, card:Card) -> void:
	var stack := card_board[col].cards
	card.reparent(stack[-1])
	stack.append(card)

func move_stack_onto_card(stack_parent:Card, onto:Card) -> void:
	var stack_index := get_card_index(stack_parent)
	var card_index := get_card_index(onto)
	var stack : Array[Card] = card_board[stack_index.x].cards
	var slice : Array[Card] = stack.slice(stack_index.y)
	stack.resize(stack.size() - slice.size())
	var target_stack := card_board[card_index.x].cards
	# if placing onto bottom card
	if card_index.y == target_stack.size() - 1:
		target_stack.append_array(slice)
		stack_parent.reparent(onto)
	else:
		var bottom_slice : Array[Card] = target_stack.slice(card_index.y + 1)
		target_stack.resize(target_stack.size() - bottom_slice.size())
		target_stack.append_array(slice)
		target_stack.append_array(bottom_slice)
		stack_parent.reparent(onto)
		bottom_slice[0].reparent(slice[-1])
		
func move_card_onto_card(moving_card:Card, on_top:Card) -> void:
	pass
	
func get_card_index(card:Card) -> Vector2i:
	for col in card_board.size():
		var index : int = card_board[col].cards.find(card, 1)
		if index != -1:
			return Vector2i(col, index)
	return Vector2i.ZERO
