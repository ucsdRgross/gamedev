extends Node2D

const CARD = preload("res://card.tscn")

var held_card : Card = null
var held_card_offset : Vector2
var turns : int = 20:
	set(value):
		($Turns/Label as Label).text = str(value)
		turns = value
var goal : int = 100:
	set(value):
		($Goal/Label as Label).text = str(value)
		goal = value
var total_score : int = 0:
	set(value):
		($Total/Label as Label).text = str(value)
		total_score = value
var last_score : int = 0:
	set(value):
		($Score/Label as Label).text = str(value)
		last_score = value
var rerolls : int = 0:
	set(value):
		($Rerolls/Label as Label).text = str(value)
		rerolls = value

func _ready() -> void:
	randomize()

func _process(delta: float) -> void:
	if held_card:
		held_card.global_position = get_global_mouse_position() + held_card_offset

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			#print("clicked")
			if held_card:
				drop_held_card()

func _on_child_entered_tree(node: Node) -> void:
	if node is Card:
		(node as Card).clicked.connect(_on_card_clicked)

func _on_card_clicked(card : Card) -> void:
	if held_card:
		if can_add_card(card, held_card):
			card.add_card(held_card)
			drop_held_card()
	elif not held_card:
		if card.is_zone:
			pass
		else:
			var next_card := card
			while next_card.top_card:
				if not can_pickup_stack(next_card, next_card.top_card):
					return
				next_card = next_card.top_card
			card.pickup()
			held_card = card
			held_card_offset = held_card.global_position - get_global_mouse_position()

func can_add_card(stack : Card, to_stack : Card) -> bool:
	if stack.is_zone:
		return true
	if stack.top_card == to_stack and to_stack == held_card:
		return true
	if not stack.top_card:
		if stack.suit != to_stack.suit:
			if to_stack.rank == stack.rank - 1:
				return true
			if to_stack.rank == stack.rank + 1:
				return true
	return false

func can_pickup_stack(stack : Card, to_stack : Card) -> bool:
	if stack.is_zone:
		return true
	if stack.suit != to_stack.suit:
		if to_stack.rank == stack.rank - 1:
			return true
		if to_stack.rank == stack.rank + 1:
			return true
	return false

func drop_held_card() -> void:
	held_card.drop()
	held_card = null

func score(card : Card) -> int:
	var card_amount : int = 1
	var rank_total : int = card.rank
	while card.top_card:
		card = card.top_card
		card_amount += 1
		rank_total += card.rank
	return rank_total * card_amount
		
func _on_button_pressed() -> void:
	var submitted : Card = $Submission
	if submitted.top_card:
		last_score = score(submitted.top_card)
		total_score += last_score
		submitted.top_card.queue_free()
		submitted.top_card = null
	
	if total_score >= goal:
		print('you win!')
		return
		
	if turns <= 0:
		print('you lose!')
		return
	
	var input : Array[Card] = [$Input1, $Input2, $Input3, $Input4, $Input5]
	var stack : Array[Card] = [$Play1, $Play2, $Play3, $Play4, $Play5]
	for i:int in input.size():
		if input[i].top_card:
			stack[i].get_last_card().add_card(input[i].top_card)
	for zone : Card in input:
		var card : Card = CARD.instantiate()
		card.suit = randi() % 4 + 1
		card.rank = randi() % 13 + 1
		add_child(card)
		zone.add_card(card)
	
	turns -= 1
