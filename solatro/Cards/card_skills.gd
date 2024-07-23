class_name CardSkill
#extends Resource

#class Skill:
enum {SCORE, SUBMIT}
var name : String
var description : String
var frame : int
var data : CardData
var game : Game

func with_data(data:CardData) -> CardSkill:
	self.data = data
	return self

func with_game(game:Game) -> CardSkill:
	self.game = game
	return self

func on_enter() -> void:
	pass
func stack_rule(target:Card) -> bool:
	return false
func on_stack() -> void:
	pass
func pickup_rule(target:Card) -> bool:
	return true
func on_pickup(target:Card) -> void:
	pass
func on_submit(target:Card) -> void:
	pass
func score_rule() -> void:
	pass
func on_score(target:Card) -> void:
	pass
func on_leave(target:Card) -> void:
	pass
	
func can_skill() -> bool:
	return true
func on_trigger() -> void:
	pass


#func apply_skill(game:Game, target:Card, state:int) -> void:
	#pass

class ExtraPoint extends CardSkill:
	func _init() -> void:
		name = "Extra Point"
		description = "Gain 1 Extra Point Per Score"
		frame = 52

