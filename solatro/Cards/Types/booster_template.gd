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
## (choose=0 = forced pickup; extra picks come later from modifiers) with the shared free-reroll
## pool from settings. The caller wires the viewer's `confirmed` signal to actually add the cards
## to the deck.
func on_map_picked(parent: Node) -> ChoiceViewer:
	var choices : int = get_frame()
	var choose : int = 0
	var rerolls : int = SettingsManager.settings.booster_reroll_pool
	return await ChoiceViewer.add_to_scene(parent, create_one_choice, choices, choose, rerolls)

## E8: one pool gather = call the pool getter, then AWAIT its on_get_possible_* broadcast,
## so async mods finish editing the pool BEFORE anything picks from or lists it (the old
## fire-and-forget dispatch was a latent race: a slow mod's edits could land after the
## pick and silently do nothing). Returns the pool (the getter's array, post-edit).
func _gather(getter: Callable, hook: StringName) -> Array:
	var pool : Array = getter.call()
	if env: await env.run_all_mods(hook, pool)
	return pool

## Generate one pack card. Rank + suit are always rolled; stamp/skill/type are luck-gated
## (RunManager.luck grows with fame), which also keeps empty pools safe (no pick_random
## on an empty array).
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
	# Type is NOT luck-gated to null: every card gets a base type (first pool entry, e.g.
	# TypePaper) like the starter decks, and luck upgrades it to a random pool type.
	var possible_types : Array = await _gather(get_possible_types, &"on_get_possible_types")
	if possible_types:
		if _lucky():
			data.with_type(possible_types.pick_random() as CardModifierType)
		else:
			data.with_type(possible_types[0]as CardModifierType)
	return data

func _lucky() -> bool:
	return randf() < RunManager.luck()

## Every component this pack could roll, as one preview card each — feeds the map node
## hover panel and view_choices. Pools gather (and broadcast) in the same order
## create_one_choice rolls them; the preview list keeps its type/stamp/skill/suit/rank order.
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

func view_choices() -> void:
	DeckViewer.show_deck(CardEnvironment.CURRENT, await get_possible_preview_cards())
