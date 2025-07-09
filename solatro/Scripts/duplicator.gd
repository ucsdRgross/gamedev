class_name Duplicator

static func deep_copy_game(game_og:Game, game_copy:Game) -> void:
	var duplicated : Dictionary[Object, Object] = {}
	var stack : Array[Object] = []
	var match_cards_helper : Callable = func(og_stack:Array[Card], new_stack:Array[Card]) -> void:
		for i in og_stack.size():
			var og_zone := og_stack[i]
			var new_zone := new_stack[i]
			while og_zone:
				duplicated[og_zone] = new_zone
				duplicated[new_zone] = new_zone
				stack.append(new_zone)
				og_zone = og_zone.top_card
				new_zone = new_zone.top_card
	match_cards_helper.call(game_og.inputs, game_copy.inputs)
	match_cards_helper.call(game_og.stacks, game_copy.stacks)
	match_cards_helper.call([game_og.free_space] as Array[Card], [game_copy.free_space] as Array[Card])
	var duplicate_helper : Callable = func(to_copy : Object) -> void:
		for prop : Dictionary in to_copy.get_property_list():
			var prop_name : String = prop.name
			if not to_copy.get(prop_name) or not (to_copy.get(prop_name) is Object or to_copy.get(prop_name) is Array): 
				continue
			elif to_copy[prop_name] is Object and duplicated.has(to_copy[prop_name]):
				to_copy[prop_name] = duplicated[to_copy[prop_name]]
			elif to_copy[prop_name] is Game:
				if prop_name != 'owner':
					to_copy[prop_name] = to_copy
			elif to_copy[prop_name] is CardData:
				var prop_og : CardData = to_copy[prop_name]
				var prop_copy : CardData = prop_og.duplicate(true)
				stack.append(prop_copy)
				duplicated[prop_og] = prop_copy
				to_copy[prop_name] = prop_copy
			elif to_copy[prop_name] is Card:
				if prop_name not in ["deck_popup", "discard_popup"]:
					print("Card reference not duplicated ", prop_name, to_copy[prop_name])
				#var prop_og : Card = to_copy[prop_name]
				#var prop_copy : Card = prop_og.duplicate(true)
				#stack.append(prop_copy)
				#duplicated[prop_og] = prop_copy
				#to_copy[prop_name] = prop_copy
			elif to_copy[prop_name] is CardModifier:
				var prop_og : CardModifier = to_copy[prop_name]
				var prop_copy : CardModifier = prop_og.duplicate(false)
				stack.append(prop_copy)
				duplicated[prop_og] = prop_copy
				to_copy[prop_name] = prop_copy
			elif to_copy[prop_name] is Array[CardData]:
				var prop_og : Array[CardData] = to_copy[prop_name]
				var array_copy : Array[CardData] = []
				#array_copy.resize(prop_og.size())
				for data in prop_og:
					if duplicated.has(data):
						array_copy.append(duplicated[data])
					else:
						var data_copy : CardData = data.duplicate(true)
						stack.append(data_copy)
						duplicated[data] = data_copy
						array_copy.append(data_copy)
				to_copy[prop_name] = array_copy
			elif to_copy[prop_name] is Array[Card]:
				var prop_og : Array[Card] = to_copy[prop_name]
				var array_copy : Array[Card] = []
				#array_copy.resize(prop_og.size())
				for data in prop_og:
					if duplicated.has(data):
						array_copy.append(duplicated[data])
					else:
						print("Card reference in Array not duplicated ", prop_name, to_copy[prop_name], data)
						#var data_copy : Card = data.duplicate(true)
						#stack.append(data_copy)
						#duplicated[data] = data_copy
						#array_copy.append(data_copy)
				to_copy[prop_name] = array_copy
			#else:
				#print(prop_name)
				#print(to_copy[prop_name])
				
	duplicate_helper.call(game_copy)
	while stack:
		duplicate_helper.call(stack.pop_back())
