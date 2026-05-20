class_name SkillEvalPokerBest
extends CardModifierSkill

func get_str() -> String:
	return "Poker Hand"
func get_description() -> String:
	return "Scores a hand with Poker rules"
func get_frame() -> int: return 8

func on_score_row(current_row : int) -> void:
	pass
