class_name CardSkill
#extends Resource

#class Skill:
enum {SCORE, SUBMIT}
var name : String
var description : String
var image : Texture2D
var data : CardData

func with_data(data:CardData) -> CardSkill:
	self.data = data
	return self
	
func apply_skill(game:Game, target:Card, state:int) -> void:
	pass

class ExtraPoint extends CardSkill:
	func _init() -> void:
		name = "Extra Point"
		description = "Gain 1 Extra Point Per Score"

