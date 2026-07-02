class_name GameData
extends Resource

signal state_changed

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

@export_storage var draw_deck : Array[CardData]
@export_storage var discard_deck : Array[CardData]
@export_storage var rules_deck : Array[CardData]
@export_storage var upper_zone_type : Array[CardData]
@export_storage var upper_zone : Array[ArrayCardData]
@export_storage var lower_zone_type : Array[CardData]
@export_storage var lower_zone : Array[ArrayCardData]
@export_storage var scores_row_upper : Array[BigNumber]
@export_storage var scores_row_lower : Array[BigNumber]
@export_storage var scores_col : Array[BigNumber]

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
