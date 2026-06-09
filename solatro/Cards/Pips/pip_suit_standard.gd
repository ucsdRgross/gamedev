@tool
class_name PipSuitStandard
extends PipSuit

const SUIT_TEXTURE : Texture2D = preload("res://Assets/suit_pips.png")
const SUIT_TEXTURE_H_FRAMES: int = 8
const SUIT_TEXTURE_V_FRAMES: int = 8
const ART_TEXTURE = preload("res://Assets/suit_art.png")
const ART_TEXTURE_H_FRAMES: int = 13
const ART_TEXTURE_V_FRAMES: int = 13
const color_picker_shader = preload("res://Assets/color_picker.tres")
const pallete_colors : Array[int] = [8,11,14,2]
func get_str() -> String: return "StandardSuit" + str(value)
func set_texture(polygon2d:Polygon2D) -> void:
	CardModifier.update_polygon_uv_frame(polygon2d, SUIT_TEXTURE, SUIT_TEXTURE_H_FRAMES, SUIT_TEXTURE_V_FRAMES, value - 1)
	set_material(polygon2d)
func set_material(polygon2d:Polygon2D) -> void:
	var material := ShaderMaterial.new()
	material.shader = color_picker_shader
	material.set_shader_parameter("color_x", pallete_colors[value-1])
	polygon2d.material = material

func set_art_texture(polygon2d:Polygon2D, rank:PipRank) -> void:
	if rank is PipRankNumeral:
		var numeral : PipRankNumeral = rank
		CardModifier.update_polygon_uv_frame(
			polygon2d, ART_TEXTURE, ART_TEXTURE_H_FRAMES, ART_TEXTURE_V_FRAMES, 13 * (value - 1) + (numeral.value - 1))			
	else:
		polygon2d.texture = null
	set_material(polygon2d)
func with_random() -> PipSuit:
	return with_value(randi_range(1,4))
