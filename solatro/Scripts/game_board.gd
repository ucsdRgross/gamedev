class_name GameBoard
extends Resource

# First row is always zone cards
var input_row : Array[CardColumn] = []
var card_board : Array[CardColumn] = []
var game : Game

class CardColumn:
	var cards : Array[Card]
	func has_row(index:int) -> bool:
		return index < cards.size() - 1
	
func setup_columns(cols : int) -> void:
	input_row.resize(cols)
	card_board.resize(cols)
	input_row.fill(CardColumn.new())
	card_board.fill(CardColumn.new())

func add_card_to_input(col:int, card:Card) -> void:
	var stack := input_row[col].cards
	card.reparent(stack[-1])
	stack.append(card)

func add_card_to_col(col:int, card:Card) -> void:
	var stack := card_board[col].cards
	card.reparent(stack[-1])
	stack.append(card)

func drop_input_cards_down(col:int) -> void:
	var input_col := input_row[col].cards
	if input_col.size() > 1:
		var input : Array[Card] = input_col.slice(1)
		input_col.resize(1)
		var board_col := card_board[col].cards
		var last_card_in_stack := board_col[-1]
		board_col.append_array(input)
		input[0].reparent(last_card_in_stack)

func move_stack_onto_card(stack_parent:Card, onto:Card) -> bool:
	if stack_parent.get_parent() == onto:
		return false
	var stack_index := get_card_index(stack_parent)
	var onto_index := get_card_index(onto)
	var stack : Array[Card] = card_board[stack_index.x].cards
	var slice : Array[Card] = stack.slice(stack_index.y)
	stack.resize(stack.size() - slice.size())
	var target_stack := card_board[onto_index.x].cards
	# if placing onto bottom card
	if onto_index.y == target_stack.size() - 1:
		target_stack.append_array(slice)
		stack_parent.reparent(onto)
	else:
		var bottom_slice : Array[Card] = target_stack.slice(onto_index.y + 1)
		target_stack.resize(target_stack.size() - bottom_slice.size())
		target_stack.append_array(slice)
		target_stack.append_array(bottom_slice)
		stack_parent.reparent(onto)
		bottom_slice[0].reparent(slice[-1])
	return true
	
func move_card_onto_card(moving_card:Card, onto:Card) -> bool:
	if moving_card.get_parent() == onto:
		return false
	var mover_index := get_card_index(moving_card)
	var onto_index := get_card_index(onto)
	var source_stack := card_board[mover_index.x].cards
	var target_stack := card_board[onto_index.x].cards
	if mover_index.y < source_stack.size() - 1:
		source_stack[mover_index.y + 1].reparent(source_stack[mover_index.y - 1])
	source_stack.erase(moving_card)
	target_stack.insert(onto_index.y + 1, moving_card)
	moving_card.reparent(onto)
	if onto_index.y + 1 < target_stack.size() - 1:
		target_stack[onto_index.y + 2].reparent(moving_card)
	return true
		
func get_card_stack(card:Card) -> Array[Card]:
	var card_index := get_card_index(card)
	return card_board[card_index.x].cards.slice(card_index.y)

func remove_card(card:Card) -> void:
	var card_index := get_card_index(card)
	var col := card_board[card_index.x]
	col.cards.erase(card)
	if col.has_row(card_index.y):
		col.cards[card_index.y].reparent(col.cards[card_index.y - 1])

func get_card_col(card:Card) -> CardColumn:
	var index := get_card_index(card)
	if index.x < INF:
		return card_board[index.x]
	return null

func get_square_board() -> Array[CardColumn]:
	var x := get_largest_col_size()
	var board : Array[CardColumn] = []
	for col in card_board:
		var new_col : CardColumn = CardColumn.new()
		new_col.cards = col.cards.duplicate()
		new_col.cards.resize(x)
		board.append(new_col)
	return board
	
func get_card_index(card:Card) -> Vector2i:
	for col in card_board.size():
		var index : int = card_board[col].cards.find(card, 1)
		if index != -1:
			return Vector2i(col, index)
	return Vector2i.MAX

func get_largest_col_size() -> int:
	var largest_size : int = 0
	for col in card_board:
		var size := col.cards.size()
		if size > largest_size:
			largest_size = size
	return largest_size
