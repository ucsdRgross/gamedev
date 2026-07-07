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

## Number of cards a pack of this booster generates.
func get_frame() -> int: return 5

## Open this pack on a map node: show the generated cards in a take-all ChoiceViewer
## (choose=0 = forced pickup; rerolls/extra picks come later from modifiers). The caller
## wires the viewer's `confirmed` signal to actually add the cards to the deck.
func on_map_picked(parent: Node) -> ChoiceViewer:
	var choices : int = get_frame()
	var choose : int = 0
	return ChoiceViewer.add_to_scene(parent, create_one_choice, choices, choose)

## Generate one pack card. Rank + suit are always rolled; stamp/skill/type are luck-gated
## (RunManager.luck grows with fame), which also keeps empty pools safe (no pick_random
## on an empty array).
func create_one_choice() -> CardData:
	var data := CardData.new()
	# return new array of possible results after running through run all mods
	var possible_ranks : Array[PipRank] = get_possible_ranks()
	if env: env.run_all_mods(&"on_get_possible_ranks", possible_ranks)
	var possible_suits : Array[PipSuit] = get_possible_suits()
	if env: env.run_all_mods(&"on_get_possible_suits", possible_suits)

	data.with_rank(possible_ranks.pick_random() as PipRank)
	data.with_suit(possible_suits.pick_random() as PipSuit)
	if _lucky():
		var possible_stamps : Array[CardModifierStamp] = get_possible_stamps()
		if env: env.run_all_mods(&"on_get_possible_stamps", possible_stamps)
		if possible_stamps:
			data.with_stamp(possible_stamps.pick_random() as CardModifierStamp)
	if _lucky():
		var possible_skills : Array[CardModifierSkill] = get_possible_skills()
		if env: env.run_all_mods(&"on_get_possible_skills", possible_skills)
		if possible_skills:
			data.with_skill(possible_skills.pick_random() as CardModifierSkill)
	# Type is NOT luck-gated to null: every card gets a base type (first pool entry, e.g.
	# TypePaper) like the starter decks, and luck upgrades it to a random pool type.
	var possible_types : Array[CardModifierType] = get_possible_types()
	if env: env.run_all_mods(&"on_get_possible_types", possible_types)
	if possible_types:
		if _lucky():
			data.with_type(possible_types.pick_random() as CardModifierType)
		else:
			data.with_type(possible_types[0])
	return data

func _lucky() -> bool:
	return randf() < RunManager.luck()

## Every component this pack could roll, as one preview card each — feeds the map node
## hover panel and view_choices.
func get_possible_preview_cards() -> Array[CardData]:
	var possible_ranks : Array[PipRank] = get_possible_ranks()
	if env: env.run_all_mods(&"on_get_possible_ranks", possible_ranks)
	var possible_suits : Array[PipSuit] = get_possible_suits()
	if env: env.run_all_mods(&"on_get_possible_suits", possible_suits)
	var possible_stamps : Array[CardModifierStamp] = get_possible_stamps()
	if env: env.run_all_mods(&"on_get_possible_stamps", possible_stamps)
	var possible_skills : Array[CardModifierSkill] = get_possible_skills()
	if env: env.run_all_mods(&"on_get_possible_skills", possible_skills)
	var possible_types : Array[CardModifierType] = get_possible_types()
	if env: env.run_all_mods(&"on_get_possible_types", possible_types)
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
	return card_datas

func view_choices() -> void:
	DeckViewer.show_deck(CardEnvironment.CURRENT, get_possible_preview_cards())
