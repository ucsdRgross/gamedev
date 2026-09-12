extends TestSuite
# res://Tests/Engine/test_board_plan.gd

#A mark IS the existing `cell_types[i]` card with a rank or a suit printed on it -- no second array
#and no flag. CATEGORY MAP: what a mark copies is BEHAVIOR, while the predicate, the backrefs and
#every `validate()` claim are IMPLEMENTATION pins on a debug invariant checker.
func suite_name() -> String:
	return "BOARD PLAN"

func _ready() -> void:
	TestLog.line("============ BOARD PLAN TEST PASS ============")
	implementation_section("THE MARK PREDICATE")
	test_is_marked_asks_rank_or_suit()
	behavior_section("WRITING AND CLEARING A MARK")
	test_write_mark_copies_every_printed_slot()
	implementation_section("A MARK'S BACKREFS POINT AT THE MARK")
	test_write_mark_relinks_the_copied_backrefs()
	behavior_section("THE PLANNER SHIPS IN THE RULES DECK")
	test_fresh_show_carries_one_localised_planner()
	implementation_section("I6: A DEALT MARK NAMES A CARD THE STATE HOLDS")
	test_i6_fails_a_mark_the_deck_never_had()
	test_i6_exempts_a_granted_mark()
	test_i6_passes_a_mark_the_deck_prints()
	finish()

## A 5x5 board with the plan deck in draw -- the state every check below starts from.
func make_state() -> GameData:
	var state := TestGridFixtures.build_fix_grid_1()
	state.draw_deck = TestDecks.plan_deck()
	for card : CardData in state.draw_deck:
		card.stage = CardData.Stage.DRAW
	return state

## Marks grid 0's first cell with exactly the pips I6's fixtures need, which no deck card prints.
func mark_first_cell(state: GameData, rank_value: float, suit: GDScript) -> CardData:
	var mark : CardData = state.grids[0].cell_types[0]
	mark.rank = PipRankNumeral.new().with_value(rank_value)
	mark.suit = suit.new() as PipSuit
	return mark

## A source wearing every printed slot plus a runtime status, so one write covers each slot and the refusal to copy a status.
func decorated_source() -> CardData:
	return TestDecks.plan_deck()[2].with_skill(SkillExtraPoint.new()) \
			.with_stamp(StampDoubleTrigger.new()) \
			.with_status(StatusBurning.new())

#TP-11: a mark is a faithful picture of what its card PRINTS, and a status is a runtime condition
#rather than a print -- so it is the one thing that never crosses.
func test_write_mark_copies_every_printed_slot() -> void:
	var state := make_state()
	var source := decorated_source()
	var mark : CardData = state.grids[0].cell_types[0]
	BoardPlan.write_mark(mark, source, true)
	check(PipComparator.printed_same(mark.rank, source.rank),
			"TP-11: the mark prints the source's rank")
	check(PipComparator.printed_same(mark.suit, source.suit),
			"TP-11: the mark prints the source's suit")
	check(mark.skill != null and is_same(mark.skill.get_script(), source.skill.get_script()),
			"TP-11: the mark carries the source's skill", "got %s" % mark.skill)
	check(mark.stamp != null and is_same(mark.stamp.get_script(), source.stamp.get_script()),
			"TP-11: the mark carries the source's stamp", "got %s" % mark.stamp)
	check(mark.statuses.is_empty(), "TP-11: a status never crosses onto a mark",
			"got %d" % mark.statuses.size())
	check((mark.type as TypeGridCell).granted,
			"TP-11: write_mark records the granted argument it was passed")
	check(mark.rank != source.rank and mark.suit != source.suit
			and mark.skill != source.skill and mark.stamp != source.stamp,
			"TP-11: every copied slot is a fresh instance the source does not share")
	source.rank.value = 9
	check(not PipComparator.printed_same(mark.rank, source.rank),
			"TP-11: changing the source's rank afterwards leaves the mark alone")
	BoardPlan.clear_mark(mark)
	check(not BoardPlan.is_marked(mark) and mark.skill == null and mark.stamp == null
			and not (mark.type as TypeGridCell).granted,
			"TP-11: clear_mark leaves a bare cell type behind")

#TP-12: `duplicate_deep` does not carry a WeakRef backref, so without the relink every copied
#modifier answers for no card at all and a hook reading `data` reads null.
func test_write_mark_relinks_the_copied_backrefs() -> void:
	var state := make_state()
	var source := decorated_source()
	var mark : CardData = state.grids[0].cell_types[0]
	BoardPlan.write_mark(mark, source, false)
	var strays : Array[String] = []
	for mod : CardModifier in [mark.skill, mark.type, mark.stamp, mark.suit]:
		if mod and mod.data and mod.data != mark: strays.append(mod.get_str())
	check(strays.is_empty(), "TP-12: no modifier on the mark answers for another card",
			"stray: %s" % ", ".join(strays))
	check(mark.skill.data == mark and mark.suit.data == mark,
			"TP-12: the copied skill and suit both resolve to the mark itself")

