extends TestSuite
# res://Tests/Engine/test_mark_match.gd

#A mark is the cell's own zone card wearing a copied face, so the engine must never treat what it
#copied as a card in play: a mark is never spotlit and it blocks nothing. CATEGORY MAP: BEHAVIOR --
#a copied skill answering the board's broadcasts is an effect the player would watch fire.
func suite_name() -> String:
	return "MARK MATCH"

func _ready() -> void:
	TestLog.line("============ MARK MATCH TEST PASS ============")
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

## Marks grid 0's cell `index` from `source` and hands back the cell's own zone card.
func mark_cell(state: GameData, index: int, source: CardData) -> CardData:
	var mark : CardData = state.grids[0].cell_types[index]
	BoardPlan.write_mark(mark, source, false)
	return mark

## Puts `card` in grid 0's cell (x, y), where nothing covers it.
func place_in_cell(state: GameData, x: int, y: int, card: CardData) -> void:
	var grid : GridData = state.grids[0]
	grid.cells[grid.cell_index(x, y)].datas.append(card)
	state.revision += 1

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


# ==============================================================================
# TP-44 -- a mark answers no broadcast
# ==============================================================================

#⚠ THE SCORING BEAM IS THE LEVER, BECAUSE MEASURED: a card in a grid cell is not naturally spotlit
#at all -- the legacy position index carries no grid coordinate, so the coverage walk fails closed
#and every grid card is dark until the beam lands on it. Both cards here are forced, one control.
func test_a_mark_answers_no_broadcast() -> void:
	var g := make_game()
	var mark := mark_cell(g.state, 0, play_card(3, SpotlightTestSkill.make("mark")))
	var extra_point := mark_cell(g.state, 1, play_card(4, SkillExtraPoint.new()))
	var control := play_card(5, SpotlightTestSkill.make("control"))
	place_in_cell(g.state, 2, 0, control)
	var mark_spy := mark.skill as SpotlightTestSkill
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
	await g.run_all_mods(&"on_spotlight")
	check(control_spy.spotlight_calls == 2 and mark_spy.spotlight_calls == 0,
			"TP-44: a board-wide broadcast reaches the control and never the mark",
			"control %d, mark %d" % [control_spy.spotlight_calls, mark_spy.spotlight_calls])
	check(control.skill.is_spotlit(),
			"precondition: is_spotlit() is true on the control's own skill")
	check(not extra_point.skill.is_spotlit(),
			"TP-44: is_spotlit() is false on a mark's copied skill")
	check(not mark.type.is_spotlit(),
			"TP-44: and false on the marked cell's own type")
	free_game(g)


# ==============================================================================
# TP-45 -- a mark blocks nothing
# ==============================================================================

#TP-45: a mark is transparent to the spotlight rule -- it covers nothing, so every answer the rule
#gives elsewhere on the board has to be the same with the mark there and gone.
func test_a_mark_blocks_nothing() -> void:
	var g := make_game()
	var stacked := fill_lower(g)
	var mark := mark_cell(g.state, 0, play_card(3, SpotlightTestSkill.make("mark")))
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
