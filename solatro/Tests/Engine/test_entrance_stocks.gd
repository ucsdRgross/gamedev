extends TestSuite
# res://Tests/Engine/test_entrance_stocks.gd

# ENTRANCE STOCKS: each slot owns the ordered cards it will draw, and the one shuffle is
# dealt round-robin left to right across them.

# CATEGORY MAP: BEHAVIOR -- which card a slot produces and when the show runs out of them.
# The walker and verifier checks are IMPLEMENTATION.

func suite_name() -> String:
	return "ENTRANCE STOCKS"

func _ready() -> void:
	TestLog.line("============ ENTRANCE STOCKS TEST PASS ============")
	await run_round_robin_deal_test()
	await run_same_order_deals_identically_test()
	await run_replayed_placement_is_identical_test()
	await run_one_empty_slot_is_not_an_empty_deck_test()
	await run_walkers_reach_a_stock_card_test()
	check_all_tests_registered()
	finish()


# ==============================================================================
# FIXTURE
# ==============================================================================

## A Game with `slots` real Entrance slots, `deck` dealt across them by the bootstrap's own deal.
func _stock_game(deck: Array[CardData], slots: int) -> Game:
	var g := Game.new()
	var state := GameData.new()
	for card : CardData in deck:
		card.stage = CardData.Stage.DRAW
	state.entrance_stocks()[0].datas.assign(deck)
	var rules : Array[CardData] = []
	var adders : Array[SkillAdderInputUpper] = []
	for _i : int in slots:
		var adder := SkillAdderInputUpper.new()
		adders.append(adder)
		var card := CardData.new().with_skill(adder)
		card.stage = CardData.Stage.RULES
		adder.spotlit = true
		rules.append(card)
	state.rules_deck = rules
	g.state = state
	CardEnvironment.CURRENT = g
	for adder : SkillAdderInputUpper in adders:
		await adder.on_spotlight()
	g.deal_stocks()
	return g

