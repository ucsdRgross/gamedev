class_name TypeStone
extends CardModifier
	
func _init() -> void:
	name = "Stone Card"
	description = "Sinks to bottom of every stack"
	frame = 4

func on_stack_card(target: Card) -> void:
	if is_instance_valid(target) and data == target.data and not is_on_bottom(target):
		var bot_card := get_bottom_card(target)
		bot_card.add_card(target)

func on_append(deck:Array[CardData], data:CardData) -> void:
	if data == self.data:
		deck.erase(data)
		var i : int = 0
		while i < deck.size() and deck[i].type and deck[i].type is TypeStone:
			i += 1
		deck.insert(i, data)

func get_bottom_card(card: Card) -> Card:
	while not is_on_bottom(card):
		card = card.bot_card
	return card.bot_card
		
func is_on_bottom(card: Card) -> bool:
	if card.bot_card.is_zone:
		return true
	elif card.bot_card.data.type is TypeStone:
		return true
	return false
