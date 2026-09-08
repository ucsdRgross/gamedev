class_name SkillGridAllotment
extends CardModifierSkill

func get_str() -> String: return TRANSLATION.find('GRID_ALLOTMENT_CARD')
func get_description() -> String: return TRANSLATION.find('GRID_ALLOTMENT_CARD_DESCRIPTION')
func get_frame() -> int: return 11

## Engine rules machinery: never a combo class, a constant baseline every act like the other
## rules-deck cards.
func combo_key(_hook: StringName = &"") -> String: return ""

## The deck-size-to-grid-count formula. Evaluated once at game start, against the deck size at
## that moment: ceil(deck_size / grid_cards_per_unlock), floored at 1 grid, capped at
## grid_max_count. Integer ceiling division as (n + d - 1) / d is exact for GDScript's
## truncating `/` and avoids a float round-trip; d >= 1 is enforced by the setting's own setter.
static func target_grid_count(deck_size: int, cards_per_unlock: int, max_count: int) -> int:
	var d := maxi(cards_per_unlock, 1)
	var raw := (maxi(deck_size, 0) + d - 1) / d
	return clampi(maxi(raw, 1), 1, max_count)

## Every persistent `SkillGridCreator` currently in the rules deck, in order.
func _creator_cards() -> Array[CardData]:
	var out : Array[CardData] = []
	for card : CardData in api.rules_deck():
		if card.skill is SkillGridCreator: out.append(card)
	return out

## On game start, matches the persistent grid-creator card count to the target computed from
## the deck just dealt (the deal runs before this hook), adding or removing `SkillGridCreator`
## cards so their count tracks the deck. This card no longer builds or removes grids
## itself -- each creator card's own `on_spotlight`/`on_unspotlight` does that.
func on_game_start() -> void:
	if not api or not api.is_live(): return
	var settings := SettingsManager.settings
	var target := target_grid_count(api.draw_deck().size(), settings.grid_cards_per_unlock,
			settings.grid_max_count)
	var creators := _creator_cards()
	while creators.size() < target:
		var card := CardData.new().with_skill(SkillGridCreator.new())
		api.add_rules_card(card)
		creators.append(card)
	while creators.size() > target:
		var card : CardData = creators.pop_back()
		var creator := card.skill as SkillGridCreator
		# Removing a rules-deck card takes it out of the walk the spotlight sweep would use to
		# catch the edge, so the removal fires on_unspotlight itself before the card is gone.
		if creator and creator.has_method(&"on_unspotlight"):
			await creator.on_unspotlight()
		api.remove_rules_card(card)
