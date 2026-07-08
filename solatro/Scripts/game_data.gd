class_name GameData
extends Resource

signal state_changed
signal board_changed

#Bumped by every board mutation (Board.*, draw, discard, add_deck, shuffle) AFTER the
#state is consistent again. The setter emits board_changed (drives the UI rebuild) and
#the counter keys CardEnvironment's compare-mod cache (SE1).
#See Board's MUTATION GUIDELINES before adding any new mutation path.
var revision : int = 0:
	set(value):
		revision = value
		board_changed.emit()

@export_storage var goal : int = 100:
	set(value):
		goal = value
		state_changed.emit()
@export_storage var total_score : int = 0:
	set(value):
		total_score = value
		state_changed.emit()
@export_storage var mult_score : int = 0:
	set(value):
		mult_score = value
		state_changed.emit()
@export_storage var col_total : int = 0:
	set(value):
		col_total = value
		state_changed.emit()
@export_storage var row_total : int = 0:
	set(value):
		row_total = value
		state_changed.emit()

## One act's payout (DESIGN_DOC §2): the act's accumulated row and column totals multiply
## into mult_score, which is added to total_score; the totals reset for the next act.
## Note: an act with no scored columns (or rows) pays 0 — both sides must score.
func apply_act_score() -> void:
	mult_score = row_total * col_total
	total_score += mult_score
	row_total = 0
	col_total = 0
	# Clear the per-row/col score gutters too, so the NEXT act starts from zero. Without this
	# the BigNumber accumulators (scores_row_*/scores_col) keep growing and the next act's
	# plus_equals stacks onto the previous act's values. The UI gutters resync from these
	# empty arrays via PlayArea.update_score_controls (see Game._perform_submit).
	scores_row_upper.clear()
	scores_row_lower.clear()
	scores_col.clear()

## Move every lower-zone card to the discard pile — the performed cards of an act. The
## upper (Entrance) zone is intentionally left intact (DESIGN_DOC §2). Bumps revision so
## the play area rebuilds.
func discard_lower_board() -> void:
	for col in lower_zone:
		for data in col.datas:
			data.stage = CardData.Stage.DISCARD
			discard_deck.append(data)
		col.datas.clear()
	revision += 1

## The fame requirement for this show has been reached.
func has_met_goal() -> bool:
	return total_score >= goal

@export_storage var draw_deck : Array[CardData]
@export_storage var discard_deck : Array[CardData]
@export_storage var rules_deck : Array[CardData]
@export_storage var upper_zone_type : Array[CardData]
@export_storage var upper_zone : Array[ArrayCardData]
@export_storage var lower_zone_type : Array[CardData]
@export_storage var lower_zone : Array[ArrayCardData]
# Runtime score accumulators. NOT serialized (BigNumber is RefCounted, invisible to
# ResourceSaver) — the disk form lives in the packed_*_mant/exp arrays below, synced by
# pack_scores()/unpack_scores(). BigNumber only exists at runtime.
var scores_row_upper : Array[BigNumber]
var scores_row_lower : Array[BigNumber]
var scores_col : Array[BigNumber]
# Serializable score form: each BigNumber array is flattened into two PARALLEL typed arrays
# (mantissa float + exponent int) instead of an Array[Array] of [m,e] pairs. Typed packed
# arrays are contiguous and avoid per-pair Variant/Array allocation, so they serialize and
# reload far cheaper than the old Dictionary-of-pairs. Written to disk; kept in lockstep by
# pack_scores()/unpack_scores().
@export_storage var packed_row_upper_mant : PackedFloat64Array
@export_storage var packed_row_upper_exp : PackedInt64Array
@export_storage var packed_row_lower_mant : PackedFloat64Array
@export_storage var packed_row_lower_exp : PackedInt64Array
@export_storage var packed_col_mant : PackedFloat64Array
@export_storage var packed_col_exp : PackedInt64Array

func duplicate_state() -> GameData:
	#duplicate_deep remaps cross-references (modifier .data backrefs, ZoneAdder.card_data,
	#etc.) so each historical state is completely separate from the others
	var copy : GameData = self.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	#BigNumber is RefCounted, invisible to duplicate_deep -> manual copy required
	copy.scores_row_upper = duplicate_big_number_array(scores_row_upper)
	copy.scores_row_lower = duplicate_big_number_array(scores_row_lower)
	copy.scores_col = duplicate_big_number_array(scores_col)
	return copy

