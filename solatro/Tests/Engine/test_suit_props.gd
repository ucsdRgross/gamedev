extends SolatroTest
# res://Tests/Engine/test_suit_props.gd
# ==============================================================================
# SUIT PROPS (SUIT_PROPS_PLAN Phase 3 §3.6): the five real suits' spawn configs +
# prop mods driven through Game.run_props headless. Hoop/Knife score across a row,
# Ball/Fire fly ballistically down a column (mancala), Firework rises + banks column
# score; talents suppress; fire buffs count. Real suit classes, hand-built boards,
# view == null. The Ball worked example (t,,b5,t,t -> t1,,b5,t2,t2) is pinned here.
#
# CATEGORY MAP: all BEHAVIOR — these are the player-facing suit rules.
# ==============================================================================

func suite_name() -> String:
	return "SUIT PROPS"

func _ready() -> void:
	print("============ SUIT PROPS TEST PASS ============")
	behavior_section("HOOP / KNIFE (row travellers)")
	await test_hoop_scores_talents()
	await test_knife_scores_props()
	test_talented_suit_suppressed()
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

## One upper zone of single-card columns → row z=0 spans them; card i lives at (0, i, 0).
func row_game(cards: Array[CardData]) -> Game:
	var g := Game.new()
	var s := GameData.new()
	var types : Array[CardData] = []
	var cols : Array[ArrayCardData] = []
	for c in cards:
		c.stage = CardData.Stage.PLAY
		var h := CardData.new(); h.stage = CardData.Stage.ZONE
		types.append(h)
		cols.append(TestFactories.col([c] as Array[CardData]))
	s.upper_zone_type = types
	s.upper_zone = cols
	g.state = s
	g._begin_act()
	CardEnvironment.CURRENT = g
	return g

## One upper zone of a single column → card i lives at (0, 0, i).
func col_game(cards: Array[CardData]) -> Game:
	var g := Game.new()
	var s := GameData.new()
	for c in cards:
		c.stage = CardData.Stage.PLAY
	var h := CardData.new(); h.stage = CardData.Stage.ZONE
	s.upper_zone_type = [h] as Array[CardData]
	s.upper_zone = [TestFactories.col(cards)]
	g.state = s
	g._begin_act()
	CardEnvironment.CURRENT = g
	return g

