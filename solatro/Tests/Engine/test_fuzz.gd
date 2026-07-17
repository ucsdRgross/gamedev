extends TestSuite
# res://Tests/Engine/test_fuzz.gd
# F1 random-walk board fuzz (UNIT_TESTS_PLAN.md §8) against Board.move_stack +
# GameData.validate(). Seeded and deterministic: on failure it prints the seed and
# the last actions — rerun with that seed in `fuzz_seed` to reproduce.
# Pure GameData/Board layer (no Game node, no mods) so every state is fully checked.
#
# CATEGORY MAP: BEHAVIOR — the properties asserted (board always validates, cards are
# never created/destroyed by moves, rejected moves change nothing) are game-level
# invariants, whatever the internals look like.

@export var fuzz_seed : int = 0        #0 = randomize (seed is printed either way)
@export var iterations : int = 500

const LOG_TAIL := 50

var _rng := RandomNumberGenerator.new()
var _log : Array[String] = []
# The walk's current state, kept as a member so _ready can break the CardData<->pip-suit
# RefCounted cycles at the end whichever way the walk exited (leak-canary discipline).
var _s : GameData = null
# Reusable off-board probe cards, one per site (fresh m_card per use leaked its suit cycle
# 500+ times a run). Never board-inserted — every use is a deliberately rejected operation.
var _stranger_probe := TestFactories.m_card(1, 1)
var _stranger_moving := TestFactories.m_card(1, 1)
var _stranger_anchor := TestFactories.m_card(1, 1)

func suite_name() -> String:
	return "BOARD FUZZ"

func _ready() -> void:
	TestLog.line("============ BOARD FUZZ (F1) ============")
	behavior_section("RANDOM WALK INVARIANTS")
	if fuzz_seed == 0:
		_rng.randomize()
		fuzz_seed = int(_rng.seed)
	_rng.seed = fuzz_seed
	TestLog.line("seed: %d, iterations: %d" % [fuzz_seed, iterations])
	run_random_walk()
	if _s:
		_s.unlink_modifier_backrefs()
		_s = null
	for stranger: CardData in [_stranger_probe, _stranger_moving, _stranger_anchor]:
		GameData.unlink_card_backrefs(stranger)
	if _fail == 0:
		TestLog.line("(fuzz seed %d)" % fuzz_seed)
	finish()

func fail(ctx: String, detail: String) -> void:
	check(false, ctx, detail)
	TestLog.line("  seed: %d — last %d actions:" % [fuzz_seed, mini(_log.size(), LOG_TAIL)], true)
	for line : String in _log.slice(maxi(0, _log.size() - LOG_TAIL)):
		TestLog.line("    " + line, true)

func note(action: String) -> void:
	_log.append(action)
	if _log.size() > LOG_TAIL * 2:
		_log = _log.slice(_log.size() - LOG_TAIL)


# ==============================================================================
# FIXTURE + HELPERS
# ==============================================================================

func make_state() -> GameData:
	var s := GameData.new()
	for zone_x in 2:
		var types : Array[CardData] = []
		var cols : Array[ArrayCardData] = []
		for c in 3:
			var h := TestFactories.m_card(100 + c, TestFactories.uc())
			h.stage = CardData.Stage.ZONE
			types.append(h)
			var col_cards : Array[CardData] = []
			for r in _rng.randi_range(0, 4):
				col_cards.append(TestFactories.m_card(r + 1, TestFactories.uc()))
			cols.append(TestFactories.col(col_cards))
		if zone_x == 0:
			s.upper_zone_type = types
			s.upper_zone = cols
		else:
			s.lower_zone_type = types
			s.lower_zone = cols
	for i in 6:
		var d := TestFactories.m_card(i + 1, TestFactories.uc())
		d.stage = CardData.Stage.DRAW
		s.draw_deck.append(d)
	return s

func zone(s: GameData, x: int) -> Array[ArrayCardData]:
	return s.upper_zone if x == 0 else s.lower_zone

func board_cards(s: GameData) -> Array[CardData]:
	var out : Array[CardData] = []
	for x in 2:
		for c in zone(s, x):
			out.append_array(c.datas)
	return out

