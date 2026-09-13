extends TestSuite
# res://Tests/Engine/test_suit_props.gd

#The five real suits' spawn configs and prop mods, driven through Game.run_props headless: Hoop and
#Knife cross a row, Ball and Fire fly down a cell's own stack (mancala), Firework rises and banks
#column score. Fire buffs the COUNT. The Ball worked example is pinned in its own test.

#⚠ A SUIT FIRES ONLY FROM A CELL WHOSE MARK AGREES ON SUIT, so every board below marks the cell its
#spawner stands on -- an unmarked or disagreeing cell spawns nothing at all, talented or not.
#CATEGORY MAP: all BEHAVIOR -- these are the player-facing suit rules.

func suite_name() -> String:
	return "SUIT PROPS"

func _ready() -> void:
	TestLog.line("============ SUIT PROPS TEST PASS ============")
	behavior_section("HOOP / KNIFE (row travellers)")
	await test_hoop_scores_talents()
	await test_knife_scores_props()
	behavior_section("THE MARK IS THE GATE")
	await test_no_props_without_a_suit_match()
	await test_a_talented_card_fires_on_a_matching_mark()
	await test_a_talent_is_not_suppressed_on_a_match()
	behavior_section("BALL / FIRE (ballistic, mancala)")
	await test_ball_worked_example()
	await test_fire_skips_talents_and_fire()
	test_fire_buffs_count()
	behavior_section("FIREWORK + on_score BROADCAST")
	await test_firework_banks_column()
	await test_juggling_pays_on_score()
	finish()

# ==============================================================================
# FIXTURE HELPERS
# ==============================================================================
class DummySkill extends CardModifierSkill:
	func get_str() -> String: return "Talent"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0

## A suit card (no skill) — a live suit-effect source.
func suit_card(rank: int, suit: PipSuit) -> CardData:
	return CardData.new().with_rank(PipRankNumeral.new().with_value(rank)).with_suit(suit)

## A talent: carries a skill, so PropScoreTalents scores it and PropScoreProps spins past it.
func talent(rank: int) -> CardData:
	return suit_card(rank, PipSuitHoop.new()).with_skill(DummySkill.new())

## A plain "prop" card: no skill (scored by knives, ignored by hoops).
func plain(rank: int) -> CardData:
	return suit_card(rank, PipSuitHoop.new())

#A bare Game over one empty 5x5 grid, view null: a suit launches from a CELL, and only a cell can
#carry the mark that lets it fire, so every board here is a real grid rather than the Entrance.
func grid_game() -> Game:
	var g := Game.new()
	g.state = TestGridFixtures.build_fix_grid_1()
	g._begin_act()
	CardEnvironment.CURRENT = g
	return g

#Marks grid 0's cell (x, y) with a card printing `suit`, which is what lets a card of that suit
#standing there fire at all. Rank 1 so the mark's own rank agrees with nothing these boards place.
func mark_cell(g: Game, x: int, y: int, suit: PipSuit) -> void:
	var grid : GridData = g.state.grids[0]
	BoardPlan.write_mark(grid.cell_types[grid.cell_index(x, y)], suit_card(1, suit), false)

## Grid 0's row 0, card i in cell (i, 0) -- the row a Hoop or a Knife travels.
func row_game(cards: Array[CardData]) -> Game:
	var g := grid_game()
	for i : int in cards.size():
		Board.place_in_cell(g.state, cards[i], BoardCoord.new(0, i, 0, 0))
	return g

#Grid 0's cell (0, 0) holding every card as ONE stack, bottom first: Ball, Fire and Firework walk a
#cell's own stack and not a grid column, and the whole stack shares that cell's single mark.
func col_game(cards: Array[CardData]) -> Game:
	var g := grid_game()
	for card : CardData in cards:
		Board.place_in_cell(g.state, card, BoardCoord.new(0, 0, 0, 0))
	return g

