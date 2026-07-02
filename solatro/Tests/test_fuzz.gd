extends Node
# res://Tests/test_fuzz.gd
# F1 random-walk board fuzz (UNIT_TESTS_PLAN.md §8) against Board.move_stack +
# GameData.validate(). Seeded and deterministic: on failure it prints the seed and
# the last actions — rerun with that seed in `fuzz_seed` to reproduce.
# Pure GameData/Board layer (no Game node, no mods) so every state is fully checked.

@export var fuzz_seed : int = 0        #0 = randomize (seed is printed either way)
@export var iterations : int = 500

const LOG_TAIL := 50

var _pass := 0
var _fail := 0
var _rng := RandomNumberGenerator.new()
var _log : Array[String] = []

func _ready() -> void:
	print("============ BOARD FUZZ (F1) ============")
	if fuzz_seed == 0:
		_rng.randomize()
		fuzz_seed = int(_rng.seed)
	_rng.seed = fuzz_seed
	print("seed: %d, iterations: %d" % [fuzz_seed, iterations])
	run_random_walk()
	if _fail == 0:
		print("============ FUZZ: ALL %d CHECKS PASSED (seed %d) ============" % [_pass, fuzz_seed])
	else:
		printerr("============ FUZZ: %d FAILED of %d (SEED %d) ============" % [_fail, _pass + _fail, fuzz_seed])

func fail(ctx: String, detail: String) -> void:
	_fail += 1
	printerr("[FAIL] ", ctx, " -- ", detail)
	printerr("  seed: %d — last %d actions:" % [fuzz_seed, mini(_log.size(), LOG_TAIL)])
	for line : String in _log.slice(maxi(0, _log.size() - LOG_TAIL)):
		printerr("    ", line)

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

## Picks a moving card: usually on-board, sometimes deliberately illegal.
func random_moving(s: GameData) -> CardData:
	match _rng.randi_range(0, 9):
		0: return s.draw_deck[0] if s.draw_deck.size() > 0 else random_board_card(s)
		1: return s.upper_zone_type[_rng.randi_range(0, s.upper_zone_type.size() - 1)]
		2: return TestFactories.m_card(1, 1) #off-board entirely
		_: return random_board_card(s)

## Picks an anchor: usually legal-ish, sometimes out of bounds / hostile.
func random_anchor(s: GameData) -> Board.Anchor:
	match _rng.randi_range(0, 9):
		0: return null
		1: return Board.Anchor.column_end(_rng.randi_range(0, 1), 99) #OOB
		2: return Board.Anchor.on_top(TestFactories.m_card(1, 1))     #off-board anchor
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
	var expected_total := s.all_card_datas().size()

	for i in iterations:
		var action := _rng.randi_range(0, 9)
		var pre_hash := board_hash(s)
		match action:
			0: #draw: deck -> random column end
				if s.draw_deck.size() > 0:
					var card : CardData = s.draw_deck.pop_back()
					card.stage = CardData.Stage.PLAY
					var x := _rng.randi_range(0, 1)
					zone(s, x)[_rng.randi_range(0, zone(s, x).size() - 1)].datas.append(card)
					note("%d: draw %s" % [i, card])
			1: #discard a random board card
				var card := random_board_card(s)
				if card:
					var loc := Board.locate(s, card)
					zone(s, loc.x)[loc.y].datas.erase(card)
					s.discard_deck.append(card)
					card.stage = CardData.Stage.DISCARD
					note("%d: discard %s" % [i, card])
			2: #zone add / remove (lockstep, ZoneAdder-style; remove only empty columns)
				var x := _rng.randi_range(0, 1)
				var types : Array[CardData] = s.upper_zone_type if x == 0 else s.lower_zone_type
				if _rng.randf() < 0.5 or zone(s, x).size() <= 1:
					var h := TestFactories.m_card(100, TestFactories.uc())
					h.stage = CardData.Stage.ZONE
					types.append(h)
					zone(s, x).append(ArrayCardData.new())
					expected_total += 1 #new header enters play
					note("%d: zone add x%d" % [i, x])
				else:
					var last := zone(s, x).size() - 1
					if zone(s, x)[last].datas.is_empty():
						zone(s, x).remove_at(last)
						types.remove_at(last)
						expected_total -= 1 #header leaves play entirely
						note("%d: zone remove x%d" % [i, x])
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

		#invariants after EVERY action
		var v := s.validate()
		if not v.is_empty():
			fail("validate() after action", str(v))
			return
		var total := s.all_card_datas().size()
		if total != expected_total:
			fail("card count changed", "expected %d got %d" % [expected_total, total])
			return
		_pass += 1
