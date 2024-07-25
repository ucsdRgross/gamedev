extends Resource
class_name CardData

@export_enum("Clubs", "Spades", "Diamonds", "Hearts") var suit: int = 0
@export var rank: int = 0
var card: Card
var skill: CardModifier
var type: CardModifier
var stamp: CardModifier
#@export var ability: 
#@export var type: 
#@export var effect: String = ""
#@export var sprite: Texture

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