func done(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

func juggling_stacks(card: CardData) -> int:
	for s : CardModifierStatus in card.statuses:
		if s is StatusJuggling: return s.stacks
	return 0

#How many props a spawn launches, which is the number a control board is compared against: a
#talented card and a plain one on the same matching mark must launch the same count.
func launched(spawners: Array[PropSpawner]) -> int:
	var total := 0
	for sp : PropSpawner in spawners:
		total += sp.remaining
	return total

func has_burning(card: CardData) -> bool:
	for s : CardModifierStatus in card.statuses:
		if s is StatusBurning: return true
	return false

# ==============================================================================
# TESTS
# ==============================================================================

#Row [hoop3, talent, talent, plain] on a Hoop mark under the hoop: each hoop scores the 2 talents
#and never itself or the plain card.

#⚠ ASSERT THE SCORE THE PLAYER SEES, NEVER `row_total` -- that field is the retired act payout's
#accumulator and `live_total()` does not read it, so a check written against it passes while the
#points reach nothing the player ever sees.
func test_hoop_scores_talents() -> void:
	var hoop := suit_card(3, PipSuitHoop.new())
	var g := row_game([hoop, talent(5), talent(5), plain(5)] as Array[CardData])
	mark_cell(g, 0, 0, PipSuitHoop.new())
	var spawners : Array[PropSpawner] = await hoop.suit.spawn_props()
	await g.run_props(spawners)
	check(g.state.board_total() == 6.0,
			"3 hoops x 2 talents x 1 point = 6, and it reaches the board total",
			"board_total=%f row_total=%d" % [g.state.board_total(), g.state.row_total])
	check(g.state.live_total() > 0,
			"...so the goal check can see it", "live_total=%d" % g.state.live_total())
	done(g)

#Row [knife3, talent, plain, plain] on a Knife mark under the knife: knives score every no-skill
#card including their own (self-pass) and spin past the talent, so 3 knives x 3 plain cards = 9.
func test_knife_scores_props() -> void:
	var knife := suit_card(3, PipSuitKnife.new())
	var g := row_game([knife, talent(5), plain(5), plain(5)] as Array[CardData])
	mark_cell(g, 0, 0, PipSuitKnife.new())
	var spawners : Array[PropSpawner] = await knife.suit.spawn_props()
	await g.run_props(spawners)
	check(g.state.board_total() == 9.0,
			"3 knives x 3 plain cards (incl. self) x 1 point = 9, into the board total",
			"board_total=%f row_total=%d" % [g.state.board_total(), g.state.row_total])
	done(g)

#The mark decides WHETHER a suit fires: an untalented Hoop standing on a KNIFE mark spawns nothing
#and its row banks nothing, because a mark that disagrees on suit fires no effect at all.
func test_no_props_without_a_suit_match() -> void:
	var hoop := suit_card(3, PipSuitHoop.new())
	var g := row_game([hoop, talent(5), talent(5)] as Array[CardData])
	mark_cell(g, 0, 0, PipSuitKnife.new())
	var spawners : Array[PropSpawner] = await hoop.suit.spawn_props()
	await g.run_props(spawners)
	check(spawners.is_empty() and is_zero_approx(g.state.board_total()),
			"TP-40: an untalented Hoop on a Knife mark spawns zero props and banks nothing",
			"spawners=%d board_total=%f" % [spawners.size(), g.state.board_total()])
	done(g)

#A talent no longer suppresses its own card's suit effect: the talented Hoop on a Hoop mark fires,
#and its hoops score itself along with the other two talents they pass.
func test_a_talented_card_fires_on_a_matching_mark() -> void:
	var talented_hoop := suit_card(4, PipSuitHoop.new()).with_skill(DummySkill.new())
	var g := row_game([talented_hoop, talent(5), talent(5)] as Array[CardData])
	mark_cell(g, 0, 0, PipSuitHoop.new())
	var spawners : Array[PropSpawner] = await talented_hoop.suit.spawn_props()
	await g.run_props(spawners)
	check(not spawners.is_empty() and is_equal_approx(g.state.board_total(), 12.0),
			"TP-41: a TALENTED Hoop on a Hoop mark spawns its props -- 4 hoops x 3 talents = 12",
			"spawners=%d board_total=%f" % [spawners.size(), g.state.board_total()])
	done(g)

#The talent suppression is retired, so a talented card on a matching mark launches exactly what the
#untalented control launches: rank x fire_mult, with the talent changing nothing about the count.
func test_a_talent_is_not_suppressed_on_a_match() -> void:
	var talented_hoop := suit_card(4, PipSuitHoop.new()).with_skill(DummySkill.new())
	var talented_board := row_game([talented_hoop, plain(5)] as Array[CardData])
	mark_cell(talented_board, 0, 0, PipSuitHoop.new())
	var talented_spawners : Array[PropSpawner] = await talented_hoop.suit.spawn_props()
	done(talented_board)
	var plain_hoop := suit_card(4, PipSuitHoop.new())
	var control := row_game([plain_hoop, plain(5)] as Array[CardData])
	mark_cell(control, 0, 0, PipSuitHoop.new())
	var control_spawners : Array[PropSpawner] = await plain_hoop.suit.spawn_props()
	check(launched(talented_spawners) == launched(control_spawners)
			and launched(control_spawners) == 4,
			"TP-42: a talented Hoop on a Hoop mark launches what the untalented control does",
			"talented=%d control=%d" % [launched(talented_spawners), launched(control_spawners)])
	done(control)

#Stack t,,b5,t,t in one cell (b5 = rank-5 Ball at height 2) on a Ball mark: the mancala walk from
#height 2 skips the plain at 1 and the ball itself, so targets 3,4,0,3,4 leave stacks t1,,b5,t2,t2.
func test_ball_worked_example() -> void:
	var t0 := talent(9)
	var p1 := plain(9)
	var b5 := suit_card(5, PipSuitBall.new())
	var t3 := talent(9)
	var t4 := talent(9)
	var g := col_game([t0, p1, b5, t3, t4] as Array[CardData])
	mark_cell(g, 0, 0, PipSuitBall.new())
	var spawners : Array[PropSpawner] = await b5.suit.spawn_props()
	await g.run_props(spawners)
	check(juggling_stacks(t0) == 1, "index 0 talent juggles 1", str(juggling_stacks(t0)))
	check(juggling_stacks(t3) == 2, "index 3 talent juggles 2 (hit twice)", str(juggling_stacks(t3)))
	check(juggling_stacks(t4) == 2, "index 4 talent juggles 2 (hit twice)", str(juggling_stacks(t4)))
	check(juggling_stacks(p1) == 0 and juggling_stacks(b5) == 0,
			"the plain card and the ball itself are never targeted (no skill)")
	done(g)

#Stack [fire2, talent, fire, plain, plain] in one cell on a Fire mark: eligible is no-skill AND not
#Fire, so the rank-2 fire's 2 targets are the two plains, never the talent or the other fire.
func test_fire_skips_talents_and_fire() -> void:
	var fire := suit_card(2, PipSuitFire.new())
	var t1 := talent(9)
	var other_fire := suit_card(3, PipSuitFire.new())
	var p3 := plain(9)
	var p4 := plain(9)
	var g := col_game([fire, t1, other_fire, p3, p4] as Array[CardData])
	mark_cell(g, 0, 0, PipSuitFire.new())
	var spawners : Array[PropSpawner] = await fire.suit.spawn_props()
	await g.run_props(spawners)
	check(has_burning(p3) and has_burning(p4), "fire drops Burning on the two eligible plains")
	check(not has_burning(t1) and not has_burning(other_fire),
			"fire skips talents AND other Fire cards")
	done(g)

#A Burning rank-2 Hoop on a Hoop mark spawns 2 x (1 + 3 stacks) hoops: Burning buffs the COUNT and
#nothing else.
func test_fire_buffs_count() -> void:
	var hoop := suit_card(2, PipSuitHoop.new())
	hoop.add_status(CardModifierStatus.stacked(StatusBurning, 3))
	var g := row_game([hoop, talent(5)] as Array[CardData])
	mark_cell(g, 0, 0, PipSuitHoop.new())
	var spawners : Array[PropSpawner] = await hoop.suit.spawn_props()
	check(spawners.size() == 1 and (spawners[0] as PropSpawner).remaining == 8,
			"rank 2 x fire_mult 4 = 8 hoops", str((spawners[0] as PropSpawner).remaining))
	done(g)

#A lone rank-3 firework on a Firework mark, with nothing above it, banks 3 x 1 into its column
#gutter even though its rise route is empty.
func test_firework_banks_column() -> void:
	var fw := suit_card(3, PipSuitFirework.new())
	var g := col_game([fw] as Array[CardData])
	mark_cell(g, 0, 0, PipSuitFirework.new())
	var spawners : Array[PropSpawner] = await fw.suit.spawn_props()
	await g.run_props(spawners)
	check(g.state.col_total == 3,
			"3 fireworks each bank 1 column point even with an empty rise route", str(g.state.col_total))
	done(g)

#A card carrying Juggling(3) banks 3 into its column when the on_score broadcast reaches it.

#⚠ THIS ASSERTED `col_total`, AND IT PASSED BECAUSE THE POINTS WERE BEING LOST: `col_total` is the
#retired act payout's total, which `live_total()` does not read, so the check asks the bucket the
#shown score is derived from. A test calibrated to a defect passes because the defect exists.
func test_juggling_pays_on_score() -> void:
	var card := plain(5)
	card.add_status(CardModifierStatus.stacked(StatusJuggling, 3))
	var g := col_game([card] as Array[CardData])
	await g.run_all_mods(&"on_score", card)
	check(g.state.line_score(g.state.scores_col, 0, 0, 0) == 3.0,
			"Juggling pays its stacks into the column bucket the shown score is derived from",
			"got %f" % g.state.line_score(g.state.scores_col, 0, 0, 0))
	check(g.state.board_total() > 0.0,
			"...so the board's own score actually moves, which col_total never made it do",
			"board_total %f" % g.state.board_total())
	done(g)
