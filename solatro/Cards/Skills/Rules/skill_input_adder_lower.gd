class_name SkillInputAdderLower
extends CardModifierSkill

func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD_DESCRIPTION')
func get_frame() -> int: return 0

func on_active() -> void:
	var new_data := CardData.new().with_type(TypeInput.new())
	new_data.stage = CardData.Stage.ZONE
	Game.CURRENT.lower_zone_type.append(new_data)
	Game.CURRENT.lower_zone.append(ArrayCardData.new())
	
func on_deactive() -> void:
	Game.CURRENT.lower_zone_type.pop_back()
	var datas : Array[CardData] = Game.CURRENT.lower_zone.pop_back().datas
	for d : CardData in datas:
		await Game.CURRENT.discard_data(d)
