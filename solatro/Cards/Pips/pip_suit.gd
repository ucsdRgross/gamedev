@abstract class_name PipSuit
extends Resource

signal data_changed

var value : int:
	set(_value):
		value = _value
		data_changed.emit()
		
@abstract func get_str() -> String
@abstract func set_texture(sprite:Sprite2D) -> void
@abstract func set_art_texture(sprite:Sprite2D, rank:PipRank) -> void
@abstract func with_random() -> PipSuit

func with_value(i:int) -> PipSuit:
	value = i
	return self
		
func set_material(sprite:Sprite2D) -> void: sprite.material = null

class Standard extends PipSuit:
	const suit_texture : Texture2D = preload("res://Assets/suit_pips.png")
	const art_texture : Texture2D = preload("res://Assets/suit_art.png")
	const color_picker_shader = preload("res://Assets/color_picker.tres")
	const pallete_colors : Array[int] = [8,11,14,2]
	func get_str() -> String: return "Standard Suit"
	func set_texture(sprite:Sprite2D) -> void:
		sprite.texture = suit_texture
		sprite.hframes = 8
		sprite.vframes = 8
		sprite.frame = value - 1
		set_material(sprite)
	func set_material(sprite:Sprite2D) -> void:
		var material := ShaderMaterial.new()
		material.shader = color_picker_shader
		material.set_shader_parameter("color_x", pallete_colors[value-1])
		sprite.material = material

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
	func with_random() -> PipSuit:
		return with_value(randi_range(1,4))
