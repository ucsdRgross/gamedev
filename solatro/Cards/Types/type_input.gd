class_name TypeInput
extends CardModifierType
	
func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_CARD_DESCRIPTION')
func get_frame() -> int: return 0

func on_can_place_stack(stack: Array[CardData], target: CardData) -> Array[CardData]:
	if target != data: return []
	var game := CardEnvironment.get_current_game()
	if not game: return []
	var game_state := game.state
	if game.is_data_topmost(target): return stack
	return []

func on_next() -> void:
	await drop_card()
	await draw_card()

func drop_card() -> void:
	var game := CardEnvironment.get_current_game()
	if not game: return
	var game_state := game.state
	var col : int = game_state.upper_zone_type.find(data)
	if col > -1 and game_state.upper_zone[col].datas.size() > 0:
		var upper_cards := game_state.upper_zone[col].datas
		await game.move_data_to_coord(upper_cards[0], Vector3i(1,col,-1), -1)

func draw_card() -> void:
	var game : Game = CardEnvironment.CURRENT if CardEnvironment.CURRENT is Game else null
	if not game: return
	var game_state := game.state
	var col : int = game_state.upper_zone_type.find(data)
	if col > -1:
		var drawn_card := game.draw_card()
		if drawn_card:
			game_state.upper_zone[col].datas.append(drawn_card)
