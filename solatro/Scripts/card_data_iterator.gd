class_name CardDataIterator

var card_count : int
var board : Array[Game.CardArray]
var next_card_data : CardData
enum {DECK, INPUTS, BOARD, DISCARD}
var phase := DECK

func should_continue() -> bool:
	match phase:
		DECK:
			if card_count < Game.CURRENT.draw_deck.size():
				next_card_data = Game.CURRENT.draw_deck[card_count]
				return true
			else:
				phase = INPUTS
				card_count = 0
				return should_continue()
		INPUTS:
			if not card_count < Game.CURRENT.inputs.size():
				phase = BOARD
				card_count = 0
				return should_continue()
			var card := Game.CURRENT.inputs[card_count].top_card
			while not card:
				card_count += 1
				if not card_count < Game.CURRENT.inputs.size():
					phase = BOARD
					card_count = 0
					return should_continue()
				card = Game.CURRENT.inputs[card_count].top_card
			next_card_data = card.data
			return true
		BOARD:
			board = Game.CURRENT.get_board_cols()
			if not board or not card_count < board[0].cards.size() * 5:
				phase = DISCARD
				card_count = 0
				return should_continue()
			var card : Card = board[card_count % 5].cards[card_count / 5]
			while not card:
				card_count += 1
				if not card_count < board[0].cards.size() * 5:
					phase = DISCARD
					card_count = 0
					return should_continue()
				card = board[card_count % 5].cards[card_count / 5]
			next_card_data = card.data
			return true
		DISCARD:
			if card_count < Game.CURRENT.discard_deck.size():
				next_card_data = Game.CURRENT.discard_deck[card_count]
				return true
			else:
				return false
	return false

func _iter_init(arg:Variant) -> bool:
	phase = DECK
	card_count = 0
	return should_continue()

func _iter_next(arg:Variant) -> bool:
	card_count += 1
	return should_continue()

func _iter_get(arg:Variant) -> CardData:
	return next_card_data
