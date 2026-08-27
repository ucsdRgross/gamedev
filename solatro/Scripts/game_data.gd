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
## The player has ended this show and the outcome is up. Lives ON the board state so undo
## rewinds it with the board and a resume comes back into the outcome rather than a live board
## — the same reason the act count used to live here.
@export_storage var show_ended : bool = false
## Which grid the Entrance is committed to; -1 = uncommitted. Once set, an Entrance placement
## into any other grid is refused. `@export_storage` so undo rewinds the commitment with the
## board -- the only way it lifts besides no legal placement remaining in the committed grid.
@export_storage var committed_grid : int = -1
## Distinct combo classes scored THIS act (SCORING_MATH_PLAN §15a U; a set — Array for
## serialization). Lives ON the board state so undo/act-cancel/pending-action replay reset
## it for free: every snapshot restore brings back the pre-act (empty) set, same reason
## show_ended lives here.
@export_storage var combo_classes : Array[String] = []
## How many registrations landed on a class ALREADY seen. Kept alongside the distinct set
## because the two are weighted differently: a first-of-its-class and a repeat each add their
## own step. Stored here, not on Game, so undo rewinds it with the board.
@export_storage var combo_repeats : int = 0
## SPOTLIGHT — the cards the scoring beam is on RIGHT NOW. Effective spotlight is
## `is_spotlit()` OR a key in here (design §2), and that one line is the whole mechanical change.
## ⚠ Deliberately NOT `@export_storage`: it is per-act state, so undo rewinds it by simply not
## saving it (`Q18`=a), and a resume replays the act from the pre-act board with it empty.
## ⚠ NEVER bump `revision` from it (`Q17`=a) — this is not a board mutation, and a bump would
## force the play area to rebuild in the middle of the cascade.
## Written only by `Game._spotlight_section()` / `Game._release_spotlight()`; read only by
## `CardModifier.is_spotlit()`. A Dictionary, not an Array, because the read is per-card and hot.
var forced_spotlight : Dictionary[CardData, bool] = {}

#const COMBO_STEP := 0.1 # moved to PlayerSettings.combo_step (all knobs in one place)

## Current act multiplier: 1.0 + combo_step per distinct class scored this act (§15a).
## The live combo multiplier: every first-of-its-class adds one step, every repeat adds a
## smaller one. Melds and effects contribute on exactly the same terms -- only whether the
## class has been seen before decides which step applies.
func combo_mult() -> float:
	var s := SettingsManager.settings
	var mult := 1.0 + s.combo_unique_step * combo_classes.size() 			+ s.combo_repeat_step * combo_repeats
	# A cap of 0 means no cap at all, which is how it ships.
	if s.combo_cap > 0.0: mult = minf(mult, s.combo_cap)
	return mult

## One act's payout (DESIGN_DOC §2 + SCORING_MATH_PLAN §15a): the act's accumulated row and
## column totals combine (R x C) and multiply with the combo multiplier into mult_score,
## which is added to total_score; the totals and combo set reset for the next act.
## Note: under R×C an act with no scored columns (or rows) pays 0 — both sides must score.
func apply_act_score() -> void:
	# §15a: round ONCE per act payout — combo applies to the combined R/C total, not per line.
	var base : int = row_total * col_total
	mult_score = int(base * combo_mult())
	total_score += mult_score
	row_total = 0
	col_total = 0
	combo_classes.clear()   # U resets every act, alongside the gutters below
	# Clear the per-row/col score gutters too, so the NEXT act starts from zero. Without this
	# the BigNumber accumulators (scores_row_*/scores_col_legacy) keep growing and the next
	# act's plus_equals stacks onto the previous act's values. The UI gutters resync from
	# these empty arrays via PlayArea.update_score_controls (see Game._perform_submit).
	scores_row_upper.clear()
	scores_row_lower.clear()
	scores_col_legacy.clear()

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

## The grid list, left to right. Each grid carries its own size and cells (§1.3 of the
## poker-patience plan: nothing hard-codes 5x5).
@export_storage var grids : Array[GridData] = []
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
var scores_col_legacy : Array[BigNumber]
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