## Only `validate()`'s I6 lines -- every other invariant is another suite's claim.
func i6_violations(state: GameData) -> Array[String]:
	var out : Array[String] = []
	for violation : String in state.validate():
		if violation.begins_with("I6:"): out.append(violation)
	return out

## The predicate IS the definition of marked: either printed pip on its own is enough.
func test_is_marked_asks_rank_or_suit() -> void:
	var state := make_state()
	var bare : CardData = state.grids[0].cell_types[0]
	check(not BoardPlan.is_marked(bare), "a freshly built cell type is not marked")
	var ranked : CardData = state.grids[0].cell_types[1]
	ranked.rank = PipRankNumeral.new().with_value(3)
	check(BoardPlan.is_marked(ranked), "a rank alone marks a cell")
	var suited : CardData = state.grids[0].cell_types[2]
	suited.suit = PipSuitHoop.new()
	check(BoardPlan.is_marked(suited), "a suit alone marks a cell")

## TP-16: a dealt mark of a card no playing card prints cannot have come from the deal.
func test_i6_fails_a_mark_the_deck_never_had() -> void:
	var state := make_state()
	mark_first_cell(state, 9, PipSuitHoop)
	var reported := i6_violations(state)
	check(reported.size() == 1 and reported[0].contains("(0,0)"),
			"TP-16: I6 reports cell (0,0)'s rank 9 mark, which the 1-5 deck never prints",
			"I6 said: %s" % ", ".join(reported))

## TP-16: both halves run on ONE state, so the pass is the flag's doing and not a quiet board.
func test_i6_exempts_a_granted_mark() -> void:
	var state := make_state()
	var mark := mark_first_cell(state, 9, PipSuitHoop)
	check(not i6_violations(state).is_empty(),
			"TP-16: the dealt form of this mark is reported")
	(mark.type as TypeGridCell).granted = true
	check(i6_violations(state).is_empty(),
			"TP-16: ...and setting granted exempts the very same mark",
			"I6 said: %s" % ", ".join(i6_violations(state)))

## TP-16: the membership test in the other direction -- a mark the deck DOES print passes.
func test_i6_passes_a_mark_the_deck_prints() -> void:
	var state := make_state()
	mark_first_cell(state, 3, PipSuitHoop)
	check(i6_violations(state).is_empty(),
			"TP-16: a dealt mark of the 3 of Hoops, which the deck holds, passes I6",
			"I6 said: %s" % ", ".join(i6_violations(state)))

## A fresh show's rules deck, built by the real `Game.add_deck` from the mirror of shipped `rules1`.
func fresh_show_rules() -> Array[CardData]:
	var g := Game.new()
	CardEnvironment.CURRENT = g
	var previous : RunState = Main.save_info
	var run := RunState.new()
	run.card_datas = TestDecks.plan_deck()
	run.rule_datas = TestDecks.standard_rules()
	Main.save_info = run
	g.add_deck()
	var rules : Array[CardData] = g.state.rules_deck
	Main.save_info = previous
	CardEnvironment.CURRENT = null
	g.free()
	return rules

#The planner has to sit AFTER the allotment card: `on_game_start` reaches the rules deck in array
#order, and the allotment's creators build their grids on the sweep that follows it, so an earlier
#planner would deal onto a board with no grids at all.
func test_fresh_show_carries_one_localised_planner() -> void:
	var rules := fresh_show_rules()
	var planner : CardModifier = null
	var planner_at := -1
	var allotment_at := -1
	var planners := 0
	for i : int in rules.size():
		var skill : CardModifier = rules[i].skill
		if skill is SkillBoardPlanner:
			planner = skill
			planner_at = i
			planners += 1
		if skill is SkillGridAllotment: allotment_at = i
	check(planners == 1, "S3: a fresh show's rules deck holds exactly one board planner",
			"rules: %s" % ", ".join(TestDecks.rules_skill_names(rules)))
	check(allotment_at != -1 and planner_at > allotment_at,
			"S3: the planner is dealt after the grid allotment card, which is the hook order",
			"allotment at %d, planner at %d" % [allotment_at, planner_at])
	var planner_name := TRANSLATION.find(&"BOARD_PLANNER_CARD")
	var planner_description := TRANSLATION.find(&"BOARD_PLANNER_CARD_DESCRIPTION")
	check(planner_name != "" and planner_name != "BOARD_PLANNER_CARD",
			"S3: the planner's name is localised, not the bare key", "got '%s'" % planner_name)
	check(planner_description != "" and planner_description != "BOARD_PLANNER_CARD_DESCRIPTION",
			"S3: the planner's description is localised, not the bare key",
			"got '%s'" % planner_description)
	check(planner != null and planner.get_str() == planner_name
			and planner.get_description() == planner_description,
			"S3: the card reads both strings through the localisation table")
