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

## Opens this pack on a map node as a take-all ChoiceViewer (choose 0 is a forced pickup) with the shared free-reroll pool from settings; the caller wires `confirmed` to add the cards to the deck.
func on_map_picked(parent: Node) -> ChoiceViewer:
	var choices : int = get_frame()
	var choose : int = 0
	var rerolls : int = SettingsManager.settings.booster_reroll_pool
	return await ChoiceViewer.add_to_scene(parent, create_one_choice, choices, choose, rerolls)

# ⚠ THE BROADCAST IS AWAITED so an async mod finishes editing the pool BEFORE anything picks from or
# lists it; an edit landing after the pick would silently do nothing.
## One pool gather: the getter's array after every mod's `hook` has edited it.
func _gather(getter: Callable, hook: StringName) -> Array:
	var pool : Array = getter.call()
	if api: await api.run_all_mods(hook, pool)
	return pool

# TYPE IS NEVER LEFT NULL: every card gets the pool's first type (TypePaper, as the starter decks do)
# and luck upgrades it to a random pool type.
## Generates one pack card: rank and suit always rolled, stamp, skill and type gated by RunManager.luck, which grows with fame.
func create_one_choice() -> CardData:
	var data := CardData.new()
	var possible_ranks : Array = await _gather(get_possible_ranks, &"on_get_possible_ranks")
	var possible_suits : Array = await _gather(get_possible_suits, &"on_get_possible_suits")
	data.with_rank(possible_ranks.pick_random() as PipRank)
	data.with_suit(possible_suits.pick_random() as PipSuit)
	if _lucky():
		var possible_stamps : Array = await _gather(get_possible_stamps, &"on_get_possible_stamps")
		if possible_stamps:
			data.with_stamp(possible_stamps.pick_random() as CardModifierStamp)
	if _lucky():
		var possible_skills : Array = await _gather(get_possible_skills, &"on_get_possible_skills")
		if possible_skills:
			data.with_skill(possible_skills.pick_random() as CardModifierSkill)
	var possible_types : Array = await _gather(get_possible_types, &"on_get_possible_types")
	if possible_types:
		if _lucky():
			data.with_type(possible_types.pick_random() as CardModifierType)
		else:
			data.with_type(possible_types[0]as CardModifierType)
	return data

func _lucky() -> bool:
	return randf() < RunManager.luck()

## Every component this pack could roll, as one preview card each; the possible-cards list groups them by kind itself.
func get_possible_preview_cards() -> Array[CardData]:
	var possible_ranks : Array = await _gather(get_possible_ranks, &"on_get_possible_ranks")
	var possible_suits : Array = await _gather(get_possible_suits, &"on_get_possible_suits")
	var possible_stamps : Array = await _gather(get_possible_stamps, &"on_get_possible_stamps")
	var possible_skills : Array = await _gather(get_possible_skills, &"on_get_possible_skills")
	var possible_types : Array = await _gather(get_possible_types, &"on_get_possible_types")
	var card_datas : Array[CardData] = []
	for type : CardModifierType in possible_types:
		card_datas.append(CardData.new().with_type(type))
	for stamp : CardModifierStamp in possible_stamps:
		card_datas.append(CardData.new().with_stamp(stamp))
	for skill : CardModifierSkill in possible_skills:
		card_datas.append(CardData.new().with_skill(skill))
	for suit : PipSuit in possible_suits:
		card_datas.append(CardData.new().with_suit(suit))
	for rank : PipRank in possible_ranks:
		card_datas.append(CardData.new().with_rank(rank))
	return card_datas

