@abstract
class_name ZoneAdder
extends CardModifierSkill

#func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD')
#func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_LOWER_ADDER_CARD_DESCRIPTION')
#func get_frame() -> int: return 0

@export_storage var card_data : CardData

@abstract
func card_data_to_add() -> CardData
@abstract
func get_zone() -> Array[ArrayCardData]
@abstract
func get_zone_type() -> Array[CardData]

func on_active() -> void:
	var game : Game = CardEnvironment.CURRENT if CardEnvironment.CURRENT is Game else null
	if not game: return
	if not card_data:
		card_data = card_data_to_add()
	card_data.stage = CardData.Stage.ZONE
	get_zone_type().append(card_data)
	get_zone().append(ArrayCardData.new())
	
func on_deactive() -> void:
	var game : Game = CardEnvironment.CURRENT if CardEnvironment.CURRENT is Game else null
	if not game: return
	var index := get_zone_type().find(card_data)
	get_zone_type().remove_at(index)
	var datas : Array[CardData] = get_zone().pop_at(index).datas
	for d : CardData in datas:
		await game.discard_data(d)
	card_data = null
		
