class_name CardData
extends Resource

signal data_changed
signal stage_changed

@export var suit: PipSuit:
	set(value):
		if suit and suit.data_changed.is_connected(_on_child_data_changed):
			suit.data_changed.disconnect(_on_child_data_changed)
		suit = value
		if suit:
			suit.data_changed.connect(_on_child_data_changed)
		data_changed.emit()
@export var rank: PipRank:
	set(value):
		if rank and rank.data_changed.is_connected(_on_child_data_changed):
			rank.data_changed.disconnect(_on_child_data_changed)
		rank = value
		if rank:
			rank.data_changed.connect(_on_child_data_changed)
		data_changed.emit()
@export var skill: CardModifierSkill:
	set(value):
		skill = value
		data_changed.emit()
@export var type: CardModifierType:
	set(value):
		type = value
		data_changed.emit()
@export var stamp: CardModifierStamp:
	set(value):
		stamp = value
		data_changed.emit()
@export var statuses: Array[CardModifierStatus] = []
@export var flipped := false
enum Stage {PLAY, DRAW, DISCARD, RULES, ZONE, DATA}
@export var stage : Stage = Stage.PLAY:
	set(value):
		previous_stage = stage
		stage = value
		stage_changed.emit()
@export_storage var previous_stage : Stage = Stage.PLAY

func with_suit(suit:PipSuit) -> CardData:
	self.suit = suit.with_data(self) if suit else null
	return self
	
func with_rank(rank:PipRank) -> CardData:
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

## Apply a status: merge into an existing same-class status (stacks add) or append a fresh
## copy. S7 trap: a status arriving already bound to another card is duplicated so the two
## cards never share one stacks/data.
func add_status(status: CardModifierStatus) -> void:
	for existing: CardModifierStatus in statuses:
		if existing.can_merge_with(status):
			existing.stacks += status.stacks   # setter emits data_changed
			return
	if status.data != null and status.data != self:
		status = status.duplicate() as CardModifierStatus
	statuses.append(status.with_data(self))
	data_changed.emit()

func remove_status(status: CardModifierStatus) -> void:
	statuses.erase(status)
	data_changed.emit()

func with_status(status: CardModifierStatus) -> CardData:
	add_status(status)
	return self

func _on_child_data_changed() -> void:
	data_changed.emit()

func _to_string() -> String:
	var s : String
	if suit: s += suit.get_str()
	if rank: s += " " + rank.get_str()
	if skill: s += " " + skill.get_str()
	if type: s += " " + type.get_str()
	if stamp: s += " " + stamp.get_str()
	for status: CardModifierStatus in statuses:
		s += " " + status.get_str() + "x" + str(status.stacks)
	if s: s += " "
	s += Stage.find_key(stage) + " " + Stage.find_key(previous_stage)
	return s
