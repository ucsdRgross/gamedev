class_name SkillInputAdderUpper
extends ZoneCardAdder

func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_UPPER_ADDER_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_UPPER_ADDER_CARD_DESCRIPTION')
func get_frame() -> int: return 3

func card_data_to_add() -> CardData:
	return CardData.new().with_type(TypeInput.new())
func get_zone() -> Array[ArrayCardData]:
	return Game.CURRENT.state.upper_zone
func get_zone_type() -> Array[CardData]:
	return Game.CURRENT.state.upper_zone_type