func _free_game(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

func _stock_sizes(g: Game) -> Array[int]:
	var sizes : Array[int] = []
	for slot : int in g.state.upper_zone.size():
		sizes.append(g.stock_for_slot(slot).size())
	return sizes


# ==============================================================================
# TEST_PLAN 4.1 -- the deal itself: round-robin left to right, earlier slots take the extras.
# ==============================================================================
func run_round_robin_deal_test() -> void:
	behavior_section("23 CARDS ACROSS 5 SLOTS")
	var deck := TestDecks.deck_standard_52().slice(0, 23)
	var g : Game = await _stock_game(deck, 5)
	check(_stock_sizes(g) == ([5, 5, 5, 4, 4] as Array[int]),
			"23 cards across 5 slots deal [5,5,5,4,4] -- the earlier slots take the extras",
			str(_stock_sizes(g)))
	check(g.state.all_stock_cards().size() == 23,
			"every dealt card is in exactly one stock", str(g.state.all_stock_cards().size()))
	check(g.state.validate().is_empty(), "the dealt board validates", str(g.state.validate()))
	_free_game(g)


# ==============================================================================
# TEST_PLAN 4.2 -- the deal carries no RNG of its own: the same order deals the same stocks.
# ==============================================================================
func run_same_order_deals_identically_test() -> void:
	behavior_section("THE SAME ORDER DEALS THE SAME STOCKS")
	var deck := TestDecks.deck_standard_52().slice(0, 23)
	var first : Game = await _stock_game(deck.duplicate(), 5)
	var second : Game = await _stock_game(deck.duplicate(), 5)
	var same := true
	for slot : int in 5:
		var a := first.stock_for_slot(slot)
		var b := second.stock_for_slot(slot)
		if a.size() != b.size():
			same = false
			continue
		for i : int in a.size():
			if a[i].log_str() != b[i].log_str(): same = false
	check(same, "the same shuffled order dealt twice gives identical stocks, card for card",
			"%s vs %s" % [str(_stock_sizes(first)), str(_stock_sizes(second))])
	_free_game(first)
	_free_game(second)


# ==============================================================================
# TEST_PLAN 4.3 -- a quit mid-placement replays off the saved board: ordered stocks, no reshuffle.
# ==============================================================================
func run_replayed_placement_is_identical_test() -> void:
	behavior_section("A REPLAYED PLACEMENT REPRODUCES ITS BOARD")
	var prev_run : RunState = RunManager.run
	var prev_info : RunState = Main.save_info
	backup_real_save(suite_tag())
	Main.save_info = RunManager.new_run(TestDecks.minimal_deck(), [] as Array[CardData])
	var g : Game = await _stock_game(TestDecks.deck_standard_52(), 5)
	var fixture := TestGridFixtures.build_fix_grid_3()
	g.state.grids = fixture.grids
	await g.refill_entrance_if_due()
	g.save_state()
	var pre_placement : GameData = g.save_history[-1]
	var coord := BoardCoord.new(0, 0, 0, 0)
	var held : CardData = g.state.upper_zone[0].datas.back()
	await g.place_card_in_grid(held, coord)
	var expected := TestGridFixtures.board_digest(g.state)

	g.state = g._runtime_state(pre_placement)
	g.save_history = [pre_placement]
	RunManager.run.pending_action = &"on_placement"
	RunManager.run.pending_placement_slot = 0
	RunManager.run.pending_placement_coord = Vector4i(coord.grid, coord.x, coord.y, coord.h)
	await g._replay_pending_action(&"on_placement")
	check(TestGridFixtures.board_digest(g.state) == expected,
			"the replayed placement reproduces the board, its scoring and its refill",
			"replayed:\n%s\n---- wanted:\n%s" % [
			TestGridFixtures.board_digest(g.state), expected])
	_free_game(g)
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_info


# ==============================================================================
# TEST_PLAN 4.7 -- "the deck is empty" is every stock empty, so one drained slot ends nothing.
# ==============================================================================
func run_one_empty_slot_is_not_an_empty_deck_test() -> void:
	behavior_section("ONE DRAINED SLOT IS NOT AN EMPTY DECK")
	var g : Game = await _stock_game(TestDecks.deck_standard_52().slice(0, 23), 5)
	g.stock_for_slot(0).clear()
	check(not g.state.stocks_are_empty(),
			"one slot out of cards does not make the deck empty",
			str(_stock_sizes(g)))
	check(g.draw_card(0) == null and g.draw_card(1) != null,
			"the drained slot draws nothing while its neighbour still draws")
	for slot : int in 5:
		g.stock_for_slot(slot).clear()
	check(g.state.stocks_are_empty(), "every stock empty IS the empty deck")
	_free_game(g)


# ==============================================================================
# TEST_PLAN 4.8 -- a stock is part of the board: on_append finds a card in one, the verifier passes.
# ==============================================================================
func run_walkers_reach_a_stock_card_test() -> void:
	implementation_section("A STOCK IS PART OF THE BOARD")
	var g : Game = await _stock_game(TestDecks.deck_standard_52().slice(0, 23), 5)
	var listener : CardData = g.stock_for_slot(4).back()
	var spy := SpyStockAppend.new()
	listener.with_type(spy)
	g.state.revision += 1
	var appended : Array[CardData] = []
	for i : int in 2:
		appended.append(TestFactories.m_card(i + 1, TestFactories.uc()))
	await g.shuffle_deck(appended)
	check(spy.append_calls == 2,
			"on_append reaches a card sitting in a stock, once per appended card",
			"calls %d" % spy.append_calls)
	check(g.state.all_card_datas().has(listener),
			"the flat card list reaches a stock card")
	check(g.state.validate().is_empty(),
			"the stage verifier passes with cards in the stocks", str(g.state.validate()))
	_free_game(g)


## Records the on_append broadcast its own card receives while sitting in a stock.
class SpyStockAppend extends CardModifierType:
	var append_calls := 0
	func get_str() -> String: return "SpyStockAppend"
	func get_description() -> String: return ""
	func get_frame() -> int: return 0
	func on_append(_deck: Array[CardData], _appended: CardData) -> void:
		append_calls += 1
