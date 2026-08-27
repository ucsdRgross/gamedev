class_name TypeInput
extends CardModifierType
	
func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_CARD_DESCRIPTION')
func get_frame() -> int: return 2

## Engine zone-header machinery (§15a): the input row's on_next fires every act — never a
## combo class (would be a constant U baseline). Not in rules1, but same opt-out reasoning.
func combo_key(_hook: StringName = &"") -> String: return ""

func on_can_place_stack(stack: Array[CardData], target: CardData) -> Array[CardData]:
	if target != data: return []
	if not api or not api.is_live(): return []
	if api.is_data_topmost(target): return stack
	return []

## ⚠ SCAFFOLDING, NOT THE DESIGN. The design retires this handler outright: the Entrance
## refills from board state (below), never from a Next. It survives only because the LEGACY
## tableau deal — drop this header's column into the paired lower column, then draw — is what
## six suites still use to put cards on a board at all, and the tableau is not archived yet.
## Deleting it early leaves those suites with no board to test against.
## It is a no-op once there is no paired lower column, which is what the archive produces.
func on_next() -> void:
	await _legacy_drop_to_lower()

## The legacy tableau drop. Goes with the tableau.
func _legacy_drop_to_lower() -> void:
	if not api or not api.is_live(): return
	var upper := api.upper_zone()
	var lower := api.lower_zone()
	var col : int = api.upper_zone_type().find(data)
	if col > -1 and col < upper.size() and col < lower.size() 			and upper[col].datas.size() > 0:
		await api.move_data_to_coord(upper[col].datas[0], Vector3i(1, col, -1), -1)

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
