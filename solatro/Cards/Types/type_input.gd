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

func on_next() -> void:
	await drop_card()
	await draw_card()

func drop_card() -> void:
	if not api or not api.is_live(): return
	var upper := api.upper_zone()
	var lower := api.lower_zone()
	var col : int = api.upper_zone_type().find(data)
	#no-op unless a matching lower column exists (upper col i is assumed paired with lower col i)
	if col > -1 and col < upper.size() and col < lower.size() \
			and upper[col].datas.size() > 0:
		await api.move_data_to_coord(upper[col].datas[0], Vector3i(1, col, -1), -1)

func draw_card() -> void:
	if not api or not api.is_live(): return
	var col : int = api.upper_zone_type().find(data)
	if col > -1 and col < api.upper_zone().size():
		var drawn_card := api.draw_card()
		if drawn_card:
			api.place_card(drawn_card, 0, col)
