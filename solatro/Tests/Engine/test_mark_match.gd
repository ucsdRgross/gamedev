extends TestSuite
# res://Tests/Engine/test_mark_match.gd

#A mark is the cell's own zone card wearing a copied face, so the engine must never treat what it
#copied as a card in play: a mark is never spotlit and it blocks nothing. CATEGORY MAP: BEHAVIOR --
#a copied skill answering the board's broadcasts is an effect the player would watch fire.
func suite_name() -> String:
	return "MARK MATCH"

## The answer a card printing both the mark's rank and its suit gives.
const RANK_AND_SUIT : int = MarkMatch.Property.RANK | MarkMatch.Property.SUIT

func _ready() -> void:
	TestLog.line("============ MARK MATCH TEST PASS ============")
	behavior_section("EACH PROPERTY MATCHES ON ITS OWN")
	await test_each_property_is_detected_independently()
	await test_a_talent_match_needs_the_same_script()
	await test_a_hat_match_needs_the_same_script()
	behavior_section("THE MATCH IS A PROPERTY OF THE LIVE BOARD")
	await test_a_repainted_suit_changes_the_match_at_once()
	await test_every_card_in_a_stack_is_tested()
	await test_an_effect_places_a_card_that_matches_the_same()
	behavior_section("A MARK OUTLIVES WHAT LANDS ON IT")
	await test_a_mark_survives_a_card_that_matched_nothing()
	await test_a_mark_matches_on_every_landing()
	behavior_section("WHAT A MATCH PAYS")
	test_the_rank_term_reads_the_rank_and_its_knobs()
	test_the_mult_terms_sum_their_shares()
	behavior_section("CONTENT MAY LOOSEN THE MATCH")
	await test_a_leniency_rule_loosens_the_match()
	behavior_section("A MARK IS NEVER SPOTLIT")
	await test_a_mark_answers_no_broadcast()
	behavior_section("A MARK BLOCKS NOTHING")
	test_a_mark_blocks_nothing()
	finish()


# ==============================================================================
# FIXTURES
# ==============================================================================

## A bare Game over one empty 5x5 grid, never added to the tree and with `view` left null.
func make_game() -> Game:
	var g := Game.new()
	g.state = TestGridFixtures.build_fix_grid_1()
	CardEnvironment.CURRENT = g
	return g

