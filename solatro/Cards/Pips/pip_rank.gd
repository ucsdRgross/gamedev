@abstract class_name PipRank
extends Resource

signal data_changed

var value : int:
	set(_value):
		value = _value
		data_changed.emit()
		
@abstract func get_str() -> String
@abstract func set_texture(sprite:Sprite2D) -> void
@abstract func with_random() -> PipRank

func with_value(i:int) -> PipRank:
	value = i
	return self

class Numeral extends PipRank:
	const texture2D : Texture2D = preload("res://Assets/rank_pips.png")
	var original_value : int
	func get_str() -> String: return "Numeral Rank"
	func set_texture(sprite:Sprite2D) -> void:
		sprite.texture = texture2D
		sprite.hframes = 13
		sprite.vframes = 5
		sprite.frame = value - 1
	
	func with_random() -> PipRank:
		return with_value(randi_range(1,13))
	
