@abstract class_name CardModifierType
extends CardModifier

const type_texture : Texture2D = preload("res://Assets/card_types.png")

func set_texture(sprite:Sprite2D) -> void:
	sprite.texture = type_texture
	sprite.hframes = 8
	sprite.vframes = 8
	sprite.frame = get_frame()
