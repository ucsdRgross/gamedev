class_name CardData
extends Resource

signal data_changed

@export var suit: int = 1:
	set(value):
		suit = value
		data_changed.emit()
@export var rank: int = 1:
	set(value):
		rank = value
		data_changed.emit()
@export var skill: CardModifier:
	set(value):
		skill = value
		data_changed.emit()
@export var type: CardModifier:
	set(value):
		type = value
		data_changed.emit()
@export var stamp: CardModifier:
	set(value):
		stamp = value
		data_changed.emit()
var card: Card
var game: Game
enum Stage {DRAW, INPUT, PLAY, DISCARD, SPACE}
@export_storage var stage := Stage.SPACE
enum {IN_PLAY, STATIC}
@export_storage var state := IN_PLAY

func with_suit(suit:int) -> CardData:
	self.suit = suit
	return self
	
func with_rank(rank:int) -> CardData:
	self.rank = rank
	return self

func with_skill(skill:CardModifier) -> CardData:
	if skill:
		self.skill = skill.with_data(self)
	else:
		self.skill = null
	return self

func with_type(type:CardModifier) -> CardData:
	if type:
		self.type = type.with_data(self)
	else:
		self.type = null
	return self

func with_stamp(stamp:CardModifier) -> CardData:
	if stamp:
		self.stamp = stamp.with_data(self)
	else:
		self.stamp = null
	return self
	
func clone(deep:bool = false) -> CardData:
	var data := CardData.new()
	data.suit = self.suit
	data.rank = self.rank
	if self.skill:
		data.with_skill(self.skill.duplicate(deep) as CardModifier)
	if self.type:
		data.with_type(self.type.duplicate(deep) as CardModifier)
	if self.stamp:
		data.with_stamp(self.stamp.duplicate(deep) as CardModifier)
	#card
	return data
