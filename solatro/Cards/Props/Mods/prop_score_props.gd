class_name PropScoreProps
extends PropModifier
## Knife effect: on passing a PLAIN card (no skill — a "prop"), bank `points` into that card's
## row gutter. Talents spin the knife aside and are NOT scored (the mirror of PropScoreTalents).

var points : int

func _init(p := 1) -> void:
	points = p

func on_pass_card(_prop: PropData, g: Game, card: CardData) -> void:
	if not card.skill:
		var v := g.find_data_vec3(card)
		if v == Vector3i.MIN: return
		g.register_combo(combo_key())   # §15a: prop score effects self-register at their seam
		g.add_line_score(true, g.row_gutter(v), v.z, points)

func reaction_for(_prop: PropData, card: CardData) -> int:
	return PropData.Reaction.SPIN if card.skill else PropData.Reaction.NONE
