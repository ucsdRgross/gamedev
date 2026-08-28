extends TestSuite
# res://Tests/Engine/test_game_headless.gd
# ==============================================================================
# Game LOGIC with view == null (Plan 2 §6.2): proves the data layer runs a full
# show headless — commands, scoring, undo, and the processing guard — with NO UI
# and NO crash despite every `if view:` branch being skipped.
#
# Like test_board.gd, the Game is a bare Game.new() never added to the tree (its
# board logic is tree-safe); CardEnvironment.CURRENT is set by hand so rules-card
# skills resolve `game`. The view field is left null throughout.
# ==============================================================================

# CATEGORY MAP: all BEHAVIOR — these drive the player-facing commands (grab, place,
# undo, end) through the real Game API and assert the outcomes a player sees.
# The single representation-level check (gutter BigNumber accumulation) is check_impl.

func suite_name() -> String:
	return "GAME HEADLESS"

func _ready() -> void:
	TestLog.line("============ GAME HEADLESS TEST PASS ============")
	behavior_section("PLAYER COMMANDS, HEADLESS")
	await test_command_guard_blocks_input()
	await test_try_grab_returns_stack()
	await test_try_place_moves_and_commits()
	await test_noop_place_commits_nothing()
	await test_undo_reverts_state_and_history()
	test_debug_history_is_uncapped_and_redoable()
	await test_undo_rewinds_per_show_state()
	await test_undo_at_game_over_rewinds_the_end()
	test_add_deck_relinks_suit_backrefs()
	await test_score_line_headless_mutates_data()
	await test_end_show_is_the_only_resolver()
	behavior_section("COMPARATOR RULES CARDS, THROUGH A REAL GAME")
	await test_comparator_rules_change_a_real_act()
	await test_authored_card_doubles()
	implementation_section("THE RETIRED ACT")
	test_retired_act_has_no_readers()
	test_zone_only_tests_do_not_multiply()
	test_nowhere_is_never_compared_by_identity()
	finish()

func rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.spotlit = true
	return c

# A minimal but real show fixture: rules cards carry the classic grabber/placer/scorer skills
# (always spotlit because they live in rules_deck), and both zones have two paired 2-card
# columns whose ranks ascend by 1 with distinct suits (so grab/place runs are legal and poker
# high-card scoring pays > 0). view is deliberately left null.
func make_game() -> Game:
	var g := Game.new()
	var s := GameData.new()
	s.rules_deck = [
		rules_card(SkillGrabberOgLower.new()),
		rules_card(SkillPlacerOgLower.new()),
		rules_card(SkillScorerCascadeLower.new()),
		rules_card(SkillEvalPokerBest.new()),
	] as Array[CardData]
	for zone_x in 2:
		var types: Array[CardData] = []
		var cols: Array[ArrayCardData] = []
		for c in 2:
			var h := TestFactories.m_card(1, TestFactories.uc()); h.stage = CardData.Stage.ZONE
			types.append(h)
			var card_lo := TestFactories.m_card(3, TestFactories.uc())
			var card_hi := TestFactories.m_card(4, TestFactories.uc())
			card_lo.stage = CardData.Stage.PLAY
			card_hi.stage = CardData.Stage.PLAY
			cols.append(TestFactories.col([card_lo, card_hi] as Array[CardData]))
		if zone_x == 0:
			s.upper_zone_type = types
			s.upper_zone = cols
		else:
			s.lower_zone_type = types
			s.lower_zone = cols
	g.state = s
	CardEnvironment.CURRENT = g
	return g

