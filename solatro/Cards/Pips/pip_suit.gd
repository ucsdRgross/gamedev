@abstract class_name PipSuit
extends Resource

signal data_changed

var name : StringName
var value : int:
	set(_value):
		value = _value
		data_changed.emit()

@abstract func set_texture(sprite:Sprite2D) -> void
@abstract func set_art_texture(sprite:Sprite2D, rank:PipRank) -> void

func with_value(i:int) -> PipSuit:
		value = i
		return self
		
func set_material(sprite:Sprite2D) -> void: sprite.material = null

class Standard extends PipSuit:
	const suit_texture : Texture2D = preload("res://Assets/suits.png")
	const art_texture : Texture2D = preload("res://Assets/card_art.png")
	func _init() -> void:
		name = "Standard Suit"
	func set_texture(sprite:Sprite2D) -> void:
		sprite.texture = suit_texture
		sprite.hframes = 14
		sprite.vframes = 5
		sprite.frame = 14 * (value - 1)
		set_material(sprite)
	func set_art_texture(sprite:Sprite2D, rank:PipRank) -> void:
		if rank is PipRank.Numeral:
			sprite.texture = art_texture
			sprite.hframes = 13
			sprite.vframes = 13
			var numeral : PipRank.Numeral = rank
			sprite.frame = 13 * (value - 1) + (numeral.value - 1)
		else:
			sprite.texture = null
		set_material(sprite)
	func with_random() -> void:
		return with_value(randi_range(1,4))