func free_game(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

## A playing card built the way a deck builds one -- a type, a suit and a rank -- carrying `skill`.
func play_card(rank: int, skill: CardModifierSkill) -> CardData:
	var card := CardData.new().with_type(TypePaper.new()) \
			.with_suit(PipSuitHoop.new()) \
			.with_rank(PipRankNumeral.new().with_value(float(rank))) \
			.with_skill(skill)
	card.stage = CardData.Stage.PLAY
	return card

#PLAN_DECK's card of `suit` and `rank`, staged as though in play. A FRESH instance per call,
#because a card sits in one cell at a time and several of these rows fill several cells.
func plan_card(suit: GDScript, rank: int) -> CardData:
	var card : CardData = TestDecks.plan_deck()[PipSuit.STANDARD.find(suit) * 5 + rank - 1]
	assert(card.rank.value == float(rank) and is_same(card.suit.get_script(), suit),
			"PLAN_DECK is the four standard suits in order, ranks 1 to 5")
	card.stage = CardData.Stage.PLAY
	return card

## Grid 0's cell (x, y) as the coordinate a match is asked about; a cell names no height.
func cell(x: int, y: int) -> BoardCoord:
	return BoardCoord.new(0, x, y, 0)

## Marks grid 0's cell (x, y) from `source` and hands back the cell's own zone card.
func mark_cell(state: GameData, x: int, y: int, source: CardData) -> CardData:
	var grid : GridData = state.grids[0]
	var mark : CardData = grid.cell_types[grid.cell_index(x, y)]
	BoardPlan.write_mark(mark, source, false)
	return mark

## Puts `card` in grid 0's cell (x, y) through the board's own placement, where nothing covers it.
func place_in_cell(state: GameData, x: int, y: int, card: CardData) -> void:
	Board.place_in_cell(state, card, cell(x, y))

#Two lower-zone columns, which is where the coverage rule is actually observable: column 0 holds a
#stacked pair, so its bottom card is dark and its top card lit, and column 1 is left empty so its
#own header is lit.
func fill_lower(g: Game) -> Array[CardData]:
	var buried := play_card(2, SpotlightTestSkill.make("buried"))
	var cover := play_card(3, SpotlightTestSkill.make("cover"))
	var headers : Array[CardData] = [play_card(1, SpotlightTestSkill.make("head0")),
			play_card(1, SpotlightTestSkill.make("head1"))]
	for header : CardData in headers:
		header.stage = CardData.Stage.ZONE
	g.state.lower_zone_type = headers
	g.state.lower_zone = [TestFactories.col([buried, cover] as Array[CardData]),
			TestFactories.col([] as Array[CardData])] as Array[ArrayCardData]
	g.state.revision += 1
	return [buried, cover] as Array[CardData]

#Every spotlit modifier on the board EXCEPT the mark's own: the mark's own darkness is the claim
#next door, and a bare cell type answers differently from a marked one by design, so comparing it
#would measure the exclusion rather than the rule around it.
func spotlit_ids(state: GameData, mark: CardData) -> Array[int]:
	var out : Array[int] = []
	for card : CardData in state.all_card_datas():
		if card == mark: continue
		for mod : CardModifier in [card.skill, card.type, card.stamp, card.suit]:
			if mod and mod.is_spotlit(): out.append(mod.get_instance_id())
	out.sort()
	return out


#Repaints its own card's suit the way an effect would -- through the card's own setter, which
#announces itself with `data_changed` and bumps no revision.
class SuitRepaint extends CardModifierType:
	func get_str() -> String: return "SuitRepaint"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func repaint(suit: PipSuit) -> void:
		data.with_suit(suit)

## Content that counts a rank one step from the mark's as a match. A TYPE, so it is always asked.
class MarkRankNeighbours extends CardModifierType:
	func get_str() -> String: return "MarkRankNeighbours"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_mark_ranks_allow(r1: PipRank, r2: PipRank) -> bool:
		return is_equal_approx(absf(float(r1.value) - float(r2.value)), 1.0)


# ==============================================================================
# TP-20, TP-21, TP-22 -- one answer per printed property
# ==============================================================================

#TP-20: each property is asked on its own and paid on its own, so one card printing a 5 of Hoops
#gives three different answers on three different marks -- and an unmarked cell answers nothing at
#all, which is what keeps an empty board silent.
func test_each_property_is_detected_independently() -> void:
	var g := make_game()
	mark_cell(g.state, 0, 0, plan_card(PipSuitKnife, 5))
	mark_cell(g.state, 1, 0, plan_card(PipSuitHoop, 3))
	mark_cell(g.state, 2, 0, plan_card(PipSuitHoop, 5))
	var on_rank := plan_card(PipSuitHoop, 5)
	var on_suit := plan_card(PipSuitHoop, 5)
	var on_both := plan_card(PipSuitHoop, 5)
	var on_bare := plan_card(PipSuitHoop, 5)
	place_in_cell(g.state, 0, 0, on_rank)
	place_in_cell(g.state, 1, 0, on_suit)
	place_in_cell(g.state, 2, 0, on_both)
	place_in_cell(g.state, 3, 0, on_bare)
	var rank_only := await MarkMatch.matches_at(g.state, on_rank, cell(0, 0))
	var suit_only := await MarkMatch.matches_at(g.state, on_suit, cell(1, 0))
	var both := await MarkMatch.matches_at(g.state, on_both, cell(2, 0))
	var bare := await MarkMatch.matches_at(g.state, on_bare, cell(3, 0))
	check(rank_only == MarkMatch.Property.RANK,
			"TP-20: a 5 of Hoops on a mark of 5 of Knives matches the RANK and nothing else",
			"got %d" % rank_only)
	check(suit_only == MarkMatch.Property.SUIT,
			"TP-20: the same card on a mark of 3 of Hoops matches the SUIT and nothing else",
			"got %d" % suit_only)
	check(both == RANK_AND_SUIT,
			"TP-20: and on a mark of 5 of Hoops it matches both",
			"got %d" % both)
	check(bare == 0, "TP-20: an unmarked cell matches nothing", "got %d" % bare)
	var off_board : int = await MarkMatch.matches_at(g.state, on_both, cell(9, 9))
	check(off_board == 0,
			"TP-20: nor does a coordinate that names no cell of any grid", "got %d" % off_board)
	free_game(g)

#TP-21: a mark carries its own COPY of the skill it names, so the only identity a talent match can
#test is the script -- two skills that merely both exist are not a match.
func test_a_talent_match_needs_the_same_script() -> void:
	var g := make_game()
	mark_cell(g.state, 0, 0,
			plan_card(PipSuitHoop, 5).with_skill(SpotlightTestSkill.make("marked")))
	mark_cell(g.state, 1, 0,
			plan_card(PipSuitKnife, 4).with_skill(SpotlightTestSkill.make("marked")))
	mark_cell(g.state, 2, 0, plan_card(PipSuitBall, 3))
	var same := plan_card(PipSuitHoop, 5).with_skill(SpotlightTestSkill.make("placed"))
	var different := plan_card(PipSuitKnife, 4).with_skill(SkillExtraPoint.new())
	var unmatched := plan_card(PipSuitBall, 3).with_skill(SkillExtraPoint.new())
	place_in_cell(g.state, 0, 0, same)
	place_in_cell(g.state, 1, 0, different)
	place_in_cell(g.state, 2, 0, unmatched)
	var matched_same := await MarkMatch.matches_at(g.state, same, cell(0, 0))
	var matched_other := await MarkMatch.matches_at(g.state, different, cell(1, 0))
	var matched_bare := await MarkMatch.matches_at(g.state, unmatched, cell(2, 0))
	check(matched_same & MarkMatch.Property.TALENT != 0,
			"TP-21: two skills of one script are a talent match", "got %d" % matched_same)
	check(matched_other == RANK_AND_SUIT,
			"TP-21: two different skill scripts are not, and the rank and suit still are",
			"got %d" % matched_other)
	check(matched_bare == RANK_AND_SUIT,
			"TP-21: nor is a skill on the card alone, with the mark carrying none",
			"got %d" % matched_bare)
	free_game(g)

#TP-22: the hat slot answers the same question as the talent slot and answers it separately, so a
#stamp match is script identity too.
func test_a_hat_match_needs_the_same_script() -> void:
	var g := make_game()
	mark_cell(g.state, 0, 0, plan_card(PipSuitHoop, 5).with_stamp(StampDoubleTrigger.new()))
	mark_cell(g.state, 1, 0, plan_card(PipSuitKnife, 4).with_stamp(StampDoubleTrigger.new()))
	var same := plan_card(PipSuitHoop, 5).with_stamp(StampDoubleTrigger.new())
	var different := plan_card(PipSuitKnife, 4).with_stamp(StampRevealing.new())
	place_in_cell(g.state, 0, 0, same)
	place_in_cell(g.state, 1, 0, different)
	var matched_same := await MarkMatch.matches_at(g.state, same, cell(0, 0))
	var matched_other := await MarkMatch.matches_at(g.state, different, cell(1, 0))
	check(matched_same & MarkMatch.Property.HAT != 0,
			"TP-22: two stamps of one script are a hat match", "got %d" % matched_same)
	check(matched_other == RANK_AND_SUIT,
			"TP-22: two different stamp scripts are not", "got %d" % matched_other)
	free_game(g)


# ==============================================================================
# TP-23, TP-24, TP-25 -- the match is a question asked of the board, every time
# ==============================================================================

#TP-23: the match is derived live, so an effect repainting a suit mid-show creates one. ⚠ THE
#REVISION IS THE POINT: a repaint announces itself with `data_changed` and bumps nothing, so a
#verdict remembered against the revision would still be answering about the old suit.
func test_a_repainted_suit_changes_the_match_at_once() -> void:
	var g := make_game()
	mark_cell(g.state, 0, 0, plan_card(PipSuitHoop, 5))
	var card := plan_card(PipSuitKnife, 5)
	var repaint := SuitRepaint.new()
	card.with_type(repaint)
	place_in_cell(g.state, 0, 0, card)
	var before := await MarkMatch.matches_at(g.state, card, cell(0, 0))
	var revision := g.state.revision
	repaint.repaint(PipSuitHoop.new())
	check(g.state.revision == revision,
			"TP-23 precondition: repainting a suit bumps no revision",
			"%d became %d" % [revision, g.state.revision])
	var after := await MarkMatch.matches_at(g.state, card, cell(0, 0))
	check(before == MarkMatch.Property.RANK,
			"TP-23: the Knives card matched the Hoops mark on rank alone",
			"got %d" % before)
	check(after == RANK_AND_SUIT,
			"TP-23: and the very next call sees the repainted suit match too", "got %d" % after)
	free_game(g)

#TP-24: a mark belongs to the CELL, not to the card on top of it, so every card in the stack is
#asked -- one cell's mark can be matched as many times as cards stack on it.
func test_every_card_in_a_stack_is_tested() -> void:
	var g := make_game()
	mark_cell(g.state, 0, 0, plan_card(PipSuitHoop, 5))
	var stack : Array[CardData] = [plan_card(PipSuitHoop, 5), plan_card(PipSuitHoop, 5),
			plan_card(PipSuitHoop, 5)]
	for card : CardData in stack:
		place_in_cell(g.state, 0, 0, card)
	var grid : GridData = g.state.grids[0]
	check(grid.cells[grid.cell_index(0, 0)].datas.size() == 3,
			"TP-24 precondition: the cell is three cards deep",
			"got %d" % grid.cells[grid.cell_index(0, 0)].datas.size())
	var matches := 0
	for card : CardData in stack:
		if await MarkMatch.matches_at(g.state, card, cell(0, 0)) == RANK_AND_SUIT: matches += 1
	check(matches == 3, "TP-24: all three cards in the stack match, not only the one at height 0",
			"%d of 3 matched" % matches)
	free_game(g)

#TP-25: a card in a cell is a card in a cell. The two placements differ only in `processing`, which
#is what tells an effect placing mid-cascade from a player putting a card down.
func test_an_effect_places_a_card_that_matches_the_same() -> void:
	var g := make_game()
	mark_cell(g.state, 0, 0, plan_card(PipSuitHoop, 5))
	mark_cell(g.state, 1, 0, plan_card(PipSuitHoop, 5))
	var by_player := plan_card(PipSuitHoop, 5)
	await g.place_card_in_grid(by_player, cell(0, 0))
	var by_effect := plan_card(PipSuitHoop, 5)
	g.processing = true
	await g.place_card_in_grid(by_effect, cell(1, 0))
	g.processing = false
	var player_match := await MarkMatch.matches_at(g.state, by_player, cell(0, 0))
	var effect_match := await MarkMatch.matches_at(g.state, by_effect, cell(1, 0))
	check(g.state.card_at(cell(0, 0)) == by_player and g.state.card_at(cell(1, 0)) == by_effect,
			"TP-25 precondition: both placements landed in their own cell")
	check(player_match == RANK_AND_SUIT and effect_match == player_match,
			"TP-25: a card an effect placed matches exactly as one the player placed",
			"player %d, effect %d" % [player_match, effect_match])
	free_game(g)


# ==============================================================================
# TP-26, TP-27 -- the mark is underneath, and it stays there
# ==============================================================================

#TP-26: a card that matches nothing changes nothing about the mark, which is still there to be
#matched by whatever lands next.
func test_a_mark_survives_a_card_that_matched_nothing() -> void:
	var g := make_game()
	var mark := mark_cell(g.state, 0, 0, plan_card(PipSuitHoop, 5))
	var stranger := plan_card(PipSuitKnife, 3)
	await g.place_card_in_grid(stranger, cell(0, 0))
	var ignored : int = await MarkMatch.matches_at(g.state, stranger, cell(0, 0))
	check(ignored == 0,
			"TP-26 precondition: a 3 of Knives on a mark of 5 of Hoops matches nothing",
			"got %d" % ignored)
	await g.remove_card_from_grid(stranger)
	check(BoardPlan.is_marked(mark),
			"TP-26: the mark is intact after the card that ignored it left")
	var matcher := plan_card(PipSuitHoop, 5)
	await g.place_card_in_grid(matcher, cell(0, 0))
	var matched : int = await MarkMatch.matches_at(g.state, matcher, cell(0, 0))
	check(matched == RANK_AND_SUIT,
			"TP-26: and the next card matches it", "got %d" % matched)
	free_game(g)

#TP-27: a mark is not spent by being hit. Three cards land on it in turn and every one of them is a
#match, which is what makes the bonus payable every time rather than once.
func test_a_mark_matches_on_every_landing() -> void:
	var g := make_game()
	mark_cell(g.state, 0, 0, plan_card(PipSuitHoop, 5))
	var matches := 0
	for _cycle : int in 3:
		var card := plan_card(PipSuitHoop, 5)
		await g.place_card_in_grid(card, cell(0, 0))
		if await MarkMatch.matches_at(g.state, card, cell(0, 0)) == RANK_AND_SUIT: matches += 1
		await g.remove_card_from_grid(card)
	check(matches == 3, "TP-27: three land-remove-land cycles report three matches",
			"%d of 3" % matches)
	free_game(g)


# ==============================================================================
# TP-35 -- what the match pays
# ==============================================================================

#TP-35: the rank term is the rank the card PRINTS, scaled and rounded up, and the two ranks that
#have no useful printed value read their own knobs instead.
func test_the_rank_term_reads_the_rank_and_its_knobs() -> void:
	var snapshot := snapshot_settings("plan_")
	var settings := SettingsManager.settings
	settings.plan_rank_match_step = 1.0
	settings.plan_ace_value = 7
	settings.plan_rank_flat_fallback = 3
	var ace := plan_card(PipSuitHoop, 1)
	check(MarkMatch.flat_bonus(ace, MarkMatch.Property.RANK) == 7,
			"TP-35: the Ace pays its own knob rather than the 1 it prints",
			"got %d" % MarkMatch.flat_bonus(ace, MarkMatch.Property.RANK))
	var nameless := plan_card(PipSuitHoop, 2)
	nameless.rank.value = NAN
	check(MarkMatch.flat_bonus(nameless, MarkMatch.Property.RANK) == 3,
			"TP-35: a rank with no value a whole number can hold pays the flat fallback",
			"got %d" % MarkMatch.flat_bonus(nameless, MarkMatch.Property.RANK))
	var half := plan_card(PipSuitHoop, 2)
	half.rank.with_value(2.5)
	check(MarkMatch.flat_bonus(half, MarkMatch.Property.RANK) == 3,
			"TP-35: a rank of 2.5 rounds UP to 3",
			"got %d" % MarkMatch.flat_bonus(half, MarkMatch.Property.RANK))
	settings.plan_rank_match_step = 0.5
	var five := plan_card(PipSuitHoop, 5)
	check(MarkMatch.flat_bonus(five, MarkMatch.Property.RANK) == 3,
			"TP-35: the step scales the printed rank, and the scaled figure rounds up as well",
			"got %d" % MarkMatch.flat_bonus(five, MarkMatch.Property.RANK))
	check(MarkMatch.flat_bonus(five, MarkMatch.Property.SUIT | MarkMatch.Property.HAT) == 0,
			"TP-35: a match on any other property pays no rank bonus")
	restore_settings_snapshot(snapshot)

#The talent and hat shares SUM rather than multiply each other, and the sum is the whole
#multiplier -- so one share of 1 is neutral and two shares of 2 make 4.
func test_the_mult_terms_sum_their_shares() -> void:
	var snapshot := snapshot_settings("plan_")
	var settings := SettingsManager.settings
	settings.plan_talent_mult = 2.0
	settings.plan_hat_mult = 3.0
	var card := plan_card(PipSuitHoop, 5)
	check(is_equal_approx(MarkMatch.mult_bonus(card, MarkMatch.Property.TALENT), 2.0),
			"a talent match contributes its own share and nothing else")
	check(is_equal_approx(MarkMatch.mult_bonus(card, MarkMatch.Property.HAT), 3.0),
			"a hat match contributes its own")
	check(is_equal_approx(MarkMatch.mult_bonus(card,
			MarkMatch.Property.TALENT | MarkMatch.Property.HAT), 5.0),
			"and the two matched together contribute the SUM of the shares, never the product")
	check(MarkMatch.mult_bonus(card, RANK_AND_SUIT) == 0.0,
			"a rank or suit match contributes no multiplier at all")
	restore_settings_snapshot(snapshot)


# ==============================================================================
# TP-39 -- content may loosen the match, through the mark's OWN hooks
# ==============================================================================

#TP-39: the leniency family is declared as comments, so a board with no implementer dispatches
#NOTHING and the printed values decide. ⚠ The counted hook NAME is what proves the mark asks its own
#family: a mark falling back to the meld hooks would leave this rule unasked.
func test_a_leniency_rule_loosens_the_match() -> void:
	var state := TestGridFixtures.build_fix_grid_1()
	var env := CountingEnvironment.new()
	add_child(env)
	mark_cell(state, 0, 0, plan_card(PipSuitKnife, 4))
	var probe := plan_card(PipSuitKnife, 5)
	place_in_cell(state, 0, 0, probe)
	var strict := await MarkMatch.matches_at(state, probe, cell(0, 0))
	check(strict == MarkMatch.Property.SUIT,
			"TP-39: with nothing implementing a mark hook, a rank one step away is no match",
			"got %d" % strict)
	check(env.total() == 0,
			"TP-39: and not one hook was dispatched -- a comment-only family opts nobody in",
			"counted %d %s" % [env.total(), str(env.dispatches)])
	env.card_collections.append([CardData.new().with_type(MarkRankNeighbours.new())]
			as Array[CardData])
	var lenient := await MarkMatch.matches_at(state, probe, cell(0, 0))
	check(lenient == RANK_AND_SUIT,
			"TP-39: a rule that allows neighbouring ranks turns the same pair into a rank match",
			"got %d" % lenient)
	var allow_calls : int = env.dispatches.get(MarkMatch.MARK_RANKS_ALLOW, 0)
	check(allow_calls >= 1,
			"TP-39: and it was asked through the mark family's own allow hook",
			"counted %s" % str(env.dispatches))
	remove_child(env)
	env.free()


# ==============================================================================
# TP-44 -- a mark answers no broadcast
# ==============================================================================

#⚠ THE SCORING BEAM IS THE LEVER, BECAUSE MEASURED: a card in a grid cell is not naturally spotlit
#at all -- the legacy position index carries no grid coordinate, so the coverage walk fails closed
#and every grid card is dark until the beam lands on it. Both cards here are forced, one control.

#⚠ A COPIED GLOBAL STAMP IS THE OTHER LEVER, and it needs no beam: a global stamp lights its card
#from anywhere, the deck included, so a mark that copied one would answer the whole board uncovered
#and unforced. It is left unforced here for exactly that reason.
func test_a_mark_answers_no_broadcast() -> void:
	var g := make_game()
	var mark := mark_cell(g.state, 0, 0, play_card(3, SpotlightTestSkill.make("mark")))
	var extra_point := mark_cell(g.state, 1, 0, play_card(4, SkillExtraPoint.new()))
	var global_source := play_card(6, SpotlightTestSkill.make("global"))
	global_source.with_stamp(StampGlobal.new())
	var global_mark := mark_cell(g.state, 2, 0, global_source)
	var control := play_card(5, SpotlightTestSkill.make("control"))
	place_in_cell(g.state, 2, 0, control)
	var mark_spy := mark.skill as SpotlightTestSkill
	var global_spy := global_mark.skill as SpotlightTestSkill
	var control_spy := control.skill as SpotlightTestSkill
	g.state.forced_spotlight[mark] = true
	g.state.forced_spotlight[extra_point] = true
	g.state.forced_spotlight[control] = true
	await g.skill_spotlight_check()
	check(control_spy.spotlight_calls == 1,
			"precondition: the control card answers the engine's spotlight sweep",
			"got %d" % control_spy.spotlight_calls)
	check(mark_spy.spotlight_calls == 0,
			"TP-44: the very same skill, copied onto a mark, answers nothing",
			"got %d" % mark_spy.spotlight_calls)
	check(global_spy.spotlight_calls == 0,
			"TP-44: a mark that copied a global stamp answers the sweep no differently",
			"got %d" % global_spy.spotlight_calls)
	await g.run_all_mods(&"on_spotlight")
	check(control_spy.spotlight_calls == 2 and mark_spy.spotlight_calls == 0,
			"TP-44: a board-wide broadcast reaches the control and never the mark",
			"control %d, mark %d" % [control_spy.spotlight_calls, mark_spy.spotlight_calls])
	check(global_spy.spotlight_calls == 0,
			"TP-44: nor does that broadcast reach the globally stamped mark",
			"got %d" % global_spy.spotlight_calls)
	check(control.skill.is_spotlit(),
			"precondition: is_spotlit() is true on the control's own skill")
	check(not extra_point.skill.is_spotlit(),
			"TP-44: is_spotlit() is false on a mark's copied skill")
	check(not mark.type.is_spotlit(),
			"TP-44: and false on the marked cell's own type")
	check(not global_mark.stamp.is_spotlit(),
			"TP-44: is_spotlit() is false on a mark's copied global stamp")
	check(not global_mark.skill.is_spotlit(),
			"TP-44: a copied global stamp lights nothing else on its mark either")
	free_game(g)


# ==============================================================================
# TP-45 -- a mark blocks nothing
# ==============================================================================

#TP-45: a mark is transparent to the spotlight rule -- it covers nothing, so every answer the rule
#gives elsewhere on the board has to be the same with the mark there and gone.
func test_a_mark_blocks_nothing() -> void:
	var g := make_game()
	var stacked := fill_lower(g)
	var mark := mark_cell(g.state, 0, 0, play_card(3, SpotlightTestSkill.make("mark")))
	for mod : CardModifier in [mark.skill, mark.type, mark.stamp, mark.suit]:
		if mod:
			check(not mod.blocks_spotlight(),
					"TP-45: a mark's %s blocks nothing" % mod.get_str())
	var with_mark := spotlit_ids(g.state, mark)
	check(not with_mark.is_empty() and not stacked[0].skill.is_spotlit()
			and stacked[1].skill.is_spotlit(),
			"precondition: the coverage rule is live in this fixture, with a lit and a dark card",
			"%d spotlit mods" % with_mark.size())
	BoardPlan.clear_mark(mark)
	g.state.revision += 1
	var without_mark := spotlit_ids(g.state, mark)
	check(with_mark == without_mark,
			"TP-45: the board's spotlit set is the same whether the cell is marked or not",
			"%d with the mark, %d without" % [with_mark.size(), without_mark.size()])
	free_game(g)
