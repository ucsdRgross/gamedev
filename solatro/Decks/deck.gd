extends Resource
class_name Deck



var deck1: Array[CardData] = [
	CardData.new().with_suit(1).with_rank(1),
	CardData.new().with_suit(2).with_rank(1),
	CardData.new().with_suit(3).with_rank(1),
	CardData.new().with_suit(4).with_rank(1),
	CardData.new().with_suit(1).with_rank(2),
	CardData.new().with_suit(2).with_rank(2),
	CardData.new().with_suit(3).with_rank(2),
	CardData.new().with_suit(4).with_rank(2),
	]

var deck2: Array[CardData] = [
	CardData.new().with_suit(1).with_rank(1),
	CardData.new().with_suit(2).with_rank(2),
	CardData.new().with_suit(3).with_rank(3),
	CardData.new().with_suit(4).with_rank(4),
	CardData.new().with_suit(1).with_rank(4),
	CardData.new().with_suit(2).with_rank(3),
	CardData.new().with_suit(3).with_rank(2),
	CardData.new().with_suit(4).with_rank(1),
	]

var deck3: Array[CardData] = [
	CardData.new().with_suit(1).with_rank(1).with_skill(CardSkill.ExtraPoint.new()),
	CardData.new().with_suit(2).with_rank(2).with_stamp(CardStamp.Revealing.new()),
	CardData.new().with_suit(3).with_rank(3).with_type(CardType.Heavy.new()),
	CardData.new().with_suit(4).with_rank(4).with_skill(CardSkill.ExtraPoint.new()).with_stamp(CardStamp.Revealing.new()),
	CardData.new().with_suit(1).with_rank(4).with_skill(CardSkill.ExtraPoint.new()).with_type(CardType.Heavy.new()),
	CardData.new().with_suit(2).with_rank(3).with_stamp(CardStamp.Revealing.new()).with_type(CardType.Heavy.new()),
	CardData.new().with_suit(3).with_rank(2),
	CardData.new().with_suit(4).with_rank(1),
	CardData.new().with_suit(1).with_rank(1).with_skill(CardSkill.ExtraPoint.new()),
	CardData.new().with_suit(2).with_rank(2).with_stamp(CardStamp.Revealing.new()),
	CardData.new().with_suit(3).with_rank(3).with_type(CardType.Heavy.new()),
	CardData.new().with_suit(4).with_rank(4).with_skill(CardSkill.ExtraPoint.new()).with_stamp(CardStamp.Revealing.new()),
	CardData.new().with_suit(1).with_rank(4).with_skill(CardSkill.ExtraPoint.new()).with_type(CardType.Heavy.new()),
	CardData.new().with_suit(2).with_rank(3).with_stamp(CardStamp.Revealing.new()).with_type(CardType.Heavy.new()),
	CardData.new().with_suit(3).with_rank(2),
	CardData.new().with_suit(4).with_rank(1),
	]

var deck4: Array[CardData] = [
	CardData.new().with_suit(1).with_rank(1),
	CardData.new().with_suit(1).with_rank(1),
	CardData.new().with_suit(1).with_rank(1),
	CardData.new().with_suit(1).with_rank(1),
	CardData.new().with_suit(1).with_rank(1),
	]

@export var card_datas : Array[CardData] = deck4