## Per-grid economy buckets (§1.6/§1.7 of the poker-patience plan): each grid gets exactly
## three buckets that multiply into its grid_score -- row, col and special (every diagonal and
## every future non-directional meld shares the one special bucket). `scores_row`/
## `scores_col` hold the height-0 (flat) bucket per grid; `scores_row_h`/`scores_col_h` hold the
## raised-level buckets, indexed [grid][height]. Runtime-only, same reason as the legacy score
## arrays above: BigNumber is RefCounted and invisible to ResourceSaver.
var scores_row : Array[BigNumber] = []
var scores_col : Array[BigNumber] = []
var scores_row_h : Array[Array] = []
var scores_col_h : Array[Array] = []
var score_special : Array[BigNumber] = []
## One bucket PER CELL, for the vertical stack scored in it -- the number behind the height
## score label that sits above each stack. Keyed by cell coordinate rather than shaped as a
## 2-D array because a grid's shape can change under effects: a dictionary survives a grid
## that grows, shrinks or turns ragged, where a width-by-height array would not.
## Key is Vector3i(grid, x, y); the stack's own height is not part of the key, because every
## payout of one stack accumulates into that stack's single bucket.
var scores_cell : Dictionary[Vector3i, BigNumber] = {}
# Serializable form of the grid economy buckets. The flat ones mirror packed_col_mant/exp
# above. The raised (2-D) ones flatten grid-major, height-minor into one parallel mant/exp
# pair plus a per-grid length so unpack_scores() can rebuild each grid's inner array exactly.
@export_storage var packed_grid_row_mant : PackedFloat64Array
@export_storage var packed_grid_row_exp : PackedInt64Array
@export_storage var packed_grid_col_mant : PackedFloat64Array
@export_storage var packed_grid_col_exp : PackedInt64Array
@export_storage var packed_grid_special_mant : PackedFloat64Array
@export_storage var packed_grid_special_exp : PackedInt64Array
# The per-cell buckets flatten into three PARALLEL arrays: the cell coordinates and the
# mantissa/exponent of each. A dictionary has no inherent order, so the key array is what
# carries the association across a save -- position i in all three is one cell's bucket.
@export_storage var packed_cell_keys : PackedVector3Array
@export_storage var packed_cell_mant : PackedFloat64Array
@export_storage var packed_cell_exp : PackedInt64Array
@export_storage var packed_grid_row_h_mant : PackedFloat64Array
@export_storage var packed_grid_row_h_exp : PackedInt64Array
@export_storage var packed_grid_row_h_lens : PackedInt32Array
@export_storage var packed_grid_col_h_mant : PackedFloat64Array
@export_storage var packed_grid_col_h_exp : PackedInt64Array
@export_storage var packed_grid_col_h_lens : PackedInt32Array

func duplicate_state() -> GameData:
	#duplicate_deep remaps cross-references (modifier .data backrefs, ZoneAdder.card_data,
	#etc.) so each historical state is completely separate from the others
	var copy : GameData = self.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	#BigNumber is RefCounted, invisible to duplicate_deep -> manual copy required
	copy.scores_row_upper = duplicate_big_number_array(scores_row_upper)
	copy.scores_row_lower = duplicate_big_number_array(scores_row_lower)
	copy.scores_col_legacy = duplicate_big_number_array(scores_col_legacy)
	#the grid economy buckets are the same RefCounted trap -- manual copy too
	copy.scores_row = duplicate_big_number_array(scores_row)
	copy.scores_col = duplicate_big_number_array(scores_col)
	copy.score_special = duplicate_big_number_array(score_special)
	copy.scores_row_h = duplicate_big_number_2d_array(scores_row_h)
	copy.scores_col_h = duplicate_big_number_2d_array(scores_col_h)
	copy.scores_cell = duplicate_big_number_dict(scores_cell)
	#the position index must never travel with a copy (its keys are THIS state's card
	#instances); the copy lazily rebuilds its own on first lookup
	copy._pos_index = {}
	copy._pos_index_revision = -1
	copy._grid_pos_index = {}
	copy._card_at_index = {}
	#the forced spotlight is per-ACT and never travels with a copy: a snapshot restored by undo,
	#act-cancel or resume must come back with no beam on it (Q18=a). duplicate_deep already
	#skips a non-exported var; stated here for the same reason the index above is.
	copy.forced_spotlight = {}
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

