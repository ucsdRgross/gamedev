class_name CardSkill
extends Resource

class ExtraPoint extends CardModifier:
	func _init() -> void:
		name = "Extra Point"
		description = "Gain 1 Extra Point Per Score"
		frame = 52
	
	func on_score(target:Card) -> void:
		if target.data == self.data:
			var grid_pos := game.get_card_grid_pos(target)
			await card_shake(add_points.bind(grid_pos.x, grid_pos.y))
			await game.on_mod_triggered(self.data, on_score.bind(target))
	
	func add_points(row:int, col:int) -> void:
		game.row_add_score(row, 1)
		game.col_add_score(col, 1)
		game.total_score += 10

class EchoingTrigger extends CardModifier:
	func _init() -> void:
		name = "Echoing Trigger"
		description = "ALL triggers repeat once"
		frame = 53
	
	var triggered : Array[CardData]
	func on_trigger(data:CardData, mod:Callable) -> void:
		if data not in triggered and data.skill:
			triggered.append(data)
			card_raise()
			await mod.call()
			card_lower()	
			#await game.on_mod_triggered(self.data, on_trigger.bind(data, mod))
			
	func after_score() -> void:
		triggered.clear()
