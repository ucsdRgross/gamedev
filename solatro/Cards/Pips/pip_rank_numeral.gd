@tool
class_name PipRankNumeral
extends PipRank

const RANK_TEXTURE : Texture2D = preload("res://Assets/rank_pips.png")
const H_FRAMES: int = 13
const V_FRAMES: int = 5
@export_storage var original_value : float
## The rank as a player reads it: the numeral itself, or the court card's own name.
func get_str() -> String:
	match int(value):
		1: return TRANSLATION.find('RANK_ACE')
		11: return TRANSLATION.find('RANK_JACK')
		12: return TRANSLATION.find('RANK_QUEEN')
		13: return TRANSLATION.find('RANK_KING')
	return "%d" % int(value)
func set_texture(polygon2d:Polygon2D) -> void:
	CardOutline.frame_polygon(polygon2d, RANK_TEXTURE, H_FRAMES, V_FRAMES, value - 1)

func with_random() -> PipRank:
	return with_value(randi_range(1,13))
