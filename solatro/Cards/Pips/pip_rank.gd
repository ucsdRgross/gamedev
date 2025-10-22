@abstract class_name PipRank
extends Resource

@abstract func set_texture(sprite:Sprite2D) -> void

class Numeral extends PipRank:
	const texture2D : Texture2D = preload("res://Assets/suits.png")
	var original_value : int
	var value : int
	func set_texture(sprite:Sprite2D) -> void:
		pass
	
