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
	behavior_section("WHAT A LINE BANKS")
	await test_a_rank_match_is_added_to_the_line()
	await test_a_line_with_no_mult_is_never_multiplied_to_nothing()
	await test_mark_effects_sum_into_one_multiplier()
	await test_a_cover_is_announced_and_a_match_adds_its_own_hook()
	await test_a_marks_copied_skill_is_dispatched_the_mark_hooks()
	await test_a_flush_keeps_its_own_score()
	await test_a_match_outside_the_meld_pays_nothing()
	await test_a_card_pays_into_every_line_it_completes()
	await test_a_match_registers_no_combo_class()
	behavior_section("A MATCHED SUIT FIRES ONCE PER MELD MEMBERSHIP")
	await test_a_matched_suit_fires_once_per_meld_membership()
	behavior_section("CONTENT MAY LOOSEN THE MATCH")
	await test_a_leniency_rule_loosens_the_match()
	behavior_section("A MARK IS NEVER SPOTLIT")
	await test_a_mark_answers_no_broadcast()
	await test_a_marks_copied_stamp_answers_no_broadcast()
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


#The REAL scorer in the rules deck: every row below is scored by a placement completing a line,
#which is the path the shipped game takes -- the composition is never called directly.
func detector_game(state: GameData) -> Game:
	var detector := SkillLineDetector.new()
	detector.spotlit = true
	var rules := CardData.new().with_skill(detector)
	rules.stage = CardData.Stage.RULES
	state.rules_deck = [rules] as Array[CardData]
	var g := Game.new()
	g.state = state
	CardEnvironment.CURRENT = g
	return g

## A card of `rank` in a suit nothing else in the run shares, so no row flushes by accident.
func row_card(rank: int) -> CardData:
	return TestFactories.m_card(float(rank), TestFactories.uc())

#A card of `rank` printing a real KNIFE -- the only suit-effect source these boards carry, because
#the test suit every other card prints spawns nothing whatever stands under it. A knife's props score
#each no-skill card of its row, so what it fires is visible as points in that row's own bucket.
func knife_card(rank: int) -> CardData:
	return play_card(rank, null).with_suit(PipSuitKnife.new())

## Five cards whose best meld is the PAIR of 7s -- the two cards a mark under cell 0 or 1 can pay.
func pair_row() -> Array[CardData]:
	return [row_card(7), row_card(7), row_card(3), row_card(9), row_card(11)] as Array[CardData]

## Five cards whose best meld is the three 7s, leaving cells 3 and 4 outside it.
func triple_row() -> Array[CardData]:
	return [row_card(7), row_card(7), row_card(7), row_card(11), row_card(3)] as Array[CardData]

## Five cards of ONE suit, the 9 first so a mark under cell 0 pays a meld card of the flush.
func flush_row() -> Array[CardData]:
	var suit := TestFactories.uc()
	var out : Array[CardData] = []
	for rank : int in [9, 2, 4, 6, 8] as Array[int]:
		out.append(TestFactories.m_card(float(rank), suit))
	return out

## The same five ranks in five different suits -- the flush row's control.
func unsuited_row() -> Array[CardData]:
	var out : Array[CardData] = []
	for rank : int in [9, 2, 4, 6, 8] as Array[int]:
		out.append(row_card(rank))
	return out

#Grid 0's row 0, marked cell by cell, then filled left to right with the LAST card placed through
#the game -- that placement is what completes the row and scores it. The game is handed back alive,
#so a row reads the bucket it banked into rather than a number the test worked out for itself.
func scored_row(cards: Array[CardData], marks: Dictionary[int, CardData]) -> Game:
	var g := detector_game(TestGridFixtures.build_fix_grid_1())
	for x : int in marks:
		mark_cell(g.state, x, 0, marks[x])
	for x : int in cards.size() - 1:
		place_in_cell(g.state, x, 0, cards[x])
	await g.place_card_in_grid(cards[cards.size() - 1], cell(cards.size() - 1, 0))
	return g

## What grid 0's row 0 banked: the BigNumber the player's own score is built from.
func row_banked(g: Game) -> float:
	return g.state.line_score(g.state.scores_row, 0, 0, 0)

## A mark whose effect is worth twice the line, spelled as the `+2` the sum of shares expects.
func mult_mark() -> CardData:
	return row_card(2).with_stamp(LineMultStamp.new())

