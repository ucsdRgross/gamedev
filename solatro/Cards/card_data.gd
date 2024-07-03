extends Resource
class_name CardData

@export_enum("Clubs", "Spades", "Diamonds", "Hearts") var suit: int = 0
@export var rank: int = 0
#@export var effect: String = ""
#@export var sprite: Texture

func with_suit(s:int) -> CardData:
	self.suit = s
	return self
	
func with_rank(r:int) -> CardData:
	self.rank = r
	return self
