@tool
class_name SkillExtraPoint
extends CardModifierSkill

func get_str() -> String: return "Extra Point"
func get_description() -> String: return "Gain 1 Extra Point Per Score"
func get_frame() -> int: return 0

func on_score(target:CardData) -> void:
	if not is_active(): return
	# P7 fix (2026-07-16): was `data == self.data` — comparing the field to itself, always
	# true, so EVERY scored card anywhere announced a trigger from every active ExtraPoint.
	# The skill triggers only when ITS OWN card is the one scored, per its description.
	if target == self.data and CardEnvironment.CURRENT:
		#var grid_pos := CardEnvironment.CURRENT.get_card_grid_pos(target)
		#await card_shake(add_points.bind(grid_pos.x, grid_pos.y))
		await CardEnvironment.CURRENT.on_mod_triggered(self.data, on_score.bind(target))

func add_points(row:int, col:int) -> void:
	if not game: return
	#CardEnvironment.CURRENT.row_add_score(row, 1)
	#CardEnvironment.CURRENT.col_add_score(col, 1)
	game.state.total_score += 10