#Row 0, column 0 and the main diagonal each one card short at the corner, every card of one rank so
#all three melds hold every card of their line. Returns what the row, the column and the diagonal
#banked, in that order.
func banked_corner_lines(marks: Dictionary[int, CardData]) -> Array[float]:
	var g := detector_game(TestGridFixtures.build_fix_grid_1())
	for x : int in marks:
		mark_cell(g.state, x, 0, marks[x])
	for i : int in 5:
		for spot : Vector2i in [Vector2i(i, 0), Vector2i(0, i), Vector2i(i, i)] as Array[Vector2i]:
			if spot == Vector2i.ZERO or g.state.card_at(cell(spot.x, spot.y)): continue
			place_in_cell(g.state, spot.x, spot.y, row_card(7))
	await g.place_card_in_grid(row_card(7), cell(0, 0))
	var diagonal : float = g.state.score_special[0].to_float() \
			if not g.state.score_special.is_empty() else 0.0
	var banked : Array[float] = [row_banked(g), g.state.line_score(g.state.scores_col, 0, 0, 0),
			diagonal]
	free_game(g)
	return banked


#Grid 0's row 2 and column 2 of one rank, so each meld holds every card of its line, with a knife at
#their crossing. `complete_column` leaves the column one short when the knife should belong to ONE
#meld, and `marked` writes the SUIT-only mark that is the whole of what lets its props fire.
func banked_knife_cross(marked: bool, complete_column: bool) -> float:
	var g := detector_game(TestGridFixtures.build_fix_grid_1())
	if marked:
		mark_cell(g.state, 2, 2, knife_card(2))
	for i : int in 5:
		if i == 2: continue
		place_in_cell(g.state, i, 2, row_card(3))
		if complete_column or i != 4:
			place_in_cell(g.state, 2, i, row_card(3))
	await g.place_card_in_grid(knife_card(3), cell(2, 2))
	var banked : float = g.state.line_score(g.state.scores_row, 0, 2, 0)
	free_game(g)
	return banked


#Counts the two mark hooks and remembers the level each arrived with. EVERY cover is announced and a
#match adds its own hook on top, so the two counts are the only thing telling the cases apart.
class MarkHookRecorder extends CardModifierStamp:
	var covers : int = 0
	var hits : int = 0
	var cover_level : int = -1
	var hit_level : int = -1
	func get_str() -> String: return "MarkHookRecorder"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_mark_covered(_card: CardData, _coord: BoardCoord, level: int) -> void:
		covers += 1
		cover_level = level
	func on_mark_hit(_card: CardData, _coord: BoardCoord, _matched: int, level: int) -> void:
		hits += 1
		hit_level = level


#The two mark hooks on the SKILL slot, which `run_mark_mods` carries in although a mark is never
#spotlit. A stamp double cannot fail when that carry-in is wrong, so the skill shape needs its own.
class MarkHookSkill extends CardModifierSkill:
	var covers : int = 0
	var hits : int = 0
	func get_str() -> String: return "MarkHookSkill"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_mark_covered(_card: CardData, _coord: BoardCoord, _level: int) -> void:
		covers += 1
	func on_mark_hit(_card: CardData, _coord: BoardCoord, _matched: int, _level: int) -> void:
		hits += 1


#Counts a BOARD-WIDE broadcast, on the slot that has no spotlight gate anywhere: a stamp is asked
#whatever covers its card, which is why the mark exclusion cannot live on the spotlight flag alone.
#`on_after_score` is the hook the shipped Double Trigger stamp implements on five deck rows.
class AfterScoreRecorder extends CardModifierStamp:
	var after_scores : int = 0
	func get_str() -> String: return "AfterScoreRecorder"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_after_score() -> void:
		after_scores += 1


#A mark worth twice the line it sits in, on a STAMP because that is the slot the shipped effects
#use. The share reaches the line through the api's own seam, which is the only way a mark effect
#has of multiplying one.
class LineMultStamp extends CardModifierStamp:
	func get_str() -> String: return "LineMultStamp"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_mark_covered(_card: CardData, _coord: BoardCoord, _level: int) -> void:
		api.add_line_mult(2.0)


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
# TP-30, TP-31, TP-32 -- (hand + flats) x the summed mults
# ==============================================================================

