@tool
@abstract class_name PipRank
extends Resource

signal data_changed

@export var value : float:
	set(_value):
		value = _value
		data_changed.emit()
		
@abstract func get_str() -> String
## What a rank means to the player, one line every rank shares.
func get_description() -> String: return TRANSLATION.find('RANK_DESCRIPTION')
@abstract func set_texture(polygon2d:Polygon2D) -> void
@abstract func with_random() -> PipRank

func with_value(i:float) -> PipRank:
	value = i
	return self

	