func all_card_datas() -> Array[CardData]:
	var all : Array[CardData] = []
	all.append_array(draw_deck)
	all.append_array(discard_deck)
	all.append_array(rules_deck)
	all.append_array(upper_zone_type)
	all.append_array(lower_zone_type)
	for col in upper_zone: all.append_array(col.datas)
	for col in lower_zone: all.append_array(col.datas)
	return all

## Invariant checker (ARCHITECTURE_REVIEW.md §5, I1-I5). Returns a list of
## violation strings; empty means the state is consistent. Report-only — never
## mutates. Game calls this after moves in debug builds; tests call it directly.
func validate() -> Array[String]:
	var violations : Array[String] = []
	#I2: zone and zone_type arrays stay in lockstep
	if upper_zone.size() != upper_zone_type.size():
		violations.append("I2: upper_zone %d cols vs upper_zone_type %d" \
				% [upper_zone.size(), upper_zone_type.size()])
	if lower_zone.size() != lower_zone_type.size():
		violations.append("I2: lower_zone %d cols vs lower_zone_type %d" \
				% [lower_zone.size(), lower_zone_type.size()])
	#I3: no null columns or null cards anywhere
	for zone_name : String in ["upper_zone", "lower_zone"]:
		var zone : Array[ArrayCardData] = get(zone_name)
		for c in zone.size():
			if not zone[c]:
				violations.append("I3: %s col %d is null" % [zone_name, c])
				continue
			for r in zone[c].datas.size():
				if not zone[c].datas[r]:
					violations.append("I3: %s col %d row %d is null" % [zone_name, c, r])
	for deck_name : String in ["draw_deck", "discard_deck", "rules_deck",
			"upper_zone_type", "lower_zone_type"]:
		var deck : Array[CardData] = get(deck_name)
		for i in deck.size():
			if not deck[i]:
				violations.append("I3: %s index %d is null" % [deck_name, i])
	#I1: every card lives in exactly one collection (no duplicates by identity)
	var seen := {}
	for card in all_card_datas():
		if not card: continue
		if seen.has(card):
			violations.append("I1: card in two places: %s (also %s)" % [card, seen[card]])
		seen[card] = true
	#I5: stage matches location
	var expected_stage := {}
	for card in draw_deck: expected_stage[card] = CardData.Stage.DRAW
	for card in discard_deck: expected_stage[card] = CardData.Stage.DISCARD
	for card in rules_deck: expected_stage[card] = CardData.Stage.RULES
	for card in upper_zone_type: expected_stage[card] = CardData.Stage.ZONE
	for card in lower_zone_type: expected_stage[card] = CardData.Stage.ZONE
	for zone : Array[ArrayCardData] in [upper_zone, lower_zone]:
		for c in zone:
			if not c: continue
			for card in c.datas: expected_stage[card] = CardData.Stage.PLAY
	for card : CardData in expected_stage:
		if not card: continue
		if card.stage != expected_stage[card]:
			violations.append("I5: %s stage %s, expected %s" % [card,
					CardData.Stage.find_key(card.stage),
					CardData.Stage.find_key(expected_stage[card])])
	#score arrays sized to the board
	if scores_col and upper_zone and scores_col.size() < min(upper_zone.size(), lower_zone.size()):
		violations.append("scores_col %d entries < %d paired columns" \
				% [scores_col.size(), min(upper_zone.size(), lower_zone.size())])
	return violations

## Capture the runtime BigNumber scores into the serializable packed_* arrays (BigNumber is
## RefCounted — invisible to ResourceSaver, same reason duplicate_state copies them by hand).
## Each array becomes two parallel typed arrays (mantissa/exponent). Pair with unpack_scores().
func pack_scores() -> void:
	# Packed arrays are value types (copy-on-write) — assign the built arrays back to the
	# fields rather than mutating them through a parameter, which would only touch a copy.
	packed_row_upper_mant = _mantissas(scores_row_upper)
	packed_row_upper_exp = _exponents(scores_row_upper)
	packed_row_lower_mant = _mantissas(scores_row_lower)
	packed_row_lower_exp = _exponents(scores_row_lower)
	packed_col_mant = _mantissas(scores_col)
	packed_col_exp = _exponents(scores_col)

