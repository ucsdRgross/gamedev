@tool
class_name CardData
extends Resource
## ⚠ `@tool` BECAUSE THE FX EDITOR PREVIEWS A REAL CARD, and a class whose chain is not `@tool` loads in
## the editor as a PLACEHOLDER: the type name survives and every member does not. Measured 2026-07-29 in
## the owner's editor — *"Invalid access to property or key 'data_changed' on a base object of type
## 'Resource (CardData)'"*, and a `PipSuitHoop` that came back as a bare `Resource` with no
## `set_texture`. Nothing here needs a running game (the `_init` registry is a weakref, the setters only
## emit), so the flag costs nothing and it is what lets a tool stand up the card the player sees rather
## than a mock of one. THE WHOLE CHAIN HAS TO CARRY IT: CardModifier, CardModifierType, PipSuit, PipRank.

signal data_changed
signal stage_changed

# LeakSentinel registry: every card ever built, held WEAKLY (debug builds only — zero
# release cost). LeakSentinel prunes dead entries and compares the survivors against the
# cards reachable from legitimate owners; see Scripts/leak_sentinel.gd.
static var sentinel_registry : Array[WeakRef] = []

func _init() -> void:
	if OS.is_debug_build():
		sentinel_registry.append(weakref(self))

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
			# Not `stacks +=`: a status carrying per-stack data must extend it in the SAME
			# operation, which is what merge_from exists for. The stacks setter still emits
			# data_changed.
			existing.merge_from(status)
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

## **THE COMPACT FORM, FOR LOGS.** `Hoop NumeralRank1.0 Extra Point  PLAY PLAY` becomes `Ho1*+`.
## Owner, 2026-08-04: *"Logs should be as compact as possible, current card data to_str may need
## changes."* A log line repeated thousands of times is mostly card identifiers, and the verbose form
## also prints the stage TWICE, which is pure noise in a per-frame record.
##
## ⚠ **THIS IS A SECOND METHOD RATHER THAN AN EDIT TO `_to_string()`, DELIBERATELY.** `_to_string()`
## feeds test assertions and the **G1.7 headless-parity diff**, which compares whole log sections
## between two runs — shortening it would either break those or, worse, change what the parity gate
## compares without anyone noticing. The verbose form stays exactly as it is for those readers.
##
## Shape: `<suit 2 chars><rank><flags>`, e.g. `Kn3sR` = Knife, rank 3, Stone, Revealing. Stage is
## appended ONLY when it is not `PLAY`, since almost every logged card is on the board.
func log_str() -> String:
	var s := ""
	if suit: s += suit.get_str().substr(0, 2)
	if rank: s += rank.get_str().trim_suffix(".0")
	# One character per modifier, because WHICH skill it is almost never matters in a log line —
	# that it HAS one is what changes behaviour, and the verbose form is one call away when it does.
	if skill: s += "*"
	if stamp: s += "+"
	if type and not type.get_str().is_empty(): s += "^"
	if not statuses.is_empty(): s += "#%d" % statuses.size()
	if stage != Stage.PLAY: s += "/" + Stage.find_key(stage)
	return s

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
