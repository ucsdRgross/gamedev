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

#scalar setters guard same-value writes (E10): each emission fans out to every HUD label,
#and scoring passes re-assign these repeatedly with unchanged values
@export_storage var goal : int = 100:
	set(value):
		if goal == value: return
		goal = value
		state_changed.emit()
@export_storage var total_score : int = 0:
	set(value):
		if total_score == value: return
		total_score = value
		state_changed.emit()
@export_storage var mult_score : int = 0:
	set(value):
		if mult_score == value: return
		mult_score = value
		state_changed.emit()
@export_storage var col_total : int = 0:
	set(value):
		if col_total == value: return
		col_total = value
		state_changed.emit()
@export_storage var row_total : int = 0:
	set(value):
		if row_total == value: return
		row_total = value
		state_changed.emit()
## Acts used this show. Lives ON the board state so every undo/history snapshot carries it:
## undoing across a Submit rewinds the act count together with the board (it used to be a
## Game-level counter that undo never touched — owner bug report 2026-07-12).
@export_storage var submits_used : int = 0
## Distinct combo classes scored THIS act (SCORING_MATH_PLAN §15a U; a set — Array for
## serialization). Lives ON the board state so undo/act-cancel/pending-action replay reset
## it for free: every snapshot restore brings back the pre-act (empty) set, same reason
## submits_used lives here.
@export_storage var combo_classes : Array[String] = []
## PATIENCE (2026-07-20) — "the audience won't watch you shuffle the board forever": idle card
## moves tick this down; a move that triggers a qualifying card modifier holds it. At 0 the game
## auto-presses Next, which resets it to settings.patience_max. Lives ON the board state (like
## submits_used) so undo/history snapshots rewind it with the board.
## NOTE (owner ruling A2, 2026-07-20): the patience mutators deliberately do NOT bump `revision`.
## Patience only ever moves together with a real board change, so the change-detector that keys
## Game.save_state() stays the single signal; a snapshot where ONLY patience differs cannot exist.
## 0 = never seeded (a bare fixture, or a save written before patience existed): the first move
## seeds it from settings. Every committed board otherwise carries at least 1 — see the auto-Next
## rule in Game._spend_patience_for_move.
@export_storage var patience : int = 0
## combo_key set of modifiers the audience has already seen this round: a re-trigger of one of
## these no longer holds patience (settings.patience_track_uniques). Cleared on Next, or after a
## Submit when settings.patience_reset_uniques_on_act.
@export_storage var patience_seen_mods : Array[String] = []

## Spend one patience (a move the audience found boring). Floors at 0 — 0 is the auto-Next trip.
func spend_patience() -> void:
	patience = maxi(patience - 1, 0)

## Refill patience for a new round. `max_val` is settings.patience_max (floored at 1 there).
func reset_patience(max_val: int) -> void:
	patience = maxi(max_val, 1)

## Record a modifier's combo_key as "seen" this round (it stops holding patience from now on).
func mark_seen(key: String) -> void:
	if key.is_empty() or patience_seen_mods.has(key): return
	patience_seen_mods.append(key)

## Forget every seen modifier — a fresh audience (Next, or Submit per the tunable).
func clear_seen() -> void:
	patience_seen_mods.clear()

#const COMBO_STEP := 0.1   # moved to PlayerSettings.combo_step 2026-07-17 (all knobs in one place)

## Current act multiplier: 1.0 + combo_step per distinct class scored this act (§15a).
func combo_mult() -> float:
	return 1.0 + SettingsManager.settings.combo_step * combo_classes.size()

## One act's payout (DESIGN_DOC §2 + SCORING_MATH_PLAN §15a): the act's accumulated row and
## column totals combine (R×C shipped; R+C when settings.score_additive — TEST variant,
## goals must be re-fit) and multiply with the combo multiplier into mult_score, which is
## added to total_score; the totals and combo set reset for the next act.
## Note: under R×C an act with no scored columns (or rows) pays 0 — both sides must score.
func apply_act_score() -> void:
	# §15a: round ONCE per act payout — combo applies to the combined R/C total, not per line.
	var base : int = (row_total + col_total) if SettingsManager.settings.score_additive \
			else (row_total * col_total)
	mult_score = int(base * combo_mult())
	total_score += mult_score
	row_total = 0
	col_total = 0
	combo_classes.clear()   # U resets every act, alongside the gutters below
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
	#the position index must never travel with a copy (its keys are THIS state's card
	#instances); the copy lazily rebuilds its own on first lookup
	copy._pos_index = {}
	copy._pos_index_revision = -1
	#modifier .data backrefs are WeakRefs, which duplicate_deep does NOT remap — the
	#copied modifiers still point at THIS state's cards. Rebind them to the copies.
	copy.relink_modifier_backrefs()
	return copy

# ---------------------------------------------------------------------------
# E4 / §5.4 position index: card -> board coordinate ((x, col, row); headers row -1),
# rebuilt LAZILY whenever `revision` moved since the last build. Runtime only — not
# @export*, so it never serializes; duplicate_state()/restore_runtime() reset it.
# Correctness rides the MUTATION GUIDELINES bump-after-consistency rule — the exact
# key the SE1 compare-mod cache already trusts, so a mutation that forgets its bump
# was a bug before this index existed. The one mid-mutation refresh point is
# Board.move_stack, which invalidates after its extraction so the post-extraction
# anchor resolve sees current rows.
# ---------------------------------------------------------------------------
var _pos_index : Dictionary[CardData, Vector3i] = {}
var _pos_index_revision : int = -1   # -1 = invalid (revision is never negative)