# The legacy zone board and the grid board coexist for now, and there is no fixed mapping from
# a legacy (zone, col, row) position onto BoardCoord. So the grid-side index is a SEPARATE
# forward index, keyed the same way (rebuild-on-revision-change) as the legacy one above, plus
# its own reverse lookup.
var _grid_pos_index : Dictionary[CardData, BoardCoord] = {}
# card_at()'s reverse index. Keyed on a value-type Vector4i(grid,x,y,h) rather than a
# BoardCoord instance, since BoardCoord is RefCounted and hashes by identity, not value.
var _card_at_index : Dictionary[Vector4i, CardData] = {}

## O(1) board position of a card; Vector3i.MIN when not on the board.
func position_of(card: CardData) -> Vector3i:
	_ensure_pos_index()
	return _pos_index.get(card, Vector3i.MIN)

## Does this coordinate name a REAL cell of a real grid? The landing question: movement runs
## over an unbounded lattice that pretends a grid exists wherever a card is heading, so a step
## can arrive anywhere. This is what a placement asks on arrival -- false means there is nothing
## to land on, and the card is discarded. False for a virtual grid index, for an x or y outside
## the grid's own bounds, and for a hole in a ragged grid.
func has_cell(coord: BoardCoord) -> bool:
	if coord.grid < 0 or coord.grid >= grids.size():
		return false
	var grid : GridData = grids[coord.grid]
	if not grid:
		return false
	if coord.x < 0 or coord.x >= grid.grid_width or coord.y < 0 or coord.y >= grid.grid_height:
		return false
	var index := grid.cell_index(coord.x, coord.y)
	return index < grid.cells.size() and grid.cells[index] != null

## The card occupying a grid cell coordinate, null when the coordinate is empty or off-board.
## INVARIANT tying this reverse index to the grid-side forward index: for every card C with a
## grid position P (i.e. `_grid_pos_index[C] == P`), `card_at(P) == C`; and for every non-null
## `card_at(P)`, that card's grid position is exactly P. Neither dictionary is a copy of the
## other — they are built together and diverge only if some path bumps `revision` without
## finishing the mutation that keeps them in step. `validate()`'s I4 check compares both against
## an independent rescan to catch that.
func card_at(coord: BoardCoord) -> CardData:
	_ensure_pos_index()
	return _card_at_index.get(Vector4i(coord.grid, coord.x, coord.y, coord.h), null)

## Where a card ACTUALLY sits on the grid board, or NOWHERE when it is not on one. The forward
## half of the pair `card_at` reads backwards. Callers that need the coordinate a mutation
## LANDED on must ask this rather than reusing the coordinate they requested: a placement lands
## on top of whatever is already in the cell, so a requested height and the real one differ as
## soon as a stack is more than one card deep.
func grid_position_of(card: CardData) -> BoardCoord:
	_ensure_pos_index()
	return _grid_pos_index.get(card, BoardCoord.NOWHERE)

## Rebuilds every position index (legacy Vector3i, grid-side BoardCoord, and its reverse) once
## per revision change, mirroring the bump-after-consistency rule the legacy index already rode.
func _ensure_pos_index() -> void:
	if _pos_index_revision == revision:
		return
	_pos_index = _scan_positions()
	_grid_pos_index = _scan_grid_positions()
	_card_at_index = {}
	for card : CardData in _grid_pos_index:
		var coord : BoardCoord = _grid_pos_index[card]
		_card_at_index[Vector4i(coord.grid, coord.x, coord.y, coord.h)] = card
	_pos_index_revision = revision

## Force the next position_of/card_at to rebuild (for lookups mid-mutation, before the bump).
func invalidate_pos_index() -> void:
	_pos_index_revision = -1

## Full rescan of every legacy zone board position. Write order is REVERSE lookup precedence
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