## Rebuild the runtime BigNumber scores from the packed_* arrays (after a load).
func unpack_scores() -> void:
	scores_row_upper = _unpack(packed_row_upper_mant, packed_row_upper_exp)
	scores_row_lower = _unpack(packed_row_lower_mant, packed_row_lower_exp)
	scores_col = _unpack(packed_col_mant, packed_col_exp)

# Cyclic CardModifier.data self-references (card -> its modifier -> back to the card) are
# the only thing ResourceSaver can't write; unlink for a save, relink after. The backref
# always equals the owning card, so relinking is lossless. ZoneAdder.card_data is a plain
# forward ref (no cycle) and is left intact.
func unlink_modifier_backrefs() -> void:
	for card in all_card_datas():
		for mod : CardModifier in [card.skill, card.type, card.stamp]:
			if mod: mod.data = null

func relink_modifier_backrefs() -> void:
	for card in all_card_datas():
		for mod : CardModifier in [card.skill, card.type, card.stamp]:
			if mod: mod.data = card

## An independent, disk-ready copy: modifier self-cycles unlinked and scores packed to
## primitives, so ResourceSaver can write it and a background thread can read it safely
## (the copy is immutable — never mutated again). Rebuild a runtime GameData from it with
## duplicate_state() + restore_runtime().
func to_saveable() -> GameData:
	var copy : GameData = duplicate_state()
	copy.pack_scores()
	copy.scores_row_upper.clear()
	copy.scores_row_lower.clear()
	copy.scores_col.clear()
	copy.unlink_modifier_backrefs()
	return copy

## Turn a to_saveable() copy back into a live runtime state (relink backrefs, rebuild the
## BigNumber score arrays). Mutates in place.
func restore_runtime() -> void:
	relink_modifier_backrefs()
	unpack_scores()

# The mantissa / exponent columns of a BigNumber array as their own typed packed arrays.
func _mantissas(src:Array[BigNumber]) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(src.size())
	for i in src.size():
		out[i] = src[i].mantissa
	return out

func _exponents(src:Array[BigNumber]) -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(src.size())
	for i in src.size():
		out[i] = src[i].exponent
	return out

# Rebuild a BigNumber array from parallel mantissa/exponent packed arrays.
func _unpack(mant:PackedFloat64Array, exp:PackedInt64Array) -> Array[BigNumber]:
	var out : Array[BigNumber] = []
	out.resize(mant.size())
	for i in mant.size():
		var bn := BigNumber.new()
		bn.mantissa = mant[i]
		bn.exponent = exp[i]
		out[i] = bn
	return out

func duplicate_big_number_array(a:Array[BigNumber]) -> Array[BigNumber]:
	var new_a : Array[BigNumber] = []
	new_a.resize(a.size())
	for i in a.size():
		new_a[i] = BigNumber.new()
		new_a[i].mantissa = a[i].mantissa
		new_a[i].exponent = a[i].exponent
	return new_a

func print_board() -> void:
	var s : String = "Upper Type,"
	for c in upper_zone_type:
		s += c.to_string() + ","
	s += "\n"
	var upper_col_sizes : Array = upper_zone.map(func(a:ArrayCardData)->int:return a.datas.size())
	var rows : int = upper_col_sizes.max() if upper_col_sizes else 0
	for r in rows:
		s += str(r) + ","
		for col in upper_zone:
			if r < col.datas.size():
				s += col.datas[r].to_string()
			s += ","
		s += "\n"
	s += "Lower Type,"
	for c in lower_zone_type:
		s += c.to_string() + ","
	s += "\n"
	var lower_col_sizes : Array = lower_zone.map(func(a:ArrayCardData)->int:return a.datas.size())
	rows = lower_col_sizes.max() if lower_col_sizes else 0
	for r in rows:
		s += str(r) + ","
		for col in lower_zone:
			if r < col.datas.size():
				s += col.datas[r].to_string()
			s += ","
		s += "\n"
	print(s)
