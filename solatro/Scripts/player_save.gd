class_name PlayerSave
extends Resource

#Only variables with @export are saved
@export var card_datas : Array[CardData]
@export var layer : int = 0

func write_card_data(data: CardData) -> void:
	card_datas.append(data)
	
func read_card_data() -> Array[CardData]:
	return card_datas
