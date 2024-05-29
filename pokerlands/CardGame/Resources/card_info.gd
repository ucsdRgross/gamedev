extends Resource
class_name CardInfo

@export var rank : int
@export var suit : int
@export var ability : CardAbility

func _init(rank:int=0, suit:int=0, ability:CardAbility=CardAbility.new()) -> void:
	self.rank = rank
	self.suit = suit
	self.ability = ability
