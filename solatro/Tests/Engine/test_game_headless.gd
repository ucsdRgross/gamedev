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
# undo, submit) through the real Game API and assert the outcomes a player sees.
# The single representation-level check (gutter BigNumber accumulation) is check_impl.

func suite_name() -> String:
	return "GAME HEADLESS"

func _ready() -> void:
	TestLog.line("============ GAME HEADLESS TEST PASS ============")
	behavior_section("PLAYER COMMANDS, HEADLESS")
	await test_command_guard_blocks_input()
	await test_try_grab_returns_stack()
	await test_try_place_moves_and_commits()
	await test_undo_reverts_state_and_history()
	await test_undo_rewinds_act_count()
	await test_undo_cancels_resolving_submit()
	await test_undo_at_game_over_rewinds_final_submit()
	test_add_deck_relinks_suit_backrefs()
	await test_score_line_headless_mutates_data()
	await test_submit_headless_full_act()
	finish()

func rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.active = true
	return c

# A minimal but real show fixture: rules cards carry the classic grabber/placer/scorer skills
# (always active because they live in rules_deck), and both zones have two paired 2-card
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
	var history_before := g.save_history.size()
	var used_before := g.submits_used
	await g.submit()
	check(g.save_history.size() == history_before and g.submits_used == used_before,
			"submit() is a no-op while processing (no history/act change)")
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

## submits_used lives on GameData so history snapshots carry it: undoing across a Submit must
## rewind the act count together with the board (owner bug report 2026-07-12 — the old
## Game-level counter survived undo, permanently eating acts).
func test_undo_rewinds_act_count() -> void:
	var g := make_game()
	g.save_state()   # baseline snapshot (act 0) so undo has somewhere to go
	await g.submit()
	check(g.submits_used == 1, "precondition: submit consumed an act")
	g.undo()
	check(g.submits_used == 0, "undo rewinds the act count with the board")
	check(g.save_history[-1].submits_used == 0,
			"the restored snapshot itself carries the rewound act count")
	CardEnvironment.CURRENT = null
	free_game(g)

## "The player pressing Undo" mid-scoring: a rules-card probe that calls game.undo() from
## inside the scoring cascade (headless resolves in one await chain, so the press can only
## come from within it — exactly what the live button does mid-animation).
class UndoDuringScoring extends CardModifierSkill:
	var pressed := false
	func get_str() -> String: return "UndoProbe"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_score_row(_zone: Array, _row: int) -> void:
		if pressed: return
		pressed = true
		var g := CardEnvironment.get_current_game()
		if g: g.undo()

## Undo during a resolving Submit cancels the act: the resolution fast-forwards and the
## board restores to the exact pre-submit snapshot — nothing scored, no act consumed, no
## new history entry, input handed back.
func test_undo_cancels_resolving_submit() -> void:
	var g := make_game()
	g.state.rules_deck.append(rules_card(UndoDuringScoring.new()))
	g.save_state()   # the committed pre-submit board the cancel restores
	var history_before := g.save_history.size()
	var lower_before : int = 0
	for col : ArrayCardData in g.state.lower_zone:
		lower_before += col.datas.size()
	await g.submit()
	check(g.submits_used == 0, "the cancelled Submit consumes NO act")
	check(g.save_history.size() == history_before, "the cancelled Submit commits nothing")
	var lower_after : int = 0
	for col : ArrayCardData in g.state.lower_zone:
		lower_after += col.datas.size()
	check(lower_after == lower_before,
			"the performed board is restored (not discarded)",
			"%d vs %d" % [lower_after, lower_before])
	check(g.state.total_score == 0, "no act score was applied", str(g.state.total_score))
	check(not g.processing, "input is handed back after the cancel")
	check(not g.act_cancelled, "the cancel flag is consumed by the restore")
	check(g.state.validate().is_empty(), "restored board validates")
	CardEnvironment.CURRENT = null
	free_game(g)

## Undo at the win/lose screen dismisses the outcome (show_unresolved) and rewinds the
## final Submit: the act comes back, input unlocks, and nothing was banked (fame only
## moves on Continue — exit_show — which never ran).
func test_undo_at_game_over_rewinds_final_submit() -> void:
	var g := make_game()
	g.save_state()
	var resolved : Array = []
	g.show_resolved.connect(func(won: bool, _s: int, _g: int) -> void: resolved.append(won))
	var unresolved : Array = []
	g.show_unresolved.connect(func() -> void: unresolved.append(true))
	await g.submit()
	await g.submit()
	await g.submit()
	check(resolved.size() == 1, "the third Submit resolves the show", str(resolved))
	check(g.processing, "the resolved show locks input")
	var history_at_over := g.save_history.size()
	g.undo()
	check(unresolved.size() == 1, "undo at the outcome screen emits show_unresolved")
	check(g.submits_used == Game.MAX_SUBMITS - 1,
			"undo rewinds the final Submit's act", str(g.submits_used))
	check(g.save_history.size() == history_at_over - 1,
			"the final Submit's snapshot is popped")
	check(not g.processing, "input unlocks — the show is live again")
	# the show can re-resolve after the rewind (undo -> submit again)
	await g.submit()
	check(resolved.size() == 2, "re-submitting after the rewind resolves the show again")
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
	await g.score_line(r, true, g.state.lower_zone, 0)  # row, lower gutter, index 0
	check(g.state.row_total == 7, "score_line adds to row_total headless", str(g.state.row_total))
	check_impl(g.state.scores_row_lower.size() >= 1 and g.state.scores_row_lower[0] != null,
			"score_line accumulates a gutter BigNumber headless (view skipped, no crash)")
	await g.score_line(r, false, [] as Array, 0)  # col path
	check(g.state.col_total == 7, "score_line adds to col_total headless")
	CardEnvironment.CURRENT = null
	free_game(g)

func test_submit_headless_full_act() -> void:
	var g := make_game()
	var history_before := g.save_history.size()
	await g.submit()
	check(g.submits_used == 1, "submit bumps submits_used")
	check(g.save_history.size() == history_before + 1, "submit commits one save")
	var lower_empty := g.state.lower_zone.all(func(c: ArrayCardData) -> bool: return c.datas.is_empty())
	check(lower_empty, "submit discards the lower (performed) board")
	check(g.state.total_score == g.state.mult_score,
			"first act's total_score equals this act's payout")
	check(g.state.total_score > 0,
			"a scored act pays out row_total x col_total > 0", str(g.state.total_score))
	check(g.state.scores_col.is_empty() and g.state.scores_row_lower.is_empty(),
			"gutters cleared after the act")
	check(g.state.validate().is_empty(), "board validates after submit")
	CardEnvironment.CURRENT = null
	free_game(g)
