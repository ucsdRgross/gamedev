@abstract class_name CardModifierSkill
extends CardModifier

const skill_texture : Texture2D = preload("res://Assets/skill_art.png")
@export var active := false

func set_texture(sprite:Sprite2D) -> void:
	sprite.texture = skill_texture
	sprite.hframes = 16
	sprite.vframes = 16
	sprite.frame = get_frame()
