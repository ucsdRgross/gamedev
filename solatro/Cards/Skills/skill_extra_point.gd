class_name SkillExtraPoint
extends CardModifier

func _init() -> void:
	name = "Extra Point"
	description = "Gain 1 Extra Point Per Score"
	frame = 52

func on_score(target:Card) -> void:
	if not is_active(): return
	if target.data == self.data and Game.CURRENT:
		var grid_pos := Game.CURRENT.get_card_grid_pos(target)
		await card_shake(add_points.bind(grid_pos.x, grid_pos.y))
		await Game.CURRENT.on_mod_triggered(self.data, on_score.bind(target))

func add_points(row:int, col:int) -> void:
	if not Game.CURRENT: return
	Game.CURRENT.row_add_score(row, 1)
	Game.CURRENT.col_add_score(col, 1)
	Game.CURRENT.total_score += 10
