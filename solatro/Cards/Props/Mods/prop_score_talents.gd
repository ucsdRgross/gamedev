class_name PropScoreTalents
extends PropModifier
## Hoop effect: on passing a TALENTED card (one carrying a skill), bank `points` into that
## card's row gutter. Talents jump through the hoop and score; plain cards are ignored.

var points : int

func _init(p := 1) -> void:
	points = p

func on_pass_card(_prop: PropData, g: Game, card: CardData) -> void:
	if card.skill:   # talent PRESENCE (not .active — covered talents still count)
		var v := g.find_data_vec3(card)
		if v == Vector3i.MIN: return
		g.add_line_score(true, g.row_gutter(v), v.z, points)

func reaction_for(_prop: PropData, card: CardData) -> int:
	return PropData.Reaction.JUMP if card.skill else PropData.Reaction.NONE