func free_game(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

func lower(g: Game, col: int) -> Array[CardData]:
	return g.state.lower_zone[col].datas

func test_command_guard_blocks_input() -> void:
	var g := make_game()
	g.processing = true
	var grabbed := await g.try_grab(lower(g, 0)[0])
	check(grabbed.is_empty(), "try_grab is a no-op while processing (returns [])")
	var placed := await g.try_place([lower(g, 0)[0]] as Array[CardData], lower(g, 1)[0])
	check(not placed, "try_place is a no-op while processing (returns false)")
	CardEnvironment.CURRENT = null
	free_game(g)

func test_try_grab_returns_stack() -> void:
	var g := make_game()
	# lower col 0 is [rank3, rank4] with distinct suits, ascending -> a legal grab run
	var bottom := lower(g, 0)[0]
	var grabbed := await g.try_grab(bottom)
	check(grabbed.size() == 2 and grabbed[0] == bottom,
			"try_grab returns the full ascending run", str(grabbed.size()))
	# an upper-zone card can't be grabbed by the lower-zone grabber
	var upper_card := g.state.upper_zone[0].datas[0]
	check((await g.try_grab(upper_card)).is_empty(),
			"try_grab rejects an upper-zone card (grabber is lower-only)")
	CardEnvironment.CURRENT = null
	free_game(g)

func test_try_place_moves_and_commits() -> void:
	var g := make_game()
	# move the top of col0 (rank4) onto... needs a topmost target one rank apart, distinct suit.
	# col1 top is rank4 too (suit differs) -> not a legal run (rank diff 0). Instead grab the
	# single top card of col0 and drop onto col1's bottom is illegal (covered). So test the
	# legal case: place col0's top (rank4) onto a fresh rank3 target we append is overkill;
	# assert the REJECTION path commits nothing, and a legal single-card place commits once.
	var history_before := g.save_history.size()
	var top0 := lower(g, 0)[1]  # rank 4
	var top1 := lower(g, 1)[1]  # rank 4 -> same rank, placement illegal
	var placed := await g.try_place([top0] as Array[CardData], top1)
	check(not placed and g.save_history.size() == history_before,
			"illegal place (equal ranks) rejected, nothing committed")
	# make a legal target: a rank-5 card distinct suit on top of col1
	var target := TestFactories.m_card(5, TestFactories.uc())
	target.stage = CardData.Stage.PLAY
	g.state.lower_zone[1].datas.append(target)
	g.state.revision += 1
	placed = await g.try_place([top0] as Array[CardData], target)  # rank4 onto rank5, diff 1
	check(placed, "legal place accepted")
	check(g.find_data_vec3(top0).x == 1 and g.find_data_vec3(top0).y == 1,
			"placed card now lives in lower col 1", str(g.find_data_vec3(top0)))
	check(g.save_history.size() == history_before + 1, "legal place commits exactly one save")
	check(g.state.validate().is_empty(), "board still validates after the move")
	CardEnvironment.CURRENT = null
	free_game(g)

## A placer that also accepts the card DIRECTLY BENEATH the moving card as a target — the
## legality query says yes, but Board resolves the move to OK_NOOP (nothing moves). The shipped
## placer can't produce this (it demands a topmost target), so the case is staged here.
class PlacerAcceptsOwnSpot extends CardModifierSkill:
	func get_str() -> String: return "NoopPlacer"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func combo_key(_hook: StringName = &"") -> String: return ""
	func on_can_place_stack(stack: Array[CardData], target: CardData) -> Array[CardData]:
		if not (stack and target): return []
		var g := CardEnvironment.get_current_game()
		if not g: return []
		var src := g.find_data_vec3(stack[0])
		var dst := g.find_data_vec3(target)
		# only the "dropped back onto its own position" case
		if src == Vector3i.MIN or dst != src - Vector3i(0, 0, 1): return []
		return stack

## Task 1: a legal placement that moves nothing (Board.OK_NOOP — a stack dropped
## back onto its own spot) must NOT push an undo entry, or Undo appears to do nothing. The
## action count entity_side_for_row hashes must not advance either: it never was an action.
func test_noop_place_commits_nothing() -> void:
	var g := make_game()
	g.state.rules_deck.append(rules_card(PlacerAcceptsOwnSpot.new()))
	g.state.revision += 1
	g.save_state()   # the committed baseline the no-op would duplicate
	var history_before := g.save_history.size()
	var actions_before := g.history_trimmed + g.save_history.size()
	var top0 := lower(g, 0)[1]
	var under0 := lower(g, 0)[0]
	var placed := await g.try_place([top0] as Array[CardData], under0)
	check(placed, "precondition: the no-op placement is reported legal")
	check(g.save_history.size() == history_before,
			"a no-op placement pushes NO undo entry", str(g.save_history.size()))
	check(g.history_trimmed + g.save_history.size() == actions_before,
			"the committed-action count does not advance on a no-op")
	# a REAL move right after still commits, and undo lands on the pre-move board
	var target := TestFactories.m_card(5, TestFactories.uc())
	target.stage = CardData.Stage.PLAY
	g.state.lower_zone[1].datas.append(target)
	g.state.revision += 1
	check(await g.try_place([top0] as Array[CardData], target), "the real move is accepted")
	check(g.save_history.size() == history_before + 1, "a real move commits exactly one snapshot")
	g.undo()
	check(g.state.lower_zone[0].datas.size() == 2,
			"undo restored the pre-move column", str(g.state.lower_zone[0].datas.size()))
	CardEnvironment.CURRENT = null
	free_game(g)

## ⚠ **THE DEBUG HISTORY OUTLIVES THE PRODUCTION CAP, WHICH IS THE ONLY REASON IT EXISTS.**
## `save_history` is capped (`undo_cap`, `Game.save_state`), so a player's undo eventually stops
## reaching backwards; the owner's playtest loop is *"undo, press record, repeat the action"*, which
## needs to reach the setup BEFORE a bug however many actions ago that was.
##
## This drives more commits than the cap allows and asserts the two histories diverge in exactly the
## intended way: the production one stops growing, the debug one does not. **A test that committed
## fewer actions than the cap would pass identically with the feature deleted.**
func test_debug_history_is_uncapped_and_redoable() -> void:
	if not OS.is_debug_build():
		check_impl(true, "debug history is debug-build only — SKIPPED in a release build")
		return
	var g := make_game()
	g.undo_cap = 3   # a small cap so "more commits than the cap" stays a fast test
	g.save_state()
	var commits := 8
	for i : int in commits:
		var extra := TestFactories.m_card(float(9 + i), TestFactories.uc())
		extra.stage = CardData.Stage.PLAY
		g.state.lower_zone[0].datas.append(extra)
		g.state.revision += 1
		g.save_state()
	check(g.save_history.size() <= 3,
			"the PLAYER's history is capped and stops growing", str(g.save_history.size()))
	check(g._debug_history.size() == commits + 1,
			"the DEBUG history kept every commit", str(g._debug_history.size()))
	var deep := g.state.lower_zone[0].datas.size()
	# Rewind further back than the production cap could ever reach.
	var steps := 0
	while g.debug_undo(): steps += 1
	check(steps > 3, "debug undo rewound PAST the production cap", "%d steps" % steps)
	check(g.state.lower_zone[0].datas.size() < deep,
			"...and the board really moved back",
			"%d vs %d" % [g.state.lower_zone[0].datas.size(), deep])
	# Redo walks forward again — the "repeat the action after undoing" half.
	var forward := 0
	while g.debug_redo(): forward += 1
	check(forward == steps, "debug redo replays exactly as far as undo rewound",
			"%d vs %d" % [forward, steps])
	check(g.state.lower_zone[0].datas.size() == deep,
			"...arriving back at the state it started from",
			"%d vs %d" % [g.state.lower_zone[0].datas.size(), deep])
	# ⚠ A fresh commit INVALIDATES the redo future — replaying it would restore a board that never
	# followed from this one.
	g.debug_undo()
	g.state.revision += 1
	g.save_state()
	check(not g.debug_redo(), "a new action clears the redo future (it no longer follows)")
	CardEnvironment.CURRENT = null
	free_game(g)

func test_undo_reverts_state_and_history() -> void:
	var g := make_game()
	g.save_state()  # seed one baseline snapshot
	var baseline_cols := g.state.lower_zone[0].datas.size()
	# commit a mutation: append a card and save
	var extra := TestFactories.m_card(9, TestFactories.uc())
	extra.stage = CardData.Stage.PLAY
	g.state.lower_zone[0].datas.append(extra)
	g.state.revision += 1
	g.save_state()
	var history_after_change := g.save_history.size()
	g.undo()
	check(g.save_history.size() == history_after_change - 1, "undo shrinks history by one")
	check(g.state.lower_zone[0].datas.size() == baseline_cols,
			"undo reverts the board to the previous snapshot",
			"%d vs %d" % [g.state.lower_zone[0].datas.size(), baseline_cols])
	# Checklist 0.4: the undo path (duplicate_state + restore_runtime) must relink the suit
	# self-cycle — a stale backref silently breaks suit spawns (suit.game / find_data_vec3).
	var undone := g.state.lower_zone[0].datas[0]
	check_impl(undone.suit != null and undone.suit.data == undone,
			"undo relinks the suit back-reference (suit.data == its card)")
	CardEnvironment.CURRENT = null
	free_game(g)

## Per-show state lives on GameData so history snapshots carry it: undoing must rewind it
## together with the board (owner bug report — the old Game-level act counter survived undo,
## permanently eating acts). The act count is retired; show_resolved is the per-show flag that
## now has to hold this property, since a resumed show reads it to decide what to show.
func test_undo_rewinds_per_show_state() -> void:
	var g := make_game()
	g.save_state()   # baseline snapshot so undo has somewhere to go
	g.end_show()
	check(g.state.show_ended, "precondition: ending the show marks the state resolved")
	g.undo()
	check(not g.state.show_ended, "undo rewinds the resolved flag with the board")
	check(not g.save_history[-1].show_ended,
			"the restored snapshot itself carries the rewound flag")
	CardEnvironment.CURRENT = null
	free_game(g)

## Undo at the win/lose screen dismisses the outcome (show_unresolved) and rewinds the
## End: the show comes back live, input unlocks, and nothing was banked (fame only
## moves on Continue — exit_show — which never ran).
func test_undo_at_game_over_rewinds_the_end() -> void:
	var g := make_game()
	g.save_state()
	var resolved : Array = []
	g.show_resolved.connect(func(won: bool, _s: int, _g: int) -> void: resolved.append(won))
	var unresolved : Array = []
	g.show_unresolved.connect(func() -> void: unresolved.append(true))
	check(resolved.is_empty(), "the show has not resolved before end_show is called")
	g.end_show()
	check(resolved.size() == 1, "ending the show resolves it", str(resolved))
	check(g.processing, "the resolved show locks input")
	var history_at_over := g.save_history.size()
	g.undo()
	check(unresolved.size() == 1, "undo at the outcome screen emits show_unresolved")
	check(g.save_history.size() == history_at_over - 1,
			"the End's snapshot is popped")
	check(not g.processing, "input unlocks — the show is live again")
	# the show can re-resolve after the rewind (undo -> End again)
	g.end_show()
	check(resolved.size() == 2, "ending it again after the rewind resolves it again")
	CardEnvironment.CURRENT = null
	free_game(g)

## Checklist 0.4's other half: add_deck deep-duplicates the saved deck into the show; the
## duplicate must remap (not share or drop) every suit's back-reference.
func test_add_deck_relinks_suit_backrefs() -> void:
	var g := make_game()
	var prev_save_info : RunState = Main.save_info
	Main.save_info = RunState.new()   # blank save -> add_deck falls back to the full starter Deck
	g.add_deck()
	var all_linked := not g.state.draw_deck.is_empty()
	for card : CardData in g.state.draw_deck:
		if card.suit and card.suit.data != card:
			all_linked = false
	check_impl(all_linked, "add_deck's deep-duplicated deck keeps suit.data == its card",
			"deck size %d" % g.state.draw_deck.size())
	Main.save_info = prev_save_info
	CardEnvironment.CURRENT = null
	free_game(g)

func test_score_line_headless_mutates_data() -> void:
	var g := make_game()
	var r := Scoring.Result.new()
	r.name = "Test"
	r.score = 7
	r.meld = [] as Array[CardData]
	check(g.state.row_total == 0, "precondition: row_total starts at 0")
	# ⚠ score_line RE-EVALUATES a real board line over its own section before banking
	# (spotlight S8, Q22=b/Q23=a), so a synthetic Result handed in for a populated zone is
	# discarded — the expected number comes from the board, not from `r`.
	var row_cards := ScoringSection.collect(g.state.lower_zone, true, 0)
	var expected : int = (await Scoring.PokerHands.score(row_cards))[0].score
	await g.score_line(r, ScoringSection.of_line(g.state.lower_zone, true, 0))  # row, lower gutter, index 0
	check(g.state.row_total == expected,
			"score_line banks the re-evaluated row hand headless", str(g.state.row_total))
	check_impl(g.state.scores_row_lower.size() >= 1 and g.state.scores_row_lower[0] != null,
			"score_line accumulates a gutter BigNumber headless (view skipped, no crash)")
	# An EMPTY zone builds an empty section: there is nothing to light and nothing to
	# re-evaluate, so the Result handed in is banked unchanged.
	await g.score_line(r, ScoringSection.of_line([] as Array, false, 0))  # col path
	check(g.state.col_total == 7, "score_line adds to col_total headless (no section)")
	CardEnvironment.CURRENT = null
	free_game(g)

# ==============================================================================
# COMPARATOR RULES CARDS, THROUGH A REAL GAME
#
# ⚠ **THIS IS `design/comparator_buckets/PLAN.md` §6, RUN.** Every other comparator test drives
# `Scoring` under a `FakeEnvironment`. That leaves the whole feature asserted only against a
# stand-in: `Game` is the environment with a REAL `_revision_key()`, a real `CardDataIterator`
# over draw deck / zones / rules deck, real `spotlit` resolution, and a real `score_line` that
# banks into the gutters. A rules card that works in the fake and not in the game would pass
# every other suite in this repo.
#
# The rules cards below are SKILLS in `rules_deck`, which is how the shipped engine rules cards
# are carried and which makes them always spotlit — so this also exercises the carrier and the
# spotlight path the fake never touches.
#
# §6's six checks, mechanically: 1 and 2 are `merge_makes_a_set` + `removing_it_restores`,
# 3 is `suit_merge_makes_a_flush`, 4 is `deny_splits_a_pair`, 5 is `merge_kills_the_straight`,
# 6 is the unmodded baseline every one of them is paired against. What CANNOT be automated —
# whether it FEELS right — is still the owner's, and stays in todo.md.
# ==============================================================================

class RulesAllRanksSame extends CardModifierSkill:
	func get_str() -> String: return "All Ranks Same"
	func get_description() -> String: return "Every rank counts as every other"
	func get_frame() -> int: return 0
	func combo_key(_hook: StringName = &"") -> String: return ""
	func on_meld_ranks_allow(_r1: PipRank, _r2: PipRank) -> bool: return true

class RulesAllSuitsSame extends CardModifierSkill:
	func get_str() -> String: return "All Suits Same"
	func get_description() -> String: return "Every suit counts as every other"
	func get_frame() -> int: return 0
	func combo_key(_hook: StringName = &"") -> String: return ""
	func on_meld_suits_allow(_s1: PipSuit, _s2: PipSuit) -> bool: return true

class RulesDenySevens extends CardModifierSkill:
	func get_str() -> String: return "No Two Sevens"
	func get_description() -> String: return "Two 7s never count as the same"
	func get_frame() -> int: return 0
	func combo_key(_hook: StringName = &"") -> String: return ""
	func on_meld_ranks_deny(r1: PipRank, r2: PipRank) -> bool:
		return float(r1.value) == 7.0 and float(r2.value) == 7.0

## A real Game whose LOWER zone is one row of `ranks`/`suits`, plus any extra rules cards.
## One row of five columns, so the cascade scorer scores a five-card row through score_line.
func comparator_game(ranks: Array[int], suits: Array[int], extra: Array[CardData]) -> Game:
	var g := Game.new()
	var s := GameData.new()
	s.rules_deck = [
		rules_card(SkillScorerCascadeLower.new()),
		rules_card(SkillEvalPokerBest.new()),
	] as Array[CardData]
	for c : CardData in extra: s.rules_deck.append(c)
	for zone_x in 2:
		var types: Array[CardData] = []
		var cols: Array[ArrayCardData] = []
		for i in range(ranks.size()):
			var h := TestFactories.m_card(1, TestFactories.uc())
			h.stage = CardData.Stage.ZONE
			types.append(h)
			if zone_x == 0:
				cols.append(TestFactories.col([] as Array[CardData]))
				continue
			var card := TestFactories.m_card(float(ranks[i]), suits[i])
			card.stage = CardData.Stage.PLAY
			cols.append(TestFactories.col([card] as Array[CardData]))
		if zone_x == 0:
			s.upper_zone_type = types
			s.upper_zone = cols
		else:
			s.lower_zone_type = types
			s.lower_zone = cols
	g.state = s
	CardEnvironment.CURRENT = g
	return g

## Score one act and report what the lower row banked. The REAL path: on_run_scorer -> cascade
## scorer -> SkillEvalPokerBest -> Scoring.PokerHands.score -> Game.score_line -> gutters ->
## GameData.apply_act_score (fires the mod pass and banks it directly; there is no button that
## does this any more, but the mod event and the bank step are both still real architecture).
func act_score(g: Game) -> int:
	await g.run_all_mods(&"on_run_scorer")
	g.state.apply_act_score()
	return g.state.total_score

func test_comparator_rules_change_a_real_act() -> void:
	# 2,4,6,8,10 in five DIFFERENT suits: no pair, no flush, no straight. High Card.
	var ranks : Array[int] = [2, 4, 6, 8, 10]
	var suits : Array[int] = [901, 902, 903, 904, 905]

	# --- §6.6 the baseline: a normal board with no comparator rules card at all --------------
	var plain := comparator_game(ranks, suits, [] as Array[CardData])
	var plain_score := await act_score(plain)
	check(plain_score > 0, "§6.6 REAL GAME: an unmodded board scores through the whole act",
			str(plain_score))
	check(plain.state.validate().is_empty(), "§6.6 REAL GAME: and the board still validates")
	free_game(plain)

	# --- §6.1 a rank-merging rules card makes those five distinct ranks a SET ----------------
	var merged := comparator_game(ranks, suits, [rules_card(RulesAllRanksSame.new())] as Array[CardData])
	var merged_score := await act_score(merged)
	check(merged_score > plain_score,
			"§6.1 REAL GAME: a rank-merging RULES CARD turns five distinct ranks into a set, "
			+ "and the act pays more than the same board unmodded",
			"modded %d vs plain %d" % [merged_score, plain_score])
	free_game(merged)

	# --- §6.2 remove it and the same board scores exactly as it did before -------------------
	# ⚠ Built from the same fixture, not the same instance: this is what proves no partition or
	# verdict outlived the card that caused it, through a REAL board revision.
	var restored := comparator_game(ranks, suits, [] as Array[CardData])
	var restored_score := await act_score(restored)
	check(restored_score == plain_score,
			"§6.2 REAL GAME: removing the rules card restores the unmodded payout exactly",
			"%d vs %d" % [restored_score, plain_score])
	free_game(restored)

	# --- §6.3 a suit-merging rules card makes five distinct suits a FLUSH --------------------
	var flushed := comparator_game(ranks, suits, [rules_card(RulesAllSuitsSame.new())] as Array[CardData])
	var flushed_score := await act_score(flushed)
	check(flushed_score > plain_score,
			"§6.3 REAL GAME: a suit-merging RULES CARD forms a flush from five distinct suits "
			+ "and takes the Full Flush multiplier",
			"modded %d vs plain %d" % [flushed_score, plain_score])
	free_game(flushed)

	# --- §6.5 a merging card kills a straight -----------------------------------------------
	# 3,4,5,6,7 one suit apiece IS a straight; merged into one rank class it cannot be.
	var run_ranks : Array[int] = [3, 4, 5, 6, 7]
	var straight := comparator_game(run_ranks, suits, [] as Array[CardData])
	var straight_score := await act_score(straight)
	free_game(straight)
	var killed := comparator_game(run_ranks, suits, [rules_card(RulesAllRanksSame.new())] as Array[CardData])
	var killed_score := await act_score(killed)
	check(straight_score != killed_score,
			"§6.5 REAL GAME: a rank-merging card changes what a five-card RUN scores as — one "
			+ "rank class left, so the straight is gone (Q3=a, Q93=d)",
			"straight %d vs merged %d" % [straight_score, killed_score])
	free_game(killed)

	# --- §6.4 a deny rule stops two printed 7s counting as a pair ----------------------------
	var pair_ranks : Array[int] = [7, 7, 2, 4, 9]
	var paired := comparator_game(pair_ranks, suits, [] as Array[CardData])
	var paired_score := await act_score(paired)
	free_game(paired)
	var split := comparator_game(pair_ranks, suits, [rules_card(RulesDenySevens.new())] as Array[CardData])
	var split_score := await act_score(split)
	check(split_score < paired_score,
			"§6.4 REAL GAME: a deny rules card stops two printed 7s counting as a pair, so the "
			+ "act pays LESS than the same board without it (Q82=a)",
			"denied %d vs paired %d" % [split_score, paired_score])
	check(split.state.validate().is_empty(),
			"§6.4 REAL GAME: and the board validates after an act scored under a deny rule")
	free_game(split)


# ==============================================================================
# THE AUTHORED-CARD DOUBLES (PLAN §3 stage 1) — CAN THE ENGINE EXPRESS THEM?
#
# ⚠ **THAT QUESTION IS THE POINT OF THIS ROSTER, AND IT IS WORTH ANSWERING BEFORE THE CARDS ARE
# AUTHORED, NOT AFTER.** Each double below is written straight from DESIGN §1e's catalog table —
# nothing here is invented — and each one's job is to prove the hook surface can carry that card.
# If The Turk cannot be written, the design is wrong NOW, and discovering that when someone tries
# to author it is the expensive version.
#
# ⚠ They are also the only doubles anywhere that read REAL BOARD POSITION — the card beneath in a
# stack, the cards in a row, whether this card is covered. `test_comparator.gd`'s
# `BoardDependentGroup` fakes that with a flag; these read a real `Game`, which is the only way to
# learn whether the information a rule needs is even reachable from inside a grouping hook.
# ==============================================================================

## Groups itself with the card BENEATH it in its own stack — "its rank is the rank of the card
## beneath it" (DESIGN §1e). At the bottom of a column it does nothing.
class TurkCopiesBelow extends CardModifierSkill:
	func get_str() -> String: return "The Turk"
	func get_description() -> String: return "Rank of the card beneath it"
	func get_frame() -> int: return 0
	func combo_key(_hook: StringName = &"") -> String: return ""
	func on_meld_group_ranks(cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		var g := CardEnvironment.get_current_game()
		if not g or not data: return groups
		var pos := g.find_data_vec3(data)
		if pos == Vector3i.MIN or pos.z <= 0: return groups
		var col : ArrayCardData = g.get_zone_from_vec3(pos)[pos.y]
		var below : CardData = col.datas[pos.z - 1]
		if not cards.has(data) or not cards.has(below): return groups
		var pair : Array[CardData] = [data, below]
		var out : Array[Array] = [pair]
		out.append_array(groups)
		return out

## "Copies its highest adjacent neighbour's rank; alone, it is rank 1" — adjacency here is the
## card directly above or below in its own column.
class CleverHansCopiesNeighbour extends CardModifierSkill:
	func get_str() -> String: return "Clever Hans"
	func get_description() -> String: return "Copies its highest neighbour"
	func get_frame() -> int: return 0
	func combo_key(_hook: StringName = &"") -> String: return ""
	func on_meld_group_ranks(cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		var g := CardEnvironment.get_current_game()
		if not g or not data: return groups
		var pos := g.find_data_vec3(data)
		if pos == Vector3i.MIN: return groups
		var col : ArrayCardData = g.get_zone_from_vec3(pos)[pos.y]
		var best : CardData = null
		for dz : int in [-1, 1]:
			var z : int = pos.z + dz
			if z < 0 or z >= col.datas.size(): continue
			var n : CardData = col.datas[z]
			if not cards.has(n) or not n.rank: continue
			if best == null or float(n.rank.value) > float(best.rank.value): best = n
		#alone -> it is rank 1, i.e. it joins nothing
		if best == null or not cards.has(data): return groups
		var pair : Array[CardData] = [data, best]
		var out : Array[Array] = [pair]
		out.append_array(groups)
		return out

## "While COVERED, copies the most valuable card in its row." Uncovered it does nothing at all,
## which is what makes it the cover-state double.
class HumbugWhileCovered extends CardModifierSkill:
	func get_str() -> String: return "Humbug"
	func get_description() -> String: return "While covered, copies the best in its row"
	func get_frame() -> int: return 0
	func combo_key(_hook: StringName = &"") -> String: return ""
	func on_meld_group_ranks(cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		var g := CardEnvironment.get_current_game()
		if not g or not data: return groups
		if g.is_data_topmost(data): return groups
		var best : CardData = null
		for c : CardData in cards:
			if c == data or not c.rank: continue
			if best == null or float(c.rank.value) > float(best.rank.value): best = c
		if best == null or not cards.has(data): return groups
		var pair : Array[CardData] = [data, best]
		var out : Array[Array] = [pair]
		out.append_array(groups)
		return out

## "Becomes a rank present in its row, chosen deterministically." Deterministic here = the LOWEST
## rank present, so two identical boards always agree.
class WildcardJoinsRow extends CardModifierSkill:
	func get_str() -> String: return "The Wildcard"
	func get_description() -> String: return "Becomes a rank present in its row"
	func get_frame() -> int: return 0
	func combo_key(_hook: StringName = &"") -> String: return ""
	func on_meld_group_ranks(cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		if not data or not cards.has(data): return groups
		var pick : CardData = null
		for c : CardData in cards:
			if c == data or not c.rank: continue
			if pick == null or float(c.rank.value) < float(pick.rank.value): pick = c
		if pick == null: return groups
		var pair : Array[CardData] = [data, pick]
		var out : Array[Array] = [pair]
		out.append_array(groups)
		return out

## Unsourced (PLAN §3 marks it so): a STAMP-carried rule that keeps its own card out of every
## group. The split exerciser, on a carrier the other doubles do not use.
class StampedLoner extends CardModifierStamp:
	func get_str() -> String: return "Stamped Loner"
	func get_description() -> String: return "Never groups with anything"
	func get_frame() -> int: return 0
	func combo_key(_hook: StringName = &"") -> String: return ""
	func on_meld_group_ranks(_cards: Array[CardData], groups: Array[Array]) -> Array[Array]:
		if not data: return groups
		var out : Array[Array] = []
		for g : Array in groups:
			var rest : Array[CardData] = []
			for c : CardData in g:
				if c != data: rest.append(c)
			if not rest.is_empty(): out.append(rest)
		out.append([data] as Array[CardData])
		return out

## A real Game whose lower zone is `cols` columns of stacked ranks, so a rule can read the card
## beneath it, its row, and whether it is covered.
func stacked_game(cols: Array, extra: Array[CardData]) -> Game:
	var g := Game.new()
	var s := GameData.new()
	s.rules_deck = [
		rules_card(SkillScorerCascadeLower.new()),
		rules_card(SkillEvalPokerBest.new()),
	] as Array[CardData]
	for c : CardData in extra: s.rules_deck.append(c)
	for zone_x in 2:
		var types: Array[CardData] = []
		var zone_cols: Array[ArrayCardData] = []
		for i in range(cols.size()):
			var h := TestFactories.m_card(1, TestFactories.uc())
			h.stage = CardData.Stage.ZONE
			types.append(h)
			var stack : Array[CardData] = []
			if zone_x == 1:
				for rank : int in (cols[i] as Array):
					var card := TestFactories.m_card(float(rank), TestFactories.uc())
					card.stage = CardData.Stage.PLAY
					stack.append(card)
			zone_cols.append(TestFactories.col(stack))
		if zone_x == 0:
			s.upper_zone_type = types
			s.upper_zone = zone_cols
		else:
			s.lower_zone_type = types
			s.lower_zone = zone_cols
	g.state = s
	CardEnvironment.CURRENT = g
	return g

## How many cards share `card`'s rank class. 1 means it grouped with nobody.
func _class_size_of(profile: Scoring.HandProfile, card: CardData) -> int:
	var refs : Array = profile.card_rank_keys.get(card, [])
	if refs.is_empty(): return 0
	return (refs[0] as Scoring.RankClass).datas.size()

func test_authored_card_doubles() -> void:
	# --- The Turk: a rule reading THE CARD BENEATH IT, from inside a grouping hook -----------
	var turk := TurkCopiesBelow.new()
	var turk_rules : Array[CardData] = [rules_card(turk)]
	var g := stacked_game([[4, 9]], turk_rules)
	var column : Array[CardData] = g.state.lower_zone[0].datas
	var plain := await Scoring._get_hand_profiles_async(column)
	check(plain.ranks.classes.size() == 2,
			"1e control: 4 and 9 in a column are two rank classes with no rule",
			"%d classes" % plain.ranks.classes.size())
	turk.data = column[1]
	var turked := await Scoring._get_hand_profiles_async(column)
	check(turked.ranks.classes.size() == 1 and turked.ranks.classes[0].datas.size() == 2,
			"1e THE TURK is expressible: a grouping rule can read the card BENEATH it on the "
			+ "board and take that card's rank",
			"%d classes" % turked.ranks.classes.size())
	free_game(g)

	# --- Clever Hans: highest adjacent neighbour, and ALONE it stays rank 1 ------------------
	var hans := CleverHansCopiesNeighbour.new()
	var hans_rules : Array[CardData] = [rules_card(hans)]
	g = stacked_game([[2, 7, 5]], hans_rules)
	column = g.state.lower_zone[0].datas
	hans.data = column[1]
	var hansed := await Scoring._get_hand_profiles_async(column)
	var hans_cls : Scoring.RankClass = hansed.card_rank_keys[column[1]][0]
	var five_cls : Scoring.RankClass = hansed.card_rank_keys[column[2]][0]
	check(_class_size_of(hansed, column[1]) == 2 and hans_cls == five_cls,
			"1e CLEVER HANS is expressible: it joins its HIGHEST neighbour (the 5, not the 2)",
			"class of %d members" % _class_size_of(hansed, column[1]))
	free_game(g)

	g = stacked_game([[7]], hans_rules)
	column = g.state.lower_zone[0].datas
	hans.data = column[0]
	var lonely := await Scoring._get_hand_profiles_async(column)
	check(lonely.ranks.classes.size() == 1 and lonely.ranks.classes[0].datas.size() == 1,
			"1e CLEVER HANS alone joins nothing — the 'alone, it is rank 1' clause",
			"%d classes" % lonely.ranks.classes.size())
	free_game(g)

	# --- Humbug: DORMANT while uncovered, live while covered ---------------------------------
	# ⚠ The paired control is the same card in the same hand, differing ONLY in whether something
	# sits on top of it — which is the whole claim.
	var humbug := HumbugWhileCovered.new()
	var humbug_rules : Array[CardData] = [rules_card(humbug)]
	g = stacked_game([[3], [11]], humbug_rules)
	var row : Array[CardData] = [g.state.lower_zone[0].datas[0], g.state.lower_zone[1].datas[0]]
	humbug.data = row[0]
	var uncovered := await Scoring._get_hand_profiles_async(row)
	check(uncovered.ranks.classes.size() == 2,
			"1e HUMBUG uncovered is DORMANT — 3 and 11 stay two classes",
			"%d classes" % uncovered.ranks.classes.size())
	var lid := TestFactories.m_card(6, TestFactories.uc())
	lid.stage = CardData.Stage.PLAY
	g.state.lower_zone[0].datas.append(lid)
	g.state.revision += 1
	var covered := await Scoring._get_hand_profiles_async(row)
	check(covered.ranks.classes.size() == 1,
			"1e HUMBUG is expressible: COVERING it makes the same cards one class — a grouping "
			+ "rule can read its own cover state",
			"%d classes" % covered.ranks.classes.size())
	free_game(g)

	# --- The Wildcard: a rank present in its row, deterministically ---------------------------
	var wild := WildcardJoinsRow.new()
	var wild_rules : Array[CardData] = [rules_card(wild)]
	g = stacked_game([[12], [5], [9]], wild_rules)
	row = [g.state.lower_zone[0].datas[0], g.state.lower_zone[1].datas[0],
			g.state.lower_zone[2].datas[0]]
	wild.data = row[0]
	var wilded := await Scoring._get_hand_profiles_async(row)
	var wilded_again := await Scoring._get_hand_profiles_async(row)
	check(_class_size_of(wilded, row[0]) == 2,
			"1e THE WILDCARD is expressible: it joins a rank present in its row",
			"class of %d" % _class_size_of(wilded, row[0]))
	check(_class_size_of(wilded, row[0]) == _class_size_of(wilded_again, row[0]),
			"1e and it is DETERMINISTIC — 'chosen deterministically, on every board change'")
	free_game(g)

	# --- StampedLoner: the split exerciser, on a STAMP carrier --------------------------------
	var loner := StampedLoner.new()
	g = stacked_game([[8], [8], [8]], [] as Array[CardData])
	row = [g.state.lower_zone[0].datas[0], g.state.lower_zone[1].datas[0],
			g.state.lower_zone[2].datas[0]]
	var trio := await Scoring._get_hand_profiles_async(row)
	check(trio.ranks.classes.size() == 1 and trio.ranks.classes[0].datas.size() == 3,
			"3 control: three printed 8s are one class of three")
	row[0].stamp = loner
	loner.data = row[0]
	g.state.revision += 1
	var split := await Scoring._get_hand_profiles_async(row)
	check(split.ranks.classes.size() == 2 and _class_size_of(split, row[0]) == 1,
			"3 STAMPED LONER is expressible: a STAMP-carried rule pulls its own card out of a "
			+ "printed-identical group, leaving the other two together",
			"%d classes, its own holds %d" % [split.ranks.classes.size(),
					_class_size_of(split, row[0])])
	free_game(g)


# ==============================================================================
# TP-80j -- END IS THE ONLY THING THAT RESOLVES A SHOW.
#
# The act is retired: there is no Submit, no banking moment and no Next button. That leaves
# exactly one way for a show to finish, and this pins it from the other side -- every OTHER
# path the player can drive must leave the show LIVE. A scored line is the interesting one:
# it pays points, and paying points must not be mistaken for finishing.
#
# Driven on a GRID board, because that is the only board the game still has.
func test_end_show_is_the_only_resolver() -> void:
	var g := Game.new()
	CardEnvironment.CURRENT = g
	g.state = TestGridFixtures.build_fix_grid_1()
	# The detector is what scores a completed line, and the evaluator is what values it. Without
	# both, the "a scored line does not resolve the show" leg below would assert over a line that
	# never scored -- which is why the precondition after the placements is there.
	g.state.rules_deck = [
		rules_card(SkillLineDetector.new()),
		rules_card(SkillEvalPokerBest.new()),
	] as Array[CardData]
	g.save_state()
	var resolved : Array = []
	g.show_resolved.connect(func(won: bool, _s: int, _g: int) -> void: resolved.append(won))

	check(not g.state.show_ended and resolved.is_empty(),
			"precondition: a fresh grid show is live")

	# A placement that COMPLETES AND SCORES A LINE. Points are banked; the show is not over.
	# The cards are built here rather than drawn: this fixture carries no draw deck, and the
	# claim under test is about RESOLUTION, not about where a card came from.
	for x : int in 5:
		var card := TestFactories.m_card(x + 2, TestFactories.uc())
		card.stage = CardData.Stage.PLAY
		await g.place_card_in_grid(card, BoardCoord.new(0, x, 0, 0))
	check(g.state.live_total() > 0,
			"precondition: the completed row actually scored -- otherwise this proves nothing",
			str(g.state.live_total()))
	check(not g.state.show_ended and resolved.is_empty(),
			"a scored line does not resolve the show -- banking points is not finishing",
			"show_ended=%s resolved=%s" % [str(g.state.show_ended), str(resolved)])

	# The refill a placement asks for.
	await g.next()
	check(not g.state.show_ended and resolved.is_empty(),
			"a refill does not resolve the show",
			"show_ended=%s resolved=%s" % [str(g.state.show_ended), str(resolved)])

	# An undo.
	g.undo()
	check(not g.state.show_ended and resolved.is_empty(),
			"an undo does not resolve the show",
			"show_ended=%s resolved=%s" % [str(g.state.show_ended), str(resolved)])

	# ...and then the one path that does.
	g.end_show()
	check(g.state.show_ended and resolved.size() == 1,
			"End resolves the show, and nothing before it had",
			"show_ended=%s resolved=%s" % [str(g.state.show_ended), str(resolved)])
	CardEnvironment.CURRENT = null
	free_game(g)


# ==============================================================================
# TP-80i -- THE RETIRED ACT HAS NO READERS.
#
# Game.submit, _perform_submit and the Next button are gone. This fails if any of them comes
# back as a READER in product code, which a merge or a copied snippet can do silently -- the
# game would compile and a second, actless way to finish a show would exist again.
#
# Comment lines are skipped: a comment must stay free to explain what it forbids.
# Tests/ is exempt -- a test may still name a thing to prove it is absent.

## Directories that are product code. Tools/ is included: it ships with the game and a caller
## there is as real as one in Levels/.
const PRODUCT_DIRS : Array[String] = [
	"res://Levels", "res://Scripts", "res://Cards", "res://UI", "res://Tools",
]

## The retired act's identifiers. `next_button` is here but `next(` is NOT -- Game.next()
## survives the button that used to call it.
const RETIRED_ACT_READERS : Array[String] = [
	".submit(", "func submit", "_perform_submit", "next_button",
]

func test_retired_act_has_no_readers() -> void:
	var scanned := 0
	var offenders : Array[String] = []
	for dir : String in PRODUCT_DIRS:
		for path : String in _gd_scripts_under(dir):
			var f := FileAccess.open(path, FileAccess.READ)
			if not f: continue
			scanned += 1
			var n := 0
			for raw : String in f.get_as_text().split("
"):
				n += 1
				var line := raw.strip_edges()
				if line.begins_with("#"): continue
				for bad : String in RETIRED_ACT_READERS:
					if line.contains(bad):
						offenders.append("%s:%d: %s" % [path, n, line])
						break
	# Without this the gate passes by scanning nothing, which is the failure it is meant to catch.
	check(scanned >= 40, "the gate actually found the product scripts to scan",
			"only %d scripts scanned" % scanned)
	check(offenders.is_empty(),
			"no product code reads the retired act -- End is the only way to finish a show",
			"
".join(offenders))




# ==============================================================================
# THE SENTINEL GATE. `BoardCoord.NOWHERE` is a shared instance and `==` on a RefCounted is
# identity, so `coord == BoardCoord.NOWHERE` is TRUE for anything that returns that instance and
# FALSE for a coordinate rebuilt with the same components. It reads correctly and it is wrong
# half the time. `is_nowhere()` is always right.
#
# ⚠ This gate is the whole reason the value-semantics work is verifiable. Without it, `equals`
# can be forgotten at a call site where `==` could not be -- which is the one respect in which
# keeping BoardCoord a reference type is worse than making the coordinate a value.

## Comparing against the shared sentinel by identity. `is_nowhere()` replaces both.
## ⚠ Built by concatenation on purpose: spelled out, the gate's own constant is an offender and
## the gate fails on itself.
const SENTINEL_NAME := "BoardCoord.NOWH" + "ERE"
static func _forbidden_sentinel_compares() -> Array[String]:
	return ["== " + SENTINEL_NAME, "!= " + SENTINEL_NAME]

func test_nowhere_is_never_compared_by_identity() -> void:
	var scanned := 0
	var offenders : Array[String] = []
	for dir : String in PRODUCT_DIRS + ["res://Tests"]:
		for path : String in _gd_scripts_under(dir):
			# The type itself defines the sentinel and compares its components.
			if path.ends_with("board_coord.gd"): continue
			var f := FileAccess.open(path, FileAccess.READ)
			if not f: continue
			scanned += 1
			var n := 0
			for raw : String in f.get_as_text().split("
"):
				n += 1
				var line := raw.strip_edges()
				if line.begins_with("#"): continue
				for bad : String in _forbidden_sentinel_compares():
					if line.contains(bad):
						offenders.append("%s:%d: %s" % [path, n, line])
						break
	check(scanned >= 60, "the sentinel gate actually found the scripts to scan",
			"only %d scripts scanned" % scanned)
	check(offenders.is_empty(),
			"nothing compares against BoardCoord.NOWHERE by identity -- is_nowhere() is the test",
			"
".join(offenders))

# ==============================================================================
# THE ZONE-ONLY RATCHET.
#
# A test that asserts against the legacy zone renderer and never touches a grid is testing a
# renderer the game no longer uses. Eleven such files existed when this gate was written, and one
# of them was the LAYERING suite -- which is why a card drawing behind its own grid cell reached
# the owner by eye instead of failing a check.
#
# This does not fix them. It RATCHETS: the set may shrink, never grow. A new zone-only test fails
# here, and porting one fails here too until it is struck off the list below, so the list cannot
# rot into a lie.
#
# The set empties when the legacy zone rendering is deleted and these files have nowhere left to
# point -- until then, every name below is a known hole, not an oversight.

## Files that assert against the legacy renderer and reference no grid.
##
## ⚠ THIS LIST HOLDS TWO DIFFERENT KINDS OF ENTRY, and confusing them wastes a session.
##
## PORTABLE -- a fixture that merely happens to sit in a zone. It can and should move onto a grid,
## and its name is struck off when it does.
##
## MACHINERY -- a test OF the legacy zone machinery itself: the Vector3i position index, dynamic
## column add/remove, zone-array scoring sections. That machinery is still LIVE (measured:
## find_data_vec3 has 9 product callers, get_zone_from_vec3 7, is_data_topmost 7,
## add_column/remove_column 9), because the Entrance is still zone-shaped storage. These tests
## CANNOT port -- a grid has no fixed-width column to add or remove -- and they MUST NOT be
## deleted, because they cover code that still runs. They leave this list only when the machinery
## they test does.
##
## Marked below. Strike a PORTABLE name off when it moves; do not add one.
const ZONE_ONLY_TESTS : Array[String] = [
	# PORTABLE
	"res://Tests/Engine/test_fuzz.gd",
	"res://Tests/Engine/test_game_data.gd",
	"res://Tests/Map/test_persistence_fuzz.gd",
	"res://Tests/Map/test_run_manager.gd",
	"res://Tests/Visual/pause_time_spike.gd",
	# MACHINERY -- these test live legacy code and leave only when it does
	"res://Tests/Engine/test_board.gd",
	"res://Tests/Engine/test_mods.gd",
	"res://Tests/Engine/test_spotlight.gd",
	# ENTRANCE-ONLY -- they name upper_zone, which IS the Entrance and is not going away yet
	"res://Tests/Engine/test_prop_engine.gd",
	"res://Tests/Engine/test_statuses.gd",
	"res://Tests/Engine/test_suit_props.gd",
]

const ZONE_MARKERS : Array[String] = ["upper_zone", "lower_zone"]
## ⚠ NOT `BoardCoord`. It is the coordinate type for the Entrance too, so a file that merely
## ported its Entrance call sites would satisfy this list while gaining no grid coverage at all --
## which is exactly the false pass this ratchet exists to prevent. These markers all require a
## GRID to be present.
const GRID_MARKERS : Array[String] = [
	"grids[", "state.grids", "place_card_in_grid", "TestGridFixtures",
]

func test_zone_only_tests_do_not_multiply() -> void:
	var scanned := 0
	var zone_only : Array[String] = []
	for path : String in _gd_scripts_under("res://Tests"):
		var f := FileAccess.open(path, FileAccess.READ)
		if not f: continue
		var text := f.get_as_text()
		scanned += 1
		var names_zone := false
		for m : String in ZONE_MARKERS:
			if text.contains(m): names_zone = true
		if not names_zone: continue
		var names_grid := false
		for m : String in GRID_MARKERS:
			if text.contains(m): names_grid = true
		if not names_grid: zone_only.append(path)
	# A gate that scans nothing passes while proving nothing.
	check(scanned >= 30, "the ratchet actually found the test scripts to scan",
			"only %d scripts scanned" % scanned)
	var added : Array[String] = []
	for path : String in zone_only:
		if not ZONE_ONLY_TESTS.has(path): added.append(path)
	var ported : Array[String] = []
	for path : String in ZONE_ONLY_TESTS:
		if not zone_only.has(path): ported.append(path)
	check(added.is_empty(),
			"no NEW test asserts against the legacy renderer without also covering a grid",
			"
".join(added))
	check(ported.is_empty(),
			"the zone-only list is honest -- a ported file has been struck off it",
			"now covers a grid, strike it from ZONE_ONLY_TESTS:
" + "
".join(ported))

## Every .gd under `dir`, recursively. Skips addons/, which is vendored and not ours.
func _gd_scripts_under(dir: String) -> Array[String]:
	var out : Array[String] = []
	var d := DirAccess.open(dir)
	if not d: return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir.path_join(name)
		if d.current_is_dir():
			if name != "addons": out.append_array(_gd_scripts_under(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
	return out