#TP-30: the rank bonus is ADDED to the hand the line scored, and the hand it is added to is measured
#from the same row with nothing marked -- the number the model produces is never written down here.
func test_a_rank_match_is_added_to_the_line() -> void:
	var snapshot := snapshot_settings("plan_")
	SettingsManager.settings.plan_rank_match_step = 1.0
	var bare := await scored_row(pair_row(), {} as Dictionary[int, CardData])
	var marked := await scored_row(pair_row(), {0: row_card(7)} as Dictionary[int, CardData])
	check(row_banked(bare) > 0.0,
			"TP-30 precondition: the unmarked row banked its hand at all",
			"banked %f" % row_banked(bare))
	check(row_banked(marked) == row_banked(bare) + 7.0,
			"TP-30: a 7 of the meld on a mark printing 7 banks the hand plus 7",
			"%f against %f" % [row_banked(marked), row_banked(bare)])
	free_game(bare)
	free_game(marked)
	restore_settings_snapshot(snapshot)

#TP-31: nothing in this row contributes a mult, so the summed mult is 0 -- and a 0 is SKIPPED rather
#than multiplied by, exactly as a bucket worth 0 is left out of the grid product.
func test_a_line_with_no_mult_is_never_multiplied_to_nothing() -> void:
	var snapshot := snapshot_settings("plan_")
	SettingsManager.settings.plan_rank_match_step = 1.0
	var bare := await scored_row(pair_row(), {} as Dictionary[int, CardData])
	var marked := await scored_row(pair_row(),
			{0: row_card(7), 1: row_card(7)} as Dictionary[int, CardData])
	check(row_banked(bare) > 0.0,
			"TP-31 precondition: the unmarked row banked its hand at all",
			"banked %f" % row_banked(bare))
	check(row_banked(marked) == row_banked(bare) + 14.0,
			"TP-31: both flat bonuses are banked and the zero mult multiplies nothing",
			"%f against %f" % [row_banked(marked), row_banked(bare)])
	check(row_banked(marked) > 0.0,
			"TP-31: a line with no mult bonus does not bank nothing",
			"banked %f" % row_banked(marked))
	free_game(bare)
	free_game(marked)
	restore_settings_snapshot(snapshot)

#TP-32: the shares SUM and the sum IS the multiplier, so one mark worth twice gives x2 and two give
#x4. Three of them separate the sum from `1 + the sum` (which would give x7) and from a product of
#the shares (x8).
func test_mark_effects_sum_into_one_multiplier() -> void:
	var bare := await scored_row(triple_row(), {} as Dictionary[int, CardData])
	var one := await scored_row(triple_row(), {0: mult_mark()} as Dictionary[int, CardData])
	var two := await scored_row(triple_row(),
			{0: mult_mark(), 1: mult_mark()} as Dictionary[int, CardData])
	var three := await scored_row(triple_row(),
			{0: mult_mark(), 1: mult_mark(), 2: mult_mark()} as Dictionary[int, CardData])
	var hand := row_banked(bare)
	check(hand > 0.0, "TP-32 precondition: the unmarked row banked its hand at all",
			"banked %f" % hand)
	check(row_banked(one) == hand * 2.0,
			"TP-32: one mark worth twice multiplies the whole line by 2",
			"%f against a hand of %f" % [row_banked(one), hand])
	check(row_banked(two) == hand * 4.0,
			"TP-32: two of them make x4 -- the shares are summed, not added to a 1",
			"%f against a hand of %f" % [row_banked(two), hand])
	check(row_banked(three) == hand * 6.0,
			"TP-32: and three make x6, where a product of the shares would make x8",
			"%f against a hand of %f" % [row_banked(three), hand])
	for g : Game in [bare, one, two, three] as Array[Game]:
		free_game(g)

