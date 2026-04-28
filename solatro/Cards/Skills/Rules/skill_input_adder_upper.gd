class_name SkillInputAdderUpper
extends CardModifierSkill

func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_UPPER_ADDER_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_UPPER_ADDER_CARD_DESCRIPTION')
func get_frame() -> int: return 0

func on_active() -> void:
	var new_data := CardData.new().with_type(TypeInput.new())
	new_data.stage = CardData.Stage.ZONE
	Game.CURRENT.upper_zone_type.append(new_data)
	Game.CURRENT.upper_zone.append(ArrayCardData.new())
	
func on_deactive() -> void:
	Game.CURRENT.upper_zone_type.pop_back()
	var datas : Array[CardData] = Game.CURRENT.upper_zone.pop_back().datas
	for d : CardData in datas:
		await Game.CURRENT.discard_data(d)
