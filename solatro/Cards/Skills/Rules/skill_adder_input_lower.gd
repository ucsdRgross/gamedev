class_name SkillAdderInputLower
extends ZoneAdder

func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD_DESCRIPTION')
func get_frame() -> int: return 4

func card_data_to_add() -> CardData:
	return CardData.new().with_type(TypeInput.new())
func get_zone() -> Array[ArrayCardData]:
	if not game: return [] 
	return game.state.lower_zone
func get_zone_type() -> Array[CardData]:
	if not game: return [] 
	return game.state.lower_zone_type