#Every landing on a marked cell is a COVER, matching or not, so a x2 mark multiplies whatever is put
#on it; a match adds `on_mark_hit` on top rather than replacing the cover. The levels say which is
#which: the cover is the normal form, the match the realized one.
func test_a_cover_is_announced_and_a_match_adds_its_own_hook() -> void:
	var marks : Dictionary[int, CardData] = {0: row_card(7).with_stamp(MarkHookRecorder.new()),
			1: row_card(2).with_stamp(MarkHookRecorder.new())}
	var g := await scored_row(triple_row(), marks)
	var matching := g.state.cell_type_at(cell(0, 0)).stamp as MarkHookRecorder
	var plain := g.state.cell_type_at(cell(1, 0)).stamp as MarkHookRecorder
	check(matching.covers == 1 and matching.hits == 1,
			"TP-32: a card that MATCHED its mark fires both hooks, the cover as well as the hit",
			"%d covers, %d hits" % [matching.covers, matching.hits])
	check(plain.covers == 1 and plain.hits == 0,
			"TP-32: a card that matched nothing fires the cover hook alone",
			"%d covers, %d hits" % [plain.covers, plain.hits])
	check(matching.cover_level == 0 and matching.hit_level == 1,
			"TP-32: the cover arrives at level 0 and the match at level 1, the realized form",
			"cover %d, hit %d" % [matching.cover_level, matching.hit_level])
	free_game(g)

#A mark's copied SKILL is dispatched the mark hooks although the spotlight rule keeps it dark --
#the one slot whose dispatch depends on a flag, so the darkness is asserted next to the hooks that
#arrived anyway.
func test_a_marks_copied_skill_is_dispatched_the_mark_hooks() -> void:
	var marks : Dictionary[int, CardData] = {0: row_card(7).with_skill(MarkHookSkill.new())}
	var g := await scored_row(triple_row(), marks)
	var spy := g.state.cell_type_at(cell(0, 0)).skill as MarkHookSkill
	check(not spy.spotlit and not spy.is_spotlit(),
			"precondition: the mark's copied skill is dark, flag and rule alike")
	check(spy.covers == 1 and spy.hits == 1,
			"TP-44b: the mark hooks reach a mark's copied skill at score time regardless",
			"%d covers, %d hits" % [spy.covers, spy.hits])
	free_game(g)


# ==============================================================================
# TP-34, TP-36, TP-37 -- which cards pay, and into what
# ==============================================================================

#TP-34: the flush's double happens inside the hand's own number and knows nothing about a bonus, so
#a rank match is simply added to it. The control row proves the five cards really did flush.
func test_a_flush_keeps_its_own_score() -> void:
	var snapshot := snapshot_settings("plan_")
	SettingsManager.settings.plan_rank_match_step = 1.0
	var suited := await scored_row(flush_row(), {} as Dictionary[int, CardData])
	var unsuited := await scored_row(unsuited_row(), {} as Dictionary[int, CardData])
	var marked := await scored_row(flush_row(), {0: row_card(9)} as Dictionary[int, CardData])
	check(row_banked(suited) > row_banked(unsuited),
			"TP-34 precondition: the five suited cards score as a flush and the same ranks unsuited do not",
			"%f against %f" % [row_banked(suited), row_banked(unsuited)])
	check(row_banked(marked) == row_banked(suited) + 9.0,
			"TP-34: the rank bonus is added to the flush's own score, never multiplied by its double",
			"%f against %f" % [row_banked(marked), row_banked(suited)])
	free_game(suited)
	free_game(unsuited)
	free_game(marked)
	restore_settings_snapshot(snapshot)

#TP-36: only a card the hand actually used pays. The marked card here matches its mark on rank and
#sits in the line, but the best meld is the three 7s, so the line banks exactly what it banked bare.
func test_a_match_outside_the_meld_pays_nothing() -> void:
	var bare := await scored_row(triple_row(), {} as Dictionary[int, CardData])
	var marked := await scored_row(triple_row(), {3: row_card(11)} as Dictionary[int, CardData])
	var outsider := marked.state.card_at(cell(3, 0))
	var outsider_match : int = await MarkMatch.matches_at(marked.state, outsider, cell(3, 0))
	check(outsider_match != 0,
			"TP-36 precondition: the card outside the meld DOES match the mark under it",
			"got %d" % outsider_match)
	check(row_banked(bare) > 0.0, "TP-36 precondition: the unmarked row banked its hand at all",
			"banked %f" % row_banked(bare))
	check(row_banked(marked) == row_banked(bare),
			"TP-36: a matching card the meld left out pays nothing at all",
			"%f against %f" % [row_banked(marked), row_banked(bare)])
	free_game(bare)
	free_game(marked)