## Cheap identity hash of the whole state for board-unchanged assertions.
func board_hash(s: GameData) -> String:
	var parts := []
	for arr : Array[CardData] in [s.draw_deck, s.discard_deck, s.rules_deck,
			s.upper_zone_type, s.lower_zone_type]:
		var ids := []
		for card in arr: ids.append(card.get_instance_id())
		parts.append(ids)
	for x in 2:
		var z := []
		for c in zone(s, x):
			var ids := []
			for card in c.datas: ids.append(card.get_instance_id())
			z.append(ids)
		parts.append(z)
	return str(parts)

func random_board_card(s: GameData) -> CardData:
	var pool := board_cards(s)
	return pool[_rng.randi_range(0, pool.size() - 1)] if pool.size() > 0 else null

## Independent linear locate — deliberately NOT Board.locate, so the §5.4 position
## index has a second implementation to disagree with (I4 chaos check).
func scan_locate(s: GameData, data: CardData) -> Vector3i:
	var i := s.upper_zone_type.find(data)
	if i > -1: return Vector3i(0, i, -1)
	i = s.lower_zone_type.find(data)
	if i > -1: return Vector3i(1, i, -1)
	for x in 2:
		var z := zone(s, x)
		for c in z.size():
			var row := z[c].datas.find(data)
			if row > -1: return Vector3i(x, c, row)
	return Vector3i.MIN

## Cross-check EVERY card the state knows about (zone cards, headers, draw/discard/
## rules — the last three must all be MIN) plus one off-board probe. Returns "" or
## the first mismatch description.
func verify_positions(s: GameData) -> String:
	for card in s.all_card_datas():
		if not card: continue
		var indexed := Board.locate(s, card)
		var scanned := scan_locate(s, card)
		if indexed != scanned:
			return "index %s vs scan %s for %s" % [indexed, scanned, card]
	if Board.locate(s, _stranger_probe) != Vector3i.MIN:
		return "off-board probe located at %s" % Board.locate(s, _stranger_probe)
	return ""

## Picks a moving card: usually on-board, sometimes deliberately illegal.
func random_moving(s: GameData) -> CardData:
	match _rng.randi_range(0, 9):
		0: return s.draw_deck[0] if s.draw_deck.size() > 0 else random_board_card(s)
		1: return s.upper_zone_type[_rng.randi_range(0, s.upper_zone_type.size() - 1)]
		2: return _stranger_moving #off-board entirely
		_: return random_board_card(s)

## Picks an anchor: usually legal-ish, sometimes out of bounds / hostile.
func random_anchor(s: GameData) -> Board.Anchor:
	match _rng.randi_range(0, 9):
		0: return null
		1: return Board.Anchor.column_end(_rng.randi_range(0, 1), 99) #OOB
		2: return Board.Anchor.on_top(_stranger_anchor)     #off-board anchor
		3: return Board.Anchor.on_top(
				s.upper_zone_type[_rng.randi_range(0, s.upper_zone_type.size() - 1)])
		4, 5:
			var x := _rng.randi_range(0, 1)
			return Board.Anchor.column_start(x, _rng.randi_range(0, zone(s, x).size() - 1))
		6, 7:
			var x := _rng.randi_range(0, 1)
			return Board.Anchor.column_end(x, _rng.randi_range(0, zone(s, x).size() - 1))
		_:
			var target := random_board_card(s)
			return Board.Anchor.on_top(target) if target else null


