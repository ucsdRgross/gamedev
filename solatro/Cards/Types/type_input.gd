class_name TypeInput
extends CardModifierType
	
func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_CARD_DESCRIPTION')
func get_frame() -> int: return 2

## Engine zone-header machinery (§15a): the input row's refill fires whenever the Entrance is
## due one — never a combo class (would be a constant U baseline). Not in rules1 itself, but
## the same opt-out reasoning as the rules cards that are.
func combo_key(_hook: StringName = &"") -> String: return ""

func on_can_place_stack(stack: Array[CardData], target: CardData) -> Array[CardData]:
	if target != data: return []
	if not api or not api.is_live(): return []
	if api.is_data_topmost(target): return stack
	return []

## Answers a refill event by filling this header's own slot, if it is empty. The DECISION to
## refill is not made here -- it is a property of the whole Entrance and is taken once, before
## this broadcast. Left to right falls out of the order these headers are dispatched in.
func on_refill() -> void:
	if not api or not api.is_live(): return
	var col : int = api.upper_zone_type().find(data)
	if col == -1 or col >= api.upper_zone().size(): return
	if api.upper_zone()[col].datas.size() > 0: return
	var drawn_card := api.draw_card()
	if drawn_card:
		api.place_card(drawn_card, 0, col)
