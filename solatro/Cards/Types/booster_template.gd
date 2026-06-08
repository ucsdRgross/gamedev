@abstract
class_name BoosterTemplate
extends CardModifierType

@abstract
func get_possible_ranks() -> Array[PipRank]
@abstract
func get_possible_suits() -> Array[PipSuit]
@abstract
func get_possible_stamps() -> Array[CardModifierStamp]
@abstract
func get_possible_skills() -> Array[CardModifierSkill]
@abstract
func get_possible_types() -> Array[CardModifierType]

func on_map_picked(map:Node) -> void:
	var choices : int = 5
	var choose : int = 0
	ChoiceViewer.add_to_scene(map, create_one_choice, choices, choose)
	
func create_one_choice() -> CardData:
	var data := CardData.new()
	# return new array of possible results after running through run all mods
	var possible_ranks : Array[PipRank] = get_possible_ranks()
	CardEnvironment.run_all_mods(&"on_get_possible_ranks", possible_ranks)
	var possible_suits : Array[PipSuit] = get_possible_suits()
	CardEnvironment.run_all_mods(&"on_get_possible_suits", possible_suits)
	var possible_stamps : Array[CardModifierStamp] = get_possible_stamps()
	CardEnvironment.run_all_mods(&"on_get_possible_stamps", possible_stamps)
	var possible_skills : Array[CardModifierSkill] = get_possible_skills()
	CardEnvironment.run_all_mods(&"on_get_possible_skills", possible_skills)
	var possible_types : Array[CardModifierType] = get_possible_types()
	CardEnvironment.run_all_mods(&"on_get_possible_types", possible_types)
	
	data.with_rank(possible_ranks.pick_random() as PipRank)
	data.with_suit(possible_suits.pick_random() as PipSuit)
	data.with_stamp(possible_stamps.pick_random() as CardModifierStamp)
	data.with_skill(possible_skills.pick_random() as CardModifierSkill)
	data.with_type(possible_types.pick_random() as CardModifierType)
	return data

func view_choices() -> void:
	var possible_ranks : Array[PipRank] = get_possible_ranks()
	CardEnvironment.run_all_mods(&"on_get_possible_ranks", possible_ranks)
	var possible_suits : Array[PipSuit] = get_possible_suits()
	CardEnvironment.run_all_mods(&"on_get_possible_suits", possible_suits)
	var possible_stamps : Array[CardModifierStamp] = get_possible_stamps()
	CardEnvironment.run_all_mods(&"on_get_possible_stamps", possible_stamps)
	var possible_skills : Array[CardModifierSkill] = get_possible_skills()
	CardEnvironment.run_all_mods(&"on_get_possible_skills", possible_skills)
	var possible_types : Array[CardModifierType] = get_possible_types()
	CardEnvironment.run_all_mods(&"on_get_possible_types", possible_types)
	var card_datas : Array[CardData] = []
	for type in possible_types:
		card_datas.append(CardData.new().with_type(type))
	for stamp in possible_stamps:
		card_datas.append(CardData.new().with_stamp(stamp))
	for skill in possible_skills:
		card_datas.append(CardData.new().with_skill(skill))
	for suit in possible_suits:
		card_datas.append(CardData.new().with_suit(suit))
	for rank in possible_ranks:
		card_datas.append(CardData.new().with_rank(rank))
	DeckViewer.show_deck(CardEnvironment.CURRENT, card_datas)
