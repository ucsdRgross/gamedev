class_name SkillScorerCascadeLower
extends CardModifierSkill

func get_str() -> String:
	return "Cascade Scorer"
func get_description() -> String:
	return "Score each row in lower board"
func get_frame() -> int: return 7

## Engine scorer machinery (§15a): never a combo class — a constant U baseline every act.
func combo_key(_hook: StringName = &"") -> String: return ""

func on_run_scorer() -> void:
	if not game: return
	var zone := game.state.lower_zone
	var current_row : int = 0
	var current_col : int = 0
	while true:
		#Check row scores
		var is_row_empty := true
		for col in zone:
			if col.datas.size() > current_row:
				is_row_empty = false
				await game.run_all_mods(&"on_score_row", zone, current_row)
				break
		if is_row_empty: break
		current_row += 1
	while current_col < zone.size():
		#Check col scores
		var col : Array[CardData] = zone[current_col].datas
		await game.run_all_mods(&"on_score_col", zone, current_col)
		current_col += 1
