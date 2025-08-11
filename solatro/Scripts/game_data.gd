class_name GameData
extends Resource

const CARD = preload("res://Cards/card.tscn")

@export_storage var deck : Array[CardData] = []
@export_storage var discard : Array[CardData] = []
@export_storage var inputs : Array[CardStack] = []
@export_storage var stacks : Array[CardStack] = []

class CardStack:
	@export_storage var array : Array[CardData] = []

static func create_save_state(game:Game) -> GameData:
	var game_data : GameData = GameData.new()
	game_data.deck = game.draw_deck
	game_data.discard = game.discard_deck
	game_data.inputs = card_stack_to_data(game.inputs)
	game_data.stacks = card_stack_to_data(game.stacks)
	var duplicated_resources : Dictionary[Resource, Resource] = {}
	var nested_resources : Array[Resource] = [game_data]
	var duplicate_helper : Callable = func(to_copy : Object) -> void:
		for prop : Dictionary in to_copy.get_property_list():
			var prop_name : String = prop.name
			if not to_copy.get(prop_name) or not (to_copy.get(prop_name) is Resource or to_copy.get(prop_name) is Array): 
				continue
			elif to_copy[prop_name] is Resource and duplicated_resources.has(to_copy[prop_name]):
				to_copy[prop_name] = duplicated_resources[to_copy[prop_name]]
			elif to_copy[prop_name] is CardData:
				var prop_og : CardData = to_copy[prop_name]
				var prop_copy : CardData = prop_og.duplicate(true)
				nested_resources.append(prop_copy)
				duplicated_resources[prop_og] = prop_copy
				duplicated_resources[prop_copy] = prop_copy
				to_copy[prop_name] = prop_copy
			elif to_copy[prop_name] is CardModifier:
				var prop_og : CardModifier = to_copy[prop_name]
				var prop_copy : CardModifier = prop_og.duplicate(true)
				nested_resources.append(prop_copy)
				duplicated_resources[prop_og] = prop_copy
				duplicated_resources[prop_copy] = prop_copy
				to_copy[prop_name] = prop_copy
			elif to_copy[prop_name] is Array[CardData]:
				var prop_og : Array[CardData] = to_copy[prop_name]
				var array_copy : Array[CardData] = []
				for data in prop_og:
					if duplicated_resources.has(data):
						array_copy.append(duplicated_resources[data])
					else:
						var data_copy : CardData = data.duplicate(true)
						nested_resources.append(data_copy)
						duplicated_resources[data] = data_copy
						duplicated_resources[data_copy] = data_copy
						array_copy.append(data_copy)
				to_copy[prop_name] = array_copy
			elif to_copy[prop_name] is Array[CardStack]:
				var prop_og : Array[CardStack] = to_copy[prop_name]
				var stack_array_copy : Array[CardStack] = []
				for card_stack in prop_og:
					var card_stack_copy := CardStack.new()
					for card_data in card_stack.array:
						if duplicated_resources.has(card_data):
							card_stack_copy.array.append(duplicated_resources[card_data])
						else:
							var data_copy : CardData = card_data.duplicate(true)
							nested_resources.append(data_copy)
							duplicated_resources[card_data] = data_copy
							duplicated_resources[data_copy] = data_copy
							card_stack_copy.array.append(data_copy)
					stack_array_copy.append(card_stack_copy)
				to_copy[prop_name] = stack_array_copy
			elif to_copy[prop_name] is Card:
				print("Card reference cannot be duplicated ", prop_name, to_copy[prop_name])
			elif to_copy[prop_name] is Array[Card]:
				print("Card reference in Array cannot be duplicated ", prop_name, to_copy[prop_name])
				
	duplicate_helper.call(game_data)
	while nested_resources:
		duplicate_helper.call(nested_resources.pop_back())
	return game_data

static func load_save_state(game:Game, save_data:GameData) -> void:
	
	pass

func load_game(game:Game) -> void:
	game.draw_deck = deck
	game.discard_deck = discard
	load_stack(game.inputs, inputs, game)
	load_stack(game.stacks, stacks, game)
	
static func load_stack(cards:Array[Card], save_datas:Array[CardStack], game:Game) -> void:
	for i in cards.size():
		var zone : Card = cards[i]
		var old_stack := zone.top_card
		if old_stack:
			zone.top_card = null
			var next_card := old_stack
			while next_card:
				var this_card := next_card
				next_card = next_card.top_card
				this_card.bot_card = null
				this_card.top_card = null
				#this_card.queue_free()
			old_stack.queue_free()
		var next_card := zone
		if save_datas:
			for data in save_datas[i].array:
				var card : Card = CARD.instantiate()
				card.add_data(data, true)
				zone.add_child(card)
				next_card.add_card(card, false)
				card.flipped = false
				next_card = card

static func card_stack_to_data(cols:Array[Card]) -> Array[CardStack]:
	var datas : Array[CardStack] = []
	for zone : Card in cols:
		var stack : CardStack = CardStack.new()
		var next_card : Card = zone.top_card
		while next_card:
			stack.array.append(next_card.data)
			next_card = next_card.top_card
		datas.append(stack)
	return datas
