class_name SkillExtraPoint
extends CardModifierSkill

func get_str() -> String: return "Extra Point"
func get_description() -> String: return "Gain 1 Extra Point Per Score"
func get_frame() -> int: return 0

func on_score(target:Card) -> void:
	if not is_active(): return
	if target.data == self.data and Game.CURRENT:
		#var grid_pos := Game.CURRENT.get_card_grid_pos(target)
		#await card_shake(add_points.bind(grid_pos.x, grid_pos.y))
		await Game.CURRENT.on_mod_triggered(self.data, on_score.bind(target))

func add_points(row:int, col:int) -> void:
	if not Game.CURRENT: return
	#Game.CURRENT.row_add_score(row, 1)
	#Game.CURRENT.col_add_score(col, 1)
	Game.CURRENT.total_score += 10
