class_name PlayerSave
extends Resource

@export var card_datas : Array

@warning_ignore("untyped_declaration")
func write_card_data(data) -> void:
	card_datas.append(data)

func read_card_data() -> Array:
	return card_datas
