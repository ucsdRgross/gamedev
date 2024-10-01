class_name CardModifier
#extends Resource

signal mod_triggered(card_data:CardData, mod:Callable)

#class Skill:
var name : String
var description : String
var frame : int
var data : CardData
var game : Game

func with_data(data:CardData) -> CardModifier:
	self.data = data
	return self

func with_game(game:Game) -> CardModifier:
	self.game = game
	return self

func on_round_start() -> void:
	pass
func on_round_end() -> void:
	pass
#func on_card_enter_game(target:Card) -> void:
	#pass
#func on_card_leave_game(target:Card) -> void:
	#pass
func stack_rule(target:Card) -> bool:
	return false
func on_stack(target:Card) -> void:
	pass
func pickup_rule(target:Card) -> bool:
	return true
func on_pickup(target:Card) -> void:
	pass
func on_submit(target:Card) -> void:
	pass
func on_card_click(target:Card) -> void:
	pass
func on_skill_activated(target:Card) -> void:
	pass
func score_rule() -> void:
	pass
func on_score(target:Card) -> void:
	pass
func on_game_start() -> void:
	pass
func on_game_win() -> void:
	pass
func on_game_loss() -> void:
	pass
func on_game_end() -> void:
	pass
func on_deck_enter(target:Card) -> void:
	pass
func on_discard(target:Card) -> void:
	pass
func on_delete(target:Card) -> void:
	pass
func on_draw(target:Card) -> void:
	pass
func on_deck_shuffle() -> void:
	pass
	
func is_card_on_top() -> bool:
	return true
	
func on_trigger(data:CardData, mod:Callable) -> void:
	pass

func card_shake(card_effect:Callable) -> void:
	if data.card:
		await game.shake_card(data.card, card_effect)
