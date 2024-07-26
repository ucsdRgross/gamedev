extends Resource
class_name CardData

signal data_changed

@export_enum("Clubs", "Spades", "Diamonds", "Hearts") var suit: int = 0:
	set(value):
		suit = value
		data_changed.emit()
@export var rank: int = 0:
	set(value):
		rank = value
		data_changed.emit()
var skill: CardModifier:
	set(value):
		skill = value
		data_changed.emit()
var type: CardModifier:
	set(value):
		type = value
		data_changed.emit()
var stamp: CardModifier:
	set(value):
		stamp = value
		data_changed.emit()
var card: Card

func with_suit(suit:int) -> CardData:
	self.suit = suit
	return self
	
func with_rank(rank:int) -> CardData:
	self.rank = rank
	return self

func with_skill(skill:CardModifier) -> CardData:
	self.skill = skill.with_data(self)
	return self

func with_type(type:CardModifier) -> CardData:
	self.type = type.with_data(self)
	return self

func with_stamp(stamp:CardModifier) -> CardData:
	self.stamp = stamp.with_data(self)
	return self