## Full rescan of every grid cell. The grid-side result stays out of the legacy Vector3i index
## (no fixed legacy-to-grid coordinate mapping exists yet), so this is a sibling scan, not a
## shared return type. Cell zone cards are not positioned by this index -- only cards in play, at a
## height. Write order: grid 0 before grid 1 before grid 2, row-major within a grid, bottom of
## stack first -- a card duplicated across two grid cells resolves to the later one, the same
## later-write-wins precedence the legacy scan uses.
func _scan_grid_positions() -> Dictionary[CardData, BoardCoord]:
	var out : Dictionary[CardData, BoardCoord] = {}
	for gi in grids.size():
		var grid : GridData = grids[gi]
		if not grid: continue
		for ci in grid.cells.size():
			var cell : ArrayCardData = grid.cells[ci]
			if not cell: continue
			var col := ci % grid.grid_width
			var row := ci / grid.grid_width
			for h in cell.datas.size():
				if cell.datas[h]:
					out[cell.datas[h]] = BoardCoord.new(gi, col, row, h)
	return out

## The board walk for `CardDataIterator` (run_all_mods, spotlight sweep, etc.): `draw_deck`
## first, then every board collection, cell zone cards near the end. Each grid's cells wrap
## in `GridCellWalk` so the grid is walked row-major with a full bottom-to-top stack per
## cell and no early stop -- a grid is sparse by nature.
func get_card_collections() -> Array:
	var out : Array = [
		draw_deck,
		upper_zone,
		lower_zone,
	]
	for grid : GridData in grids:
		if grid: out.append(GridCellWalk.new(grid.cells))
	out.append(discard_deck)
	out.append(upper_zone_type)
	out.append(lower_zone_type)
	for grid : GridData in grids:
		if grid: out.append(grid.cell_types)
	out.append(rules_deck)
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
	for grid : GridData in grids:
		if not grid: continue
		all.append_array(grid.cell_types)
		for cell : ArrayCardData in grid.cells:
			if not cell: continue
			all.append_array(cell.datas)
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
	#I2: every grid's cells and cell_types stay in lockstep with its OWN width * height
	#(G7: 25 cell zone cards per grid, at the default 5x5 -- nothing hard-codes 5)
	for gi in grids.size():
		var grid_check : GridData = grids[gi]
		if not grid_check:
			violations.append("I3: grids index %d is null" % gi)
			continue
		var expected_cells := grid_check.grid_width * grid_check.grid_height
		if grid_check.cells.size() != expected_cells:
			violations.append("I2: grid %d cells %d entries vs %d expected (%dx%d)" \
					% [gi, grid_check.cells.size(), expected_cells,
					grid_check.grid_width, grid_check.grid_height])
		if grid_check.cell_types.size() != expected_cells:
			violations.append("I2: grid %d cell_types %d entries vs %d expected (%dx%d)" \
					% [gi, grid_check.cell_types.size(), expected_cells,
					grid_check.grid_width, grid_check.grid_height])
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
	#I3: no null grid cells / cell zone cards
	for gi in grids.size():
		var grid_null_check : GridData = grids[gi]
		if not grid_null_check: continue
		for ci in grid_null_check.cells.size():
			if not grid_null_check.cells[ci]:
				violations.append("I3: grid %d cell %d is null" % [gi, ci])
				continue
			for r in grid_null_check.cells[ci].datas.size():
				if not grid_null_check.cells[ci].datas[r]:
					violations.append("I3: grid %d cell %d row %d is null" % [gi, ci, r])
		for ci in grid_null_check.cell_types.size():
			if not grid_null_check.cell_types[ci]:
				violations.append("I3: grid %d cell_types %d is null" % [gi, ci])
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
	for gi in grids.size():
		var grid_dup_check : GridData = grids[gi]
		if not grid_dup_check: continue
		for ci in grid_dup_check.cell_types.size():
			var type_card := grid_dup_check.cell_types[ci]
			if not type_card: continue
			var type_here := "grid %d cell_types (%d,%d)" \
					% [gi, ci % grid_dup_check.grid_width, ci / grid_dup_check.grid_width]
			if seen.has(type_card):
				violations.append("I1: card in two places: %s (%s, also %s)" \
						% [type_card, type_here, seen[type_card]])
			seen[type_card] = type_here
		for ci in grid_dup_check.cells.size():
			var cell_col : ArrayCardData = grid_dup_check.cells[ci]
			if not cell_col: continue
			var cell_here := "grid %d cell (%d,%d)" \
					% [gi, ci % grid_dup_check.grid_width, ci / grid_dup_check.grid_width]
			for card : CardData in cell_col.datas:
				if not card: continue
				if seen.has(card):
					violations.append("I1: card in two places: %s (%s, also %s)" \
							% [card, cell_here, seen[card]])
				seen[card] = cell_here
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
	for grid_stage_check : GridData in grids:
		if not grid_stage_check: continue
		for card in grid_stage_check.cell_types: expected_stage[card] = CardData.Stage.ZONE
		for cell : ArrayCardData in grid_stage_check.cells:
			if not cell: continue
			for card in cell.datas: expected_stage[card] = CardData.Stage.PLAY
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
		#I4, grid side: the grid forward index agrees with an independent rescan, and the
		#reverse index (card_at) names exactly the same card at exactly the same coordinate
		#the forward index has for it -- the invariant stated at card_at()'s definition.
		var grid_rescan := _scan_grid_positions()
		for card in grid_rescan:
			var expected : BoardCoord = grid_rescan[card]
			var got : BoardCoord = _grid_pos_index.get(card, null)
			if not got or got.grid != expected.grid or got.x != expected.x \
					or got.y != expected.y or got.h != expected.h:
				violations.append("I4: grid index says %s for %s, rescan says (%d,%d,%d,%d)" \
						% [got, card, expected.grid, expected.x, expected.y, expected.h])
		for card in _grid_pos_index:
			if not grid_rescan.has(card):
				violations.append("I4: stale grid index entry for off-board %s" % card)
		for card in _grid_pos_index:
			var coord : BoardCoord = _grid_pos_index[card]
			var key := Vector4i(coord.grid, coord.x, coord.y, coord.h)
			if _card_at_index.get(key, null) != card:
				violations.append(
						"I4: card_at reverse index disagrees with forward index for %s at %s" \
						% [card, key])
	#score arrays sized to the board
	if scores_col_legacy and upper_zone and scores_col_legacy.size() < min(upper_zone.size(), lower_zone.size()):
		violations.append("scores_col_legacy %d entries < %d paired columns" \
				% [scores_col_legacy.size(), min(upper_zone.size(), lower_zone.size())])
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
	packed_col_mant = _mantissas(scores_col_legacy)
	packed_col_exp = _exponents(scores_col_legacy)
	# The grid economy buckets (§1.7): flat buckets pack exactly like the legacy ones above;
	# the raised 2-D buckets flatten grid-major/height-minor with a per-grid length column so
	# unpack_scores() can rebuild each grid's inner array at its own size.
	packed_grid_row_mant = _mantissas(scores_row)
	packed_grid_row_exp = _exponents(scores_row)
	packed_grid_col_mant = _mantissas(scores_col)
	packed_grid_col_exp = _exponents(scores_col)
	packed_grid_special_mant = _mantissas(score_special)
	packed_grid_special_exp = _exponents(score_special)
	var cell_keys := PackedVector3Array()
	var cell_mant := PackedFloat64Array()
	var cell_exp := PackedInt64Array()
	for key : Vector3i in scores_cell:
		cell_keys.append(Vector3(key))
		cell_mant.append(scores_cell[key].mantissa)
		cell_exp.append(scores_cell[key].exponent)
	packed_cell_keys = cell_keys
	packed_cell_mant = cell_mant
	packed_cell_exp = cell_exp
	var row_h_packed := _pack_2d(scores_row_h)
	packed_grid_row_h_mant = row_h_packed[0]
	packed_grid_row_h_exp = row_h_packed[1]
	packed_grid_row_h_lens = row_h_packed[2]
	var col_h_packed := _pack_2d(scores_col_h)
	packed_grid_col_h_mant = col_h_packed[0]
	packed_grid_col_h_exp = col_h_packed[1]
	packed_grid_col_h_lens = col_h_packed[2]