## O(1) board position of a card; Vector3i.MIN when not on the board.
func position_of(card: CardData) -> Vector3i:
	if _pos_index_revision != revision:
		_pos_index = _scan_positions()
		_pos_index_revision = revision
	return _pos_index.get(card, Vector3i.MIN)

## Force the next position_of to rebuild (for lookups mid-mutation, before the bump).
func invalidate_pos_index() -> void:
	_pos_index_revision = -1

## Full rescan of every board position. Write order is REVERSE lookup precedence
## (upper types > lower types > upper cards > lower cards — later writes win), so a
## duplicate-card state (I1 violation) resolves like the old linear locate did.
func _scan_positions() -> Dictionary[CardData, Vector3i]:
	var out : Dictionary[CardData, Vector3i] = {}
	for c in lower_zone.size():
		if not lower_zone[c]: continue
		for r in lower_zone[c].datas.size():
			if lower_zone[c].datas[r]: out[lower_zone[c].datas[r]] = Vector3i(1, c, r)
	for c in upper_zone.size():
		if not upper_zone[c]: continue
		for r in upper_zone[c].datas.size():
			if upper_zone[c].datas[r]: out[upper_zone[c].datas[r]] = Vector3i(0, c, r)
	for c in lower_zone_type.size():
		if lower_zone_type[c]: out[lower_zone_type[c]] = Vector3i(1, c, -1)
	for c in upper_zone_type.size():
		if upper_zone_type[c]: out[upper_zone_type[c]] = Vector3i(0, c, -1)
	return out

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
	#I1: every card lives in exactly one collection (no duplicates by identity).
	#Walks the named containers (not all_card_datas) so the message can say WHERE the
	#card also lives instead of a bare true.
	var seen : Dictionary[CardData, String] = {}
	for deck_name : String in ["draw_deck", "discard_deck", "rules_deck",
			"upper_zone_type", "lower_zone_type"]:
		for card : CardData in get(deck_name):
			if not card: continue
			if seen.has(card):
				violations.append("I1: card in two places: %s (%s, also %s)" \
						% [card, deck_name, seen[card]])
			seen[card] = deck_name
	for zone_name : String in ["upper_zone", "lower_zone"]:
		for c in (get(zone_name) as Array[ArrayCardData]).size():
			var col : ArrayCardData = get(zone_name)[c]
			if not col: continue
			for card in col.datas:
				if not card: continue
				var here := "%s col %d" % [zone_name, c]
				if seen.has(card):
					violations.append("I1: card in two places: %s (%s, also %s)" \
							% [card, here, seen[card]])
				seen[card] = here
	#I5: stage matches location
	var expected_stage : Dictionary[CardData, CardData.Stage] = {}
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
	#I4 (§5.4): the position index, when built for THIS revision, agrees with a rescan.
	#Report-only like everything here — no rebuild, no invalidation.
	if _pos_index_revision == revision:
		var rescan := _scan_positions()
		for card in rescan:
			if _pos_index.get(card, Vector3i.MIN) != rescan[card]:
				violations.append("I4: index says %s for %s, rescan says %s" \
						% [_pos_index.get(card, Vector3i.MIN), card, rescan[card]])
		for card in _pos_index:
			if not rescan.has(card):
				violations.append("I4: stale index entry %s for off-board %s" \
						% [_pos_index[card], card])
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

# CardModifier.data backrefs are WeakRefs (no RefCounted cycle — dropped card graphs
# just die; the old per-drop-site unlink discipline is gone). These helpers remain for
# two jobs: RELINK after any deep copy or load (duplicate_deep does not remap a WeakRef,
# and saves carry no backref), and UNLINK on to_saveable copies so saved decks stay
# backref-free. The backref always equals the owning card, so relinking is lossless.
# ZoneAdder.card_data is a plain forward ref and is left intact.
# The per-card halves are static and are THE single list of modifier slots — RunManager's
# deck save/load paths call them too. Add any new modifier slot here and nowhere else.
static func unlink_card_backrefs(card: CardData) -> void:
	for mod : CardModifier in [card.skill, card.type, card.stamp, card.suit]:
		if mod: mod.data = null
	for st: CardModifierStatus in card.statuses:
		st.data = null

static func relink_card_backrefs(card: CardData) -> void:
	for mod : CardModifier in [card.skill, card.type, card.stamp, card.suit]:
		if mod: mod.data = card
	for st: CardModifierStatus in card.statuses:
		st.data = card

func unlink_modifier_backrefs() -> void:
	for card in all_card_datas():
		unlink_card_backrefs(card)

func relink_modifier_backrefs() -> void:
	for card in all_card_datas():
		relink_card_backrefs(card)

## An independent, disk-ready copy: modifier backrefs nulled (saves carry none) and scores packed to
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
	invalidate_pos_index()  # loaded/copied states rebuild their own index on first lookup

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
	print(_zone_to_csv("Upper Type", upper_zone_type, upper_zone)
			+ _zone_to_csv("Lower Type", lower_zone_type, lower_zone))

#one zone's debug CSV: header row of type cards, then one row per stack depth (E7)
func _zone_to_csv(label: String, types: Array[CardData], zone: Array[ArrayCardData]) -> String:
	var s : String = label + ","
	for c in types:
		s += c.to_string() + ","
	s += "\n"
	var col_sizes : Array = zone.map(func(a:ArrayCardData)->int:return a.datas.size())
	var rows : int = col_sizes.max() if col_sizes else 0
	for r in rows:
		s += str(r) + ","
		for col in zone:
			if r < col.datas.size():
				s += col.datas[r].to_string()
			s += ","
		s += "\n"
	return s
