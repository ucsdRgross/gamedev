class_name GameData
extends Resource

@export_storage var deck : Array[CardData] = []
@export_storage var discard : Array[CardData] = []
@export_storage var input : Array[CardStack] = []
@export_storage var board : Array[CardStack] = []

class CardStack:
	var array : Array[CardData] = []

static func create_save_state(game:Game) -> GameData:
	var game_data : GameData = GameData.new()
	game_data.deck = game.draw_deck
	game_data.discard = game.discard_deck
	game_data.input = card_stack_to_data(game.inputs)
	game_data.input = card_stack_to_data(game.stacks)
	return game_data

static func load_save_state(game:Game, save_data:GameData) -> void:
	pass

static func card_stack_to_data(cols:Array[Card]) -> Array[CardStack]:
	var datas : Array[CardStack] = []
	for zone : Card in cols:
		var stack : CardStack = CardStack.new()
		var next_card : Card = zone.top_card
		while next_card:
			stack.array.append(next_card)
			next_card = next_card.top_card
		datas.append(stack)
	return datas
