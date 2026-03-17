@abstract class_name CardModifierStamp
extends CardModifier

const stamp_texture : Texture2D = preload("res://Assets/stamp_pips.png")

func set_texture(sprite:Sprite2D) -> void:
	sprite.texture = stamp_texture
	sprite.hframes = 8
	sprite.vframes = 8
	sprite.frame = get_frame()
