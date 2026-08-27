extends TestSuite
# res://Tests/Engine/test_grid_cards.gd
# Phase 4 of the poker-patience board: the rules cards that manage the grid board itself.
# TP-62..TP-65 -- SkillGridAllotment matches the grid count to the deck size at game start.

func suite_name() -> String:
	return "GRID CARDS"

func _ready() -> void:
	TestLog.line("============ GRID CARDS TEST PASS ============")
	check_all_tests_registered()
	run_effect_api_boundary_gate()
	await run_small_deck_yields_one_grid_test()
	await run_the_52_53_boundary_test()
	await run_105_yields_three_grids_test()
	await run_the_cap_holds_test()
	finish()

# ==============================================================================
# Helpers: a bare Game wired to a rules deck holding one spotlit SkillGridAllotment,
# mirroring test_grid_economy's detector_game.
# ==============================================================================
func _rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.spotlit = true
	return c

## A Game whose draw_deck is `deck` and whose only rules card is a spotlit
## SkillGridAllotment -- enough to fire on_game_start the way Levels/game.gd does.
func _allotment_game(deck: Array[CardData]) -> Game:
	var g := Game.new()
	var state := GameData.new()
	state.draw_deck = deck
	state.rules_deck = [_rules_card(SkillGridAllotment.new())] as Array[CardData]
	g.state = state
	CardEnvironment.CURRENT = g
	return g

func _free_game(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

# ==============================================================================
# TP-62 -- FIX-DECK-20 -> 1 grid.
# ==============================================================================
func run_small_deck_yields_one_grid_test() -> void:
	behavior_section("A SMALL DECK YIELDS ONE GRID")
	var g := _allotment_game(TestDecks.deck_20())
	await g.run_all_mods(&"on_game_start")
	check(g.state.grids.size() == 1,
			"a 20-card deck allots exactly 1 grid",
			"got %d" % g.state.grids.size())
	_free_game(g)

# ==============================================================================
# TP-63 -- FIX-DECK-52 -> 1 grid; FIX-DECK-53 -> 2. The exact-multiple boundary.
# ==============================================================================
func run_the_52_53_boundary_test() -> void:
	behavior_section("THE 52/53 BOUNDARY")
	var g52 := _allotment_game(TestDecks.deck_standard_52())
	await g52.run_all_mods(&"on_game_start")
	check(g52.state.grids.size() == 1,
			"an exact multiple of grid_cards_per_unlock (52) does NOT round up",
			"got %d" % g52.state.grids.size())
	_free_game(g52)

	var g53 := _allotment_game(TestDecks.deck_53())
	await g53.run_all_mods(&"on_game_start")
	check(g53.state.grids.size() == 2,
			"one card past the boundary (53) rounds up to 2",
			"got %d" % g53.state.grids.size())
	_free_game(g53)

# ==============================================================================
# TP-64 -- FIX-DECK-105 -> 3 grids.
# ==============================================================================
func run_105_yields_three_grids_test() -> void:
	behavior_section("105 CARDS YIELDS THREE GRIDS")
	var g := _allotment_game(TestDecks.deck_105())
	await g.run_all_mods(&"on_game_start")
	check(g.state.grids.size() == 3,
			"a 105-card deck allots exactly 3 grids",
			"got %d" % g.state.grids.size())
	_free_game(g)

# ==============================================================================
# TP-65 -- the cap holds: a 300-card deck still yields 3, not more.
# ==============================================================================
func run_the_cap_holds_test() -> void:
	behavior_section("THE CAP HOLDS")
	var big : Array[CardData] = []
	for _i : int in 6:
		big.append_array(TestDecks.deck_standard_52())
	var g := _allotment_game(big)
	await g.run_all_mods(&"on_game_start")
	check(g.state.grids.size() == 3,
			"a deck far past 3 grids' worth is still capped at grid_max_count (3)",
			"got %d" % g.state.grids.size())
	_free_game(g)

# ==============================================================================
# THE CARD EFFECT API BOUNDARY GATE.
#
# A card modifier implements its effect through CardEffectApi and NEVER reaches `Game`,
# `GameData` or `Board` directly. The rule is ENFORCED here rather than documented, because
# it was documented for a long time -- CardModifier's own comment said "State MUTATION
# should still go through Game's API" -- and 26 card files reached past it anyway.
#
# Scans every modifier under Cards/ as TEXT. A modifier is any file whose `extends` names a
# CardModifier type; the card's VISUAL node and the prop classes are not modifiers and are
# not scanned, which is also why the layer needs no `view` accessor.
# ==============================================================================

## `extends` bases that make a file a card modifier rather than a visual or a data holder.
const MODIFIER_BASES : Array[String] = [
	"CardModifier", "CardModifierSkill", "CardModifierType", "CardModifierStamp",
	"CardModifierStatus", "PipSuit", "PipRank", "ZoneAdder",
]

## What a modifier may not name. `Board` is included because a modifier reaching it still
## edits the board behind the layer, which is the thing the layer exists to prevent.
const FORBIDDEN_IN_MODIFIERS : Array[String] = ["game.", "Game.", "GameData", "Board."]

func run_effect_api_boundary_gate() -> void:
	implementation_section("CARD EFFECT API BOUNDARY")
	var scanned := 0
	var offenders : Array[String] = []
	for path : String in _all_card_scripts("res://Cards"):
		var f := FileAccess.open(path, FileAccess.READ)
		if not f: continue
		var text := f.get_as_text()
		if not _is_modifier(text): continue
		scanned += 1
		var n := 0
		for raw : String in text.split("\n"):
			n += 1
			var line := raw.strip_edges()
			# Comments explain the rule and must be free to name what they forbid.
			if line.begins_with("#"): continue
			for bad : String in FORBIDDEN_IN_MODIFIERS:
				if line.contains(bad):
					offenders.append("%s:%d: %s" % [path, n, line])
					break
	check(scanned >= 10, "the gate actually found the modifiers to scan",
			"only %d modifier scripts scanned" % scanned)
	check(offenders.is_empty(),
			"no card modifier reaches Game, GameData or Board directly -- effects go through the api",
			"\n".join(offenders))

## Does this script extend a card-modifier type?
func _is_modifier(text: String) -> bool:
	for raw : String in text.split("\n"):
		if not raw.begins_with("extends "): continue
		var base := raw.substr(8).strip_edges()
		return MODIFIER_BASES.has(base)
	return false

## Every .gd under `root`, recursively. Test-only helper.
func _all_card_scripts(root: String) -> Array[String]:
	var out : Array[String] = []
	var dirs : Array[String] = [root]
	while not dirs.is_empty():
		var d : String = dirs.pop_back()
		var dir := DirAccess.open(d)
		if not dir: continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("."):
				name = dir.get_next()
				continue
			var full : String = d.path_join(name)
			if dir.current_is_dir(): dirs.append(full)
			elif name.ends_with(".gd"): out.append(full)
			name = dir.get_next()
		dir.list_dir_end()
	return out