## Rebuild the runtime BigNumber scores from the packed_* arrays (after a load).
func unpack_scores() -> void:
	scores_row_upper = _unpack(packed_row_upper_mant, packed_row_upper_exp)
	scores_row_lower = _unpack(packed_row_lower_mant, packed_row_lower_exp)
	scores_col_legacy = _unpack(packed_col_mant, packed_col_exp)
	scores_row = _unpack(packed_grid_row_mant, packed_grid_row_exp)
	scores_col = _unpack(packed_grid_col_mant, packed_grid_col_exp)
	score_special = _unpack(packed_grid_special_mant, packed_grid_special_exp)
	scores_row_h = _unpack_2d(packed_grid_row_h_mant, packed_grid_row_h_exp, packed_grid_row_h_lens)
	scores_col_h = _unpack_2d(packed_grid_col_h_mant, packed_grid_col_h_exp, packed_grid_col_h_lens)
	var cells : Dictionary[Vector3i, BigNumber] = {}
	for i in packed_cell_keys.size():
		var bn := BigNumber.new()
		bn.mantissa = packed_cell_mant[i]
		bn.exponent = packed_cell_exp[i]
		cells[Vector3i(packed_cell_keys[i])] = bn
	scores_cell = cells

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
	copy.scores_col_legacy.clear()
	copy.scores_row.clear()
	copy.scores_col.clear()
	copy.score_special.clear()
	copy.scores_row_h.clear()
	copy.scores_col_h.clear()
	copy.scores_cell.clear()
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

