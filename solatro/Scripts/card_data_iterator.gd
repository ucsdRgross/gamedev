class_name CardDataIterator

var card_count : int
var next_card_data : CardData
enum {DECK, UPPER, LOWER, DISCARD, UPPER_RULES, LOWER_RULES, RULES}
var phase : int = DECK

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
			if card_count < Game.CURRENT.rules_deck.size():
				next_card_data = Game.CURRENT.rules_deck[card_count]
				return true
			else:
				return false
	return false

func iterate_array(deck:Array[CardData], next_stage:int) -> bool:
	if card_count < deck.size():
		next_card_data = deck[card_count]
		return true
	else:
		phase = next_stage
		card_count = 0
		return should_continue()

func iterate_2d_array(zone:Array[ArrayCardData], next_stage:int) -> bool:
	var total_cards : int = 0
	var largest_col : int = 0
	for a in zone:
		total_cards += a.datas.size()
		if a.datas.size() > largest_col: largest_col = a.datas.size()
	var count : int = 0
	if card_count < total_cards:
		for row : int in largest_col:
			for col : int in zone.size():
				if row < zone[col].datas.size():
					if count == card_count:
						next_card_data = zone[col].datas[row]
						break
					count += 1
		return true
	else:
		phase = next_stage
		card_count = 0
		return should_continue()

func _iter_init(arg:Variant) -> bool:
	phase = DECK
	card_count = 0
	return should_continue()

func _iter_next(arg:Variant) -> bool:
	card_count += 1
	return should_continue()

func _iter_get(arg:Variant) -> CardData:
	return next_card_data