# ==============================================================================
# THE WALK
# ==============================================================================
func run_random_walk() -> void:
	var s := make_state()
	_s = s
	var expected_total := s.all_card_datas().size()

	for i in iterations:
		var action := _rng.randi_range(0, 9)
		var pre_hash := board_hash(s)
		#raw mutations below bump s.revision afterwards, exactly like the sanctioned
		#paths they simulate (MUTATION GUIDELINES) — the §5.4 position index and the
		#compare-mod cache both key on it
		match action:
			0: #draw: deck -> random column end
				if s.draw_deck.size() > 0:
					var card : CardData = s.draw_deck.pop_back()
					card.stage = CardData.Stage.PLAY
					var x := _rng.randi_range(0, 1)
					zone(s, x)[_rng.randi_range(0, zone(s, x).size() - 1)].datas.append(card)
					s.revision += 1
					note("%d: draw %s" % [i, card])
			1: #discard a random board card
				var card := random_board_card(s)
				if card:
					var loc := Board.locate(s, card)
					zone(s, loc.x)[loc.y].datas.erase(card)
					s.discard_deck.append(card)
					card.stage = CardData.Stage.DISCARD
					s.revision += 1
					note("%d: discard %s" % [i, card])
			2: #zone add / remove (lockstep, ZoneAdder-style; remove only empty columns)
				var x := _rng.randi_range(0, 1)
				var types : Array[CardData] = s.upper_zone_type if x == 0 else s.lower_zone_type
				if _rng.randf() < 0.5 or zone(s, x).size() <= 1:
					var h := TestFactories.m_card(100, TestFactories.uc())
					h.stage = CardData.Stage.ZONE
					types.append(h)
					zone(s, x).append(ArrayCardData.new())
					s.revision += 1
					expected_total += 1 #new header enters play
					note("%d: zone add x%d" % [i, x])
				else:
					var last := zone(s, x).size() - 1
					if zone(s, x)[last].datas.is_empty():
						zone(s, x).remove_at(last)
						GameData.unlink_card_backrefs(types[last])  # header leaves play for good
						types.remove_at(last)
						s.revision += 1
						expected_total -= 1 #header leaves play entirely
						note("%d: zone remove x%d" % [i, x])
			3: #NOT-a-column remove: exercise Board.remove_column's orphan return
				var x := _rng.randi_range(0, 1)
				var types : Array[CardData] = s.upper_zone_type if x == 0 else s.lower_zone_type
				if zone(s, x).size() > 1:
					var idx := _rng.randi_range(0, zone(s, x).size() - 1)
					var header := types[idx]
					var orphans := Board.remove_column(s, zone(s, x), types, idx)
					GameData.unlink_card_backrefs(header)  # header dropped inside remove_column
					#header gone entirely; orphaned column cards leave play -> discard them
					expected_total -= 1
					for card in orphans:
						s.discard_deck.append(card)
						card.stage = CardData.Stage.DISCARD
					if orphans: s.revision += 1
					note("%d: remove_column x%d idx%d (%d orphans)" % [i, x, idx, orphans.size()])
			_: #move (the main event)
				var moving := random_moving(s)
				if not moving: continue
				var count : int = [-1, 0, 1, 1, 2, 3][_rng.randi_range(0, 5)]
				var anchor := random_anchor(s)
				var res := Board.move_stack(s, moving, count, anchor)
				note("%d: move %s x%d -> %s = %s" % [i, moving, count, anchor,
						Board.ERROR_NAMES[res.code]])
				#rejected/no-op moves must leave the board bit-identical
				if res.code != Board.OK and board_hash(s) != pre_hash:
					fail("rejected move mutated the board", _log[-1])
					return

		#§5.4 position index vs an independent scan, for EVERY card, after EVERY action
		#(this builds the index, so validate()'s I4 below is armed every iteration too)
		var pos_mismatch := verify_positions(s)
		if pos_mismatch != "":
			fail("position index disagrees with scan", pos_mismatch)
			return
		#invariants after EVERY action
		var v := s.validate()
		if not v.is_empty():
			fail("validate() after action", str(v))
			return
		var total := s.all_card_datas().size()
		if total != expected_total:
			fail("card count changed", "expected %d got %d" % [expected_total, total])
			return
		#periodic state cloning: the copy must rebuild ITS OWN index (remapped card
		#instances) and keep validating — chaos coverage for undo/history/resume paths
		if i % 50 == 49:
			var old := s
			s = s.duplicate_state()
			old.unlink_modifier_backrefs()  # the pre-hop state is dropped — break its cycles
			_s = s
			note("%d: duplicate_state hop" % i)
			pos_mismatch = verify_positions(s)
			if pos_mismatch != "":
				fail("position index wrong after duplicate_state", pos_mismatch)
				return
			if not s.validate().is_empty():
				fail("validate() after duplicate_state", str(s.validate()))
				return
		_pass += 1