## Deep copy of a 2-D BigNumber array, per grid. BigNumber is RefCounted and invisible to
## duplicate_deep, so every level has to be rebuilt by hand or the copy shares its scores with
## the state it came from -- and undo would then rewind the board but not the score.
## A BigNumber at ZERO. `BigNumber.new()` alone is ONE, so a bucket seeded with it would
## start every grid a point ahead and, worse, read as "has scored" to the product rule.
func _zero_big_number() -> BigNumber:
	var bn := BigNumber.new()
	bn.mantissa = 0
	return bn

## One grid's score: its row, column and special TERMS multiplied together, counting only the
## terms that actually scored.
##
## ⚠ A term that has not scored ADDS 0 — it never multiplies by 0. Owner's worked example:
## row + col + special = 0 + 0 + 0; row banks 10 and it is 10; col banks 5 and it is 10 * 5;
## special banks 2 and it is 10 * 5 * 2 = 100.
##
## ⚠ THE TEST IS THE VALUE, NEVER TOUCHED-NESS. A term worth 0 is excluded from the product
## even when a line genuinely completed and scored 0.
##
## Storage is granular so every label has its own number; scoring aggregates:
##   row     = the height-0 row bucket    + every raised row bucket
##   col     = the height-0 column bucket + every raised column bucket
##   special = the diagonal bucket        + every CELL bucket in this grid
func grid_score(grid: int) -> float:
	var terms : Array[float] = [_row_term(grid), _col_term(grid), _special_term(grid)]
	var product := 0.0
	for term : float in terms:
		if term <= 0.0: continue
		product = term if product == 0.0 else product * term
	return product

## The whole board's score: the sum of every grid's own score.
func board_total() -> float:
	var total := 0.0
	for i in grids.size():
		total += grid_score(i)
	return total

## Height-0 row bucket plus every raised row bucket for this grid.
func _row_term(grid: int) -> float:
	return _flat_and_raised(scores_row, scores_row_h, grid)

## Height-0 column bucket plus every raised column bucket for this grid.
func _col_term(grid: int) -> float:
	return _flat_and_raised(scores_col, scores_col_h, grid)

## The diagonal bucket plus every cell bucket in this grid — the vertical stacks fold in here
## rather than forming a factor of their own.
func _special_term(grid: int) -> float:
	var total : float = score_special[grid].to_float() if grid < score_special.size() else 0.0
	for key : Vector3i in scores_cell:
		if key.x == grid: total += scores_cell[key].to_float()
	return total

## A flat per-grid bucket plus every level of its raised companion.
func _flat_and_raised(flat: Array[BigNumber], raised: Array[Array], grid: int) -> float:
	var total : float = flat[grid].to_float() if grid < flat.size() else 0.0
	if grid < raised.size():
		for bn : BigNumber in raised[grid]:
			total += bn.to_float()
	return total

## Adds to one CELL's bucket, creating it at zero on first use. Buckets are created lazily
## because a cell only gets one once it has scored, and a grid can change shape under an
## effect -- a missing bucket reads as "has not scored", never as an error.
func bank_cell_score(grid: int, cell: Vector2i, amount: int) -> void:
	var key := Vector3i(grid, cell.x, cell.y)
	if not scores_cell.has(key):
		scores_cell[key] = _zero_big_number()
	scores_cell[key].plus_equals(amount)