func done(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

func juggling_stacks(card: CardData) -> int:
	for s : CardModifierStatus in card.statuses:
		if s is StatusJuggling: return s.stacks
	return 0

func has_burning(card: CardData) -> bool:
	for s : CardModifierStatus in card.statuses:
		if s is StatusBurning: return true
	return false

# ==============================================================================
# TESTS
# ==============================================================================

func test_hoop_scores_talents() -> void:
	# row: [hoop3, talent, talent, plain]. Each hoop scores the 2 talents (not itself/plain).
	var hoop := suit_card(3, PipSuitHoop.new())
	var g := row_game([hoop, talent(5), talent(5), plain(5)] as Array[CardData])
	await g.run_props(hoop.suit.spawn_props())
	check(g.state.row_total == 6,
			"3 hoops x 2 talents x 1 point = 6 into the row gutter", str(g.state.row_total))
	done(g)

func test_knife_scores_props() -> void:
	# row: [knife3, talent, plain, plain]. Knives score NO-skill cards incl. their own card
	# (self-pass), spin past the talent -> 3 plain cards (knife, plain, plain) x 3 knives = 9.
	var knife := suit_card(3, PipSuitKnife.new())
	var g := row_game([knife, talent(5), plain(5), plain(5)] as Array[CardData])
	await g.run_props(knife.suit.spawn_props())
	check(g.state.row_total == 9,
			"3 knives x 3 plain cards (incl. self) x 1 point = 9", str(g.state.row_total))
	done(g)

func test_talented_suit_suppressed() -> void:
	# a hoop card that is ALSO a talent (has a skill) spawns nothing.
	var talented_hoop := suit_card(4, PipSuitHoop.new()).with_skill(DummySkill.new())
	var g := row_game([talented_hoop, plain(5)] as Array[CardData])
	check(talented_hoop.suit.spawn_props().is_empty(),
			"a talented suit card suppresses its own suit effect")
	done(g)

func test_ball_worked_example() -> void:
	# column t,,b5,t,t (b5 = rank-5 Ball at index 2). mancala from index 2 skips the plain at 1
	# and the ball itself -> targets 3,4,0,3,4 -> final Juggling stacks t1,,b5,t2,t2.
	var t0 := talent(9)
	var p1 := plain(9)
	var b5 := suit_card(5, PipSuitBall.new())
	var t3 := talent(9)
	var t4 := talent(9)
	var g := col_game([t0, p1, b5, t3, t4] as Array[CardData])
	await g.run_props(b5.suit.spawn_props())
	check(juggling_stacks(t0) == 1, "index 0 talent juggles 1", str(juggling_stacks(t0)))
	check(juggling_stacks(t3) == 2, "index 3 talent juggles 2 (hit twice)", str(juggling_stacks(t3)))
	check(juggling_stacks(t4) == 2, "index 4 talent juggles 2 (hit twice)", str(juggling_stacks(t4)))
	check(juggling_stacks(p1) == 0 and juggling_stacks(b5) == 0,
			"the plain card and the ball itself are never targeted (no skill)")
	done(g)

func test_fire_skips_talents_and_fire() -> void:
	# column [fire2, talent, fire, plain, plain]. eligible = no-skill AND not Fire -> only the
	# two plains. rank-2 fire -> 2 targets -> both plains gain Burning; talent/fire do not.
	var fire := suit_card(2, PipSuitFire.new())
	var t1 := talent(9)
	var other_fire := suit_card(3, PipSuitFire.new())
	var p3 := plain(9)
	var p4 := plain(9)
	var g := col_game([fire, t1, other_fire, p3, p4] as Array[CardData])
	await g.run_props(fire.suit.spawn_props())
	check(has_burning(p3) and has_burning(p4), "fire drops Burning on the two eligible plains")
	check(not has_burning(t1) and not has_burning(other_fire),
			"fire skips talents AND other Fire cards")
	done(g)

func test_fire_buffs_count() -> void:
	# a Burning rank-2 Hoop spawns 2 x (1 + stacks) hoops (count buff only).
	var hoop := suit_card(2, PipSuitHoop.new())
	hoop.add_status(CardModifierStatus.stacked(StatusBurning, 3))  # fire_mult = 4
	var g := row_game([hoop, talent(5)] as Array[CardData])
	var spawners := hoop.suit.spawn_props()
	check(spawners.size() == 1 and (spawners[0] as PropSpawner).remaining == 8,
			"rank 2 x fire_mult 4 = 8 hoops", str((spawners[0] as PropSpawner).remaining))
	done(g)

func test_firework_banks_column() -> void:
	# a lone rank-3 firework (nothing above it) banks 3 x 1 into its column gutter.
	var fw := suit_card(3, PipSuitFirework.new())
	var g := col_game([fw] as Array[CardData])
	await g.run_props(fw.suit.spawn_props())
	check(g.state.col_total == 3,
			"3 fireworks each bank 1 column point even with an empty rise route", str(g.state.col_total))
	done(g)

func test_juggling_pays_on_score() -> void:
	# a card carrying Juggling(3), when scored (on_score broadcast), banks 3 into its column.
	var card := plain(5)
	card.add_status(CardModifierStatus.stacked(StatusJuggling, 3))
	var g := col_game([card] as Array[CardData])
	await g.run_all_mods(&"on_score", card)
	check(g.state.col_total == 3, "Juggling pays its stacks into the column when scored",
			str(g.state.col_total))
	done(g)
