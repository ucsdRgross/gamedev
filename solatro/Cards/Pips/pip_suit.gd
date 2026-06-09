@abstract class_name PipSuit
extends Resource

signal data_changed

@export var value : int:
	set(_value):
		value = _value
		data_changed.emit()
		
@abstract func get_str() -> String
@abstract func set_texture(polygon2d:Polygon2D) -> void
@abstract func set_art_texture(polygon2d:Polygon2D, rank:PipRank) -> void
@abstract func with_random() -> PipSuit

func with_value(i:int) -> PipSuit:
	value = i
	return self
		
func set_material(polygon2d:Polygon2D) -> void: polygon2d.material = null