## One cell's banked vertical score, 0 when that cell has never scored.
func cell_score(grid: int, cell: Vector2i) -> float:
	var key := Vector3i(grid, cell.x, cell.y)
	return scores_cell[key].to_float() if scores_cell.has(key) else 0.0

## Grows a per-grid bucket array to `n` entries, seeding new ones at zero. Buckets are created
## lazily because a grid can be added mid-show, and a missing bucket must read as "has not
## scored" rather than as an error.
func resize_grid_bucket(bucket: Array[BigNumber], n: int) -> void:
	if bucket.size() < n: bucket.resize(n)
	for i in bucket.size():
		# A resize leaves NULL holes, and a caller may have grown the array itself, so fill
		# every empty slot rather than only the ones this call appended.
		if not bucket[i]: bucket[i] = _zero_big_number()

## The same, one level deeper: `levels[grid][height]`, both dimensions grown as needed.
func resize_grid_levels(levels: Array[Array], grids_n: int, heights_n: int) -> void:
	while levels.size() < grids_n:
		levels.append([] as Array[BigNumber])
	for i in grids_n:
		var level : Array[BigNumber] = levels[i]
		while level.size() < heights_n:
			level.append(_zero_big_number())
		levels[i] = level

## Drops grid `index`'s score buckets and re-indexes every later grid down by one, keeping every
## bucket aligned with `grids` after a grid is removed. `total_score` is untouched -- a removed
## grid's LABELS go, its already-banked contribution does not.
func remove_grid_score_data(index: int) -> void:
	if index >= 0 and index < scores_row.size(): scores_row.remove_at(index)
	if index >= 0 and index < scores_col.size(): scores_col.remove_at(index)
	if index >= 0 and index < score_special.size(): score_special.remove_at(index)
	if index >= 0 and index < scores_row_h.size(): scores_row_h.remove_at(index)
	if index >= 0 and index < scores_col_h.size(): scores_col_h.remove_at(index)
	var kept : Dictionary[Vector3i, BigNumber] = {}
	for key : Vector3i in scores_cell:
		if key.x == index: continue
		var out_key := key
		if key.x > index: out_key = Vector3i(key.x - 1, key.y, key.z)
		kept[out_key] = scores_cell[key]
	scores_cell = kept

## Deep copy of a coordinate-keyed BigNumber dictionary -- the same RefCounted trap as the
## arrays: duplicate_deep cannot see a BigNumber, so every value is rebuilt by hand.
func duplicate_big_number_dict(d:Dictionary[Vector3i, BigNumber]) -> Dictionary[Vector3i, BigNumber]:
	var out : Dictionary[Vector3i, BigNumber] = {}
	for key : Vector3i in d:
		var bn := BigNumber.new()
		bn.mantissa = d[key].mantissa
		bn.exponent = d[key].exponent
		out[key] = bn
	return out

func duplicate_big_number_2d_array(a:Array[Array]) -> Array[Array]:
	var out : Array[Array] = []
	out.resize(a.size())
	for i in a.size():
		out[i] = duplicate_big_number_array(a[i])
	return out

## Flattens a 2-D BigNumber array grid-major into one mantissa/exponent pair plus a per-grid
## LENGTH, which is what lets unpack rebuild each grid's inner array at exactly its own size --
## the lengths differ per grid and cannot be recovered from the flat arrays alone.
func _pack_2d(src:Array[Array]) -> Array:
	var mant := PackedFloat64Array()
	var exp := PackedInt64Array()
	var lens := PackedInt32Array()
	for level : Array[BigNumber] in src:
		lens.append(level.size())
		for bn : BigNumber in level:
			mant.append(bn.mantissa)
			exp.append(bn.exponent)
	return [mant, exp, lens]

## Rebuilds a 2-D BigNumber array from the flat pair plus the per-grid lengths.
func _unpack_2d(mant:PackedFloat64Array, exp:PackedInt64Array, lens:PackedInt32Array) -> Array[Array]:
	var out : Array[Array] = []
	var at := 0
	for n : int in lens:
		var level : Array[BigNumber] = []
		level.resize(n)
		for i in n:
			var bn := BigNumber.new()
			bn.mantissa = mant[at + i]
			bn.exponent = exp[at + i]
			level[i] = bn
		at += n
		out.append(level)
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