#TP-37: the bonus is computed inside each line's own number, so a card completing three lines at once
#pays into all three -- the same way its suit effect fires once per meld it belongs to.
func test_a_card_pays_into_every_line_it_completes() -> void:
	var snapshot := snapshot_settings("plan_")
	SettingsManager.settings.plan_rank_match_step = 1.0
	var bare := await banked_corner_lines({} as Dictionary[int, CardData])
	var marked := await banked_corner_lines({0: row_card(7)} as Dictionary[int, CardData])
	for i : int in 3:
		check(bare[i] > 0.0, "TP-37 precondition: line %d banked its hand at all" % i,
				"banked %f" % bare[i])
		check(marked[i] == bare[i] + 7.0,
				"TP-37: the corner's rank bonus is banked into line %d as well" % i,
				"%f against %f" % [marked[i], bare[i]])
	restore_settings_snapshot(snapshot)


# ==============================================================================
# TP-38 -- a match is not a combo class
# ==============================================================================

#TP-38: matching pays points and touches the combo not at all, so the classes the act has seen are
#the same set with the mark there and gone -- the hand's own class and nothing else.
func test_a_match_registers_no_combo_class() -> void:
	var bare := await scored_row(pair_row(), {} as Dictionary[int, CardData])
	var marked := await scored_row(pair_row(), {0: row_card(7)} as Dictionary[int, CardData])
	check(not bare.state.combo_classes.is_empty(),
			"TP-38 precondition: scoring the row registered the hand's own combo class",
			"got %s" % str(bare.state.combo_classes))
	check(marked.state.combo_classes == bare.state.combo_classes,
			"TP-38: a match registers no class of its own",
			"%s against %s" % [str(marked.state.combo_classes), str(bare.state.combo_classes)])
	check(row_banked(marked) > row_banked(bare),
			"TP-38 precondition: the match did pay, so the comparison is about a line that matched",
			"%f against %f" % [row_banked(marked), row_banked(bare)])
	free_game(bare)
	free_game(marked)


# ==============================================================================
# TP-43 -- a matched suit fires where suit effects fire, once per meld membership
# ==============================================================================

#TP-43: the mark decides WHETHER a suit fires, never how often. A knife in a row and a column banks
#its props twice, once per meld it belongs to, which is exactly the unconditional firing this rule
#replaced; with the mark gone neither firing happens and the row keeps only its hand.
func test_a_matched_suit_fires_once_per_meld_membership() -> void:
	var two_melds := await banked_knife_cross(true, true)
	var one_meld := await banked_knife_cross(true, false)
	var bare_two := await banked_knife_cross(false, true)
	var bare_one := await banked_knife_cross(false, false)
	var fired_twice := two_melds - bare_two
	var fired_once := one_meld - bare_one
	check(fired_once > 0.0,
			"TP-43 precondition: a matched knife in one meld banks its props into its row",
			"%f against the unmarked %f" % [one_meld, bare_one])
	check(is_equal_approx(bare_two, bare_one),
			"TP-43 precondition: without a match the second meld adds nothing to the row",
			"%f against %f" % [bare_two, bare_one])
	check(is_equal_approx(fired_twice, fired_once * 2.0),
			"TP-43: the same knife in a row AND a column fires once per meld membership",
			"%f against twice %f" % [fired_twice, fired_once])


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

#⚠ THE SKILL SLOT IS NOT THE WHOLE OF IT, BECAUSE MEASURED: a stamp answers a broadcast with no
#spotlight gate at all, so a mark that copied one answers the board's hooks once per marked cell
#however dark it is. The control is the same stamp on a real card, in a cell carrying no mark.
func test_a_marks_copied_stamp_answers_no_broadcast() -> void:
	var g := make_game()
	var mark := mark_cell(g.state, 3, 0, play_card(3, null).with_stamp(AfterScoreRecorder.new()))
	var control := play_card(4, null).with_stamp(AfterScoreRecorder.new())
	place_in_cell(g.state, 4, 0, control)
	var mark_spy := mark.stamp as AfterScoreRecorder
	var control_spy := control.stamp as AfterScoreRecorder
	await g.run_all_mods(&"on_after_score")
	check(control_spy.after_scores == 1,
			"precondition: the same stamp on a played card answers the board-wide broadcast",
			"got %d" % control_spy.after_scores)
	check(mark_spy.after_scores == 0,
			"TP-44: a mark's copied stamp answers no board-wide broadcast",
			"got %d" % mark_spy.after_scores)
	check(mark.statuses.is_empty(),
			"TP-44: and the mark carries no status for the same broadcast to reach",
			"got %d" % mark.statuses.size())
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
