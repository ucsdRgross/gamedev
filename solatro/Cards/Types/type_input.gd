class_name TypeInput
extends CardModifierType
	
func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_CARD_DESCRIPTION')
func get_frame() -> int: return 0

func on_can_stack(stack : CardData, to_stack : CardData) -> bool:
	if stack == self:
		# get column of zone
		var col : int = Game.CURRENT.lower_zone_type.find(self)
		# if column of board is empty, return true
		if col > 0 and Game.CURRENT.lower_zone[col].datas.size() == 0:
			return true
	return false

func on_next() -> void:
	await drop_card()
	await draw_card()

func drop_card() -> void:
	var col : int = Game.CURRENT.upper_zone_type.find(self)
	if col > 0 and Game.CURRENT.upper_zone[col].datas.size() >= 0:
		var upper_cards := Game.CURRENT.upper_zone[col].datas
		await Game.CURRENT.move_data_to_coord(upper_cards[0], Vector3i(1,col,-1), -1)

func draw_card() -> void:
	var col : int = Game.CURRENT.upper_zone_type.find(self)
	if col > 0:
		var drawn_card := Game.CURRENT.draw_card()
		if drawn_card:
			Game.CURRENT.upper_zone[col].datas.append(drawn_card)
