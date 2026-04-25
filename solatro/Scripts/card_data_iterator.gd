class_name CardDataIterator
# Currently does not support nested loops and don't there will be reason to
# Below class variables would need to be moved into _arg as dict to do so

var next_card_data : CardData
enum {DECK, UPPER, LOWER, DISCARD, UPPER_RULES, LOWER_RULES, RULES}
var phase : int = DECK
var current_row : int = 0
var current_col : int = 0
var is_row_empty := true

func should_continue() -> bool:
	match phase:
		DECK:
			return iterate_array(Game.CURRENT.draw_deck, UPPER)
		UPPER:
			return iterate_2d_array(Game.CURRENT.upper_zone, LOWER)
		LOWER:
			return iterate_2d_array(Game.CURRENT.lower_zone, DISCARD)
		DISCARD:
			return iterate_array(Game.CURRENT.discard_deck, UPPER_RULES)
		UPPER_RULES:
			return iterate_array(Game.CURRENT.upper_zone_type, LOWER_RULES)
		LOWER_RULES:
			return iterate_array(Game.CURRENT.lower_zone_type, RULES)
		RULES:
			if current_col < Game.CURRENT.rules_deck.size():
				next_card_data = Game.CURRENT.rules_deck[current_col]
				current_col += 1
				return true
			else:
				return false
	return false

func iterate_array(deck:Array[CardData], next_stage:int) -> bool:
	if current_col < deck.size():
		next_card_data = deck[current_col]
		current_col += 1
		return true
	else:
		phase = next_stage
		current_col = 0
		return should_continue()

func iterate_2d_array(zone:Array[ArrayCardData], next_stage:int) -> bool:
	while true:
		if current_col < zone.size():
			var col : Array[CardData] = zone[current_col].datas
			if current_row < col.size():
				next_card_data = col[current_row]
				current_col += 1
				is_row_empty = false
				return true
			else:
				current_col += 1
		else:
			if is_row_empty: 
				break
			current_row += 1
			current_col = 0
			is_row_empty = true
	phase = next_stage
	current_row = 0
	current_col = 0
	return should_continue()

func _iter_init(_arg:Variant) -> bool:
	return should_continue()

func _iter_next(_arg:Variant) -> bool:
	return should_continue()

func _iter_get(_arg:Variant) -> CardData:
	return next_card_data
