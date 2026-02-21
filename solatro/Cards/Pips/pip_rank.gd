@abstract class_name PipRank
extends Resource

signal data_changed

var name : StringName
var value : int:
	set(_value):
		value = _value
		data_changed.emit()
		
@abstract func set_texture(sprite:Sprite2D) -> void

func with_value(i:int) -> PipRank:
		value = i
		return self

class Numeral extends PipRank:
	const texture2D : Texture2D = preload("res://Assets/suits.png")
	var original_value : int
	func _init() -> void:
		name = "Numeral Rank"
	func set_texture(sprite:Sprite2D) -> void:
		sprite.texture = texture2D
		sprite.hframes = 14
		sprite.vframes = 5
		sprite.frame = value
	
	func with_random() -> void:
		return with_value(randi_range(1,13))
	
