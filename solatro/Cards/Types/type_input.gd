class_name TypeInput
extends CardModifierType
	
func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_CARD_DESCRIPTION')
func get_frame() -> int: return 0

func on_can_place_stack(stack: Array[CardData], target: CardData) -> Array[CardData]:
	if target != data: return []
	var game_state := Game.CURRENT.state
	if Game.CURRENT.is_data_topmost(target): return stack
	return []

func on_next() -> void:
	await drop_card()
	await draw_card()

func drop_card() -> void:
	var game_state := Game.CURRENT.state
	var col : int = game_state.upper_zone_type.find(data)
	if col > -1 and game_state.upper_zone[col].datas.size() > 0:
		var upper_cards := game_state.upper_zone[col].datas
		await Game.CURRENT.move_data_to_coord(upper_cards[0], Vector3i(1,col,-1), -1)

func draw_card() -> void:
	var game_state := Game.CURRENT.state
	var col : int = game_state.upper_zone_type.find(data)
	if col > -1:
		var drawn_card := Game.CURRENT.draw_card()
		if drawn_card:
			game_state.upper_zone[col].datas.append(drawn_card)
