class_name PropScoreProps
extends PropModifier
## Knife effect: on passing a PLAIN card (no skill — a "prop"), bank `points` into that card's
## row gutter. Talents spin the knife aside and are NOT scored (the mirror of PropScoreTalents).

var points : int

func _init(p := 1) -> void:
	points = p

func on_pass_card(_prop: PropData, g: Game, card: CardData) -> void:
	if not card.skill:
		var v := g.state.grid_position_of(card)
		if v.is_nowhere(): return
		g.register_combo(combo_key())   # §15a: prop score effects self-register at their seam
		var section : ScoringSection
		if v.is_entrance():
			section = ScoringSection.of_line(g.state.upper_zone, true, v.h)
		else:
			section = ScoringSection.of_line_at(g.state, v.grid, ScoringSection.LineKind.ROW, v.y, v.h)
		g.add_line_score(section, points)

func reaction_for(_prop: PropData, card: CardData) -> int:
	return PropData.Reaction.SPIN if card.skill else PropData.Reaction.NONE
