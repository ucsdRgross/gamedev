extends TestSuite
# res://Tests/E2E/test_e2e_run.gd
# ==============================================================================
# END-TO-END, HEADLESS: the full player loop through the REAL production paths —
# RunManager.new_run with the shipped starter deck + rules, Game's fresh-show
# bootstrap (the zone adders build the Entrance, the allotment card sizes the grid
# count and its creators build the grids, the deck is dealt & shuffled and the
# opening hand fills the Entrance), placements completing lines that the detector
# scores live, End -> win -> fame, quit mid-show -> resume from disk, and the loss
# path. No view anywhere: this is the whole game with view == null.
#
# ⚠ Placements here come from the DRAW DECK, not from the Entrance, and go through
# `place_card_in_grid` rather than `try_place`. That is not a shortcut chosen for
# convenience: no card answers `on_can_place_stack` for a grid cell yet, so the UI
# placement path does not reach a grid at all (gaps/GAP-008). When it does, the
# placements below become `try_grab`/`try_place` and this note goes.
#
# CATEGORY MAP: all BEHAVIOR — every check is an outcome the player experiences.
#
# Ordering: this suite deliberately runs LAST (it owns CardEnvironment.CURRENT,
# RunManager.run and Main.save_info while it runs) — it waits for every sibling
# suite to finish first.
# Safety: any real run.tres is moved aside (backup_real_save) before the scenarios and
# restored after, so it always runs full and never touches the player's save.
# ==============================================================================

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")

func suite_name() -> String:
	return "E2E RUN"

func _ready() -> void:
	# Waits for every other suite except LEAK CANARY and WALL PAUSE — both wait for THIS suite and
	# run after it (LEAK CANARY needs an idle process for global object counts; WALL PAUSE runs
	# dead last of all because it pauses the tree PERMANENTLY, see its own header).
	await await_siblings_except(["LEAK CANARY", "WALL PAUSE"])
	TestLog.line("============ END-TO-END RUN TEST PASS ============")
	behavior_section("FULL SHOW LOOP, HEADLESS")
	# Always run full: move any real run.tres aside so the scenarios can write/clear freely.
	backup_real_save(suite_tag())
	var real_run: RunState = RunManager.run
	var real_save_info: RunState = Main.save_info
	await run_win_and_resume_scenario()
	await run_loss_scenario()
	await run_headless_and_viewed_parity_scenario()
	# Join any in-flight background save FIRST — otherwise a write queued by the last
	# save_state can land after clear_save and resurrect run.tres.
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())   # put the player's real run.tres back
	RunManager.run = real_run
	Main.save_info = real_save_info
	finish()

## Every card the BOARD is holding: the Entrance slots, the legacy zones, and the grid
## cells. Zone/cell TYPE cards are not counted -- they belong to the zone's own lifetime,
## not to the deck, and the end-of-show sweep leaves them where they are.
func total_zone_cards(g: Game) -> int:
	var n := 0
	for zone: Array[ArrayCardData] in [g.state.upper_zone, g.state.lower_zone]:
		for col in zone:
			n += col.datas.size()
	for grid: GridData in g.state.grids:
		for cell: ArrayCardData in grid.cells:
			n += cell.datas.size()
	return n

## How many cards are sitting in the Entrance right now.
func entrance_cards(g: Game) -> int:
	var n := 0
	for col: ArrayCardData in g.state.upper_zone:
		n += col.datas.size()
	return n

func validate_ok(g: Game, ctx: String) -> void:
	var v := g.state.validate()
	check(v.is_empty(), ctx + " -> board validates", str(v))


# ==============================================================================
# SCENARIO 1: WIN + QUIT/RESUME — start a run, play a show, quit after act 1,
# resume from disk, finish, win, hand the board back to the map.
# ==============================================================================
func run_win_and_resume_scenario() -> void:
	# FROZEN test deck, never Decks/deck.gd: the seeded win below replays against
	# TestDecks.seeded_deck's exact composition (playtest decks change freely).
	var cards := TestDecks.seeded_deck()
	var deck_size := cards.size()
	var rules := TestDecks.standard_rules()
	# ⚠ THE MIRROR HAS TO TRACK THE SHIPPED RULES SET, and nothing else says so. Every scenario
	# below runs the REAL bootstrap against this frozen copy of `Deck.rules1` -- so the day
	# rules1 gains or loses a card and the mirror does not, this whole suite quietly starts
	# testing a game that is not the one being shipped, and every check in it still passes.
	# Compared by skill class name: the shipped builder draws random suits and ranks, and the
	# mirror fixes them on purpose, so only the COMPOSITION is comparable.
	check(TestDecks.rules_skill_names(rules) == TestDecks.rules_skill_names(Deck.new().rules1),
			"the frozen rules mirror still matches the shipped rules1",
			"mirror %s vs shipped %s" % [TestDecks.rules_skill_names(rules),
			TestDecks.rules_skill_names(Deck.new().rules1)])
	var run := RunManager.new_run(cards, rules)
	Main.save_info = run
	check(RunManager.has_save(), "starting a run immediately writes a resumable save")
	run.pending_goal = 1     # the map node's fame requirement for this show
	run.pending_node_id = 2  # a show is in progress on this node

	# --- fresh show bootstrap (Game._ready -> _start_fresh_show) ---
	seed(424242)
	var g := Game.new()
	add_child(g)
	await get_tree().process_frame
	check(g.state.goal == 1, "the show takes its goal from the map node", str(g.state.goal))
	check(g.state.upper_zone.size() > 0 \
			and g.state.upper_zone.size() == g.state.upper_zone_type.size(),
			"the upper zone-adder rules cards build the Entrance on game start",
			"%d slots, %d headers" % [g.state.upper_zone.size(), g.state.upper_zone_type.size()])
	check(g.state.grids.size() >= 1,
			"the allotment card's creators build at least one grid on game start",
			"%d grids" % g.state.grids.size())
	# The opening deal: the Entrance starts full, so the deck is down by exactly what it holds.
	# ⚠ This is also what proves the bootstrap refills AFTER the spotlight sweep that builds
	# the slots -- asked before it, the refill finds nothing to fill and deals silently nothing.
	var opening := entrance_cards(g)
	check(opening > 0, "the opening deal fills the Entrance", "%d cards" % opening)
	check(g.state.draw_deck.size() == deck_size - opening,
			"the rest of the starter deck is in the draw pile",
			"%d vs %d - %d" % [g.state.draw_deck.size(), deck_size, opening])
	check(g.save_history.size() == 1 and run.game_history.size() == 1,
			"the opening board is committed to history and the save")
	validate_ok(g, "fresh show")

	# --- placements: the detector scores a completed line live; no act, no banking moment ---
	check(g.state.live_total() == 0, "an untouched board scores nothing",
			str(g.state.live_total()))
	var placed := await TestGridFixtures.place_row_from_deck(g, 0, 0, 5)
	check(placed.size() == 5, "five cards are placed into row 0", "%d placed" % placed.size())
	check(g.state.live_total() > 0,
			"completing a row pays into the live board total", str(g.state.live_total()))
	check(entrance_cards(g) == opening,
			"the Entrance is still full -- the placements came from the deck, not from it",
			"%d vs %d" % [entrance_cards(g), opening])
	validate_ok(g, "placements")

	# --- quit mid-show: everything needed to resume must already be on disk ---
	var exp_total := g.state.live_total()
	var exp_history := g.save_history.size()
	# A real quit flushes + joins the background saver (RunManager._exit_tree). Do the
	# same here: loading while an async save is mid-write intermittently corrupts the
	# loaded typed arrays (script class identity race).
	RunManager._shutdown_saver()
	RunManager.save_run()
	remove_child(g)
	g.free()
	var loaded := RunManager.load_run()
	Main.save_info = loaded
	check(loaded.pending_node_id == 2,
			"the save remembers which node and act the quit interrupted")

	# --- resume: a new Game rebuilds the exact interrupted show ---
	var g2 := Game.new()
	add_child(g2)
	await get_tree().process_frame
	await get_tree().process_frame  # _resume_after_visuals is deferred
	# A REAL check, not a tautology: the score is derived from the per-grid buckets, so this
	# only holds if every bucket round-tripped through the save and back.
	check(g2.state.live_total() == exp_total, "resume restores the board's score",
			"%d vs %d" % [g2.state.live_total(), exp_total])
	check(g2.state.goal == 1, "resume restores the show's goal")
	check(g2.save_history.size() == exp_history, "resume restores the undo history")
	check(not g2.processing, "a plain mid-show resume hands the board back to the player")
	validate_ok(g2, "resumed show")

	# --- End: the show resolves; the win feeds fame ---
	var resolved: Array = []
	g2.show_resolved.connect(func(won: bool, score: int, goal: int) -> void:
			resolved.append([won, score, goal]))
	var more := await TestGridFixtures.place_row_from_deck(g2, 0, 1, 5)
	check(more.size() == 5 and resolved.is_empty(),
			"a show never resolves on its own -- only End resolves one",
			"%d placed, %d resolutions" % [more.size(), resolved.size()])
	g2.end_show()
	check((resolved.size() == 1 and resolved[0][0] == true) as bool,
			"ending the show resolves it as a win (goal met)", str(resolved))
	check(loaded.fame == 0,
			"the win is NOT banked at the outcome screen (it stays undoable until Continue)",
			"fame %d" % loaded.fame)

	# --- Continue: fame banks, the board sweeps back into the run deck for the map ---
	var ended: Array = []
	g2.game_ended.connect(func() -> void: ended.append(true))
	# Read the score BEFORE Continue: the sweep empties the grids, so the live total it is
	# derived from is gone by the time fame can be compared against it.
	var exp_fame := g2.state.live_total()
	g2.exit_show()
	check(ended.size() == 1, "leaving a won show hands back to the map")
	check(loaded.fame == exp_fame,
			"Continue banks the FULL score as fame",
			"fame %d, score %d" % [loaded.fame, exp_fame])
	check(total_zone_cards(g2) == 0 and g2.state.discard_deck.is_empty(),
			"the board and discard pile are swept clean")
	check(g2.state.draw_deck.size() == deck_size,
			"every card returns to the run deck — none created or lost",
			"%d vs %d" % [g2.state.draw_deck.size(), deck_size])
	check(Main.save_info.game_history.is_empty(),
			"the finished show's history is dropped (Continue won't re-enter it)")
	remove_child(g2)
	g2.free()
	# Both run documents (the original and the reloaded one) drop when scenario 2 starts a


# ==============================================================================
# SCENARIO 2: LOSS — an unreachable goal ends the run.
# ==============================================================================
func run_loss_scenario() -> void:
	# FROZEN test deck for the same reason as the win scenario: replay-stable regardless
	# of what happens to Decks/deck.gd.
	var cards := TestDecks.seeded_deck()
	var rules := TestDecks.standard_rules()
	var run := RunManager.new_run(cards, rules)
	Main.save_info = run
	run.pending_goal = 1000000000
	run.pending_node_id = 1

	seed(31337)
	var g := Game.new()
	add_child(g)
	await get_tree().process_frame

	var resolved: Array = []
	g.show_resolved.connect(func(won: bool, score: int, goal: int) -> void:
			resolved.append([won, score, goal]))
	# End without placing anything: score stays under the goal.
	g.end_show()
	check((resolved.size() == 1 and resolved[0][0] == false) as bool,
			"ending below the goal resolves the show as a loss", str(resolved))
	check(run.fame == 0, "a lost show banks no fame")

	var lost: Array = []
	g.run_lost.connect(func() -> void: lost.append(true))
	g.exit_show()
	check(lost.size() == 1, "leaving a lost show ends the whole run")
	remove_child(g)
	g.free()

# ==============================================================================
# SCENARIO 3: A WHOLE SHOW, HEADLESS AND VIEWED (TP-128, TP-130).
#
# TP-130 is the plain claim: a full show -- deal, place every card the Entrance ever offers,
# End -- runs start to finish without stalling or throwing.
#
# TP-128 is the PHASE GATE, and it is the reason every `if view:` in the scoring path is
# written the way it is. The view is supposed to be a presentation layer over a model that
# does not know it exists; the moment a `view` branch decides anything -- rounds a number,
# skips a step, reorders a cascade -- headless play and real play diverge, and every headless
# test in this suite stops being evidence about the game the player actually plays. The two
# runs below start from the same seed and the same frozen deck, make the same placements in
# the same order, and must end on the same board, cell for cell and bucket for bucket.
# ==============================================================================
func run_headless_and_viewed_parity_scenario() -> void:
	var headless := await play_whole_show(false)
	var viewed := await play_whole_show(true)
	var headless_placements : int = headless["placements"]
	var viewed_placements : int = viewed["placements"]
	var headless_digest : String = headless["digest"]
	var viewed_digest : String = viewed["digest"]
	var headless_resolved : bool = headless["resolved"]
	check(headless_placements == 52,
			"the headless show placed every card in the frozen 52-card deck",
			"%d placements" % headless_placements)
	check(headless_resolved, "the headless show ran to End and resolved")
	check(viewed_placements == headless_placements,
			"the viewed show made the same number of placements",
			"%d vs %d" % [viewed_placements, headless_placements])
	check(viewed_digest == headless_digest,
			"a headless show and a viewed show end on the IDENTICAL board",
			"viewed:\n%s\n---- headless:\n%s" % [viewed_digest, headless_digest])

## Plays one whole show and returns {digest, placements, resolved}. `with_view` decides
## whether a real GameView is attached; everything else is identical, deliberately.
func play_whole_show(with_view: bool) -> Dictionary:
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	# The SAME seed for both runs: add_deck shuffles, so an unseeded second run would deal a
	# different order and the comparison would be meaningless rather than false.
	seed(20260827)
	var view : GameView = null
	var g : Game = null
	if with_view:
		view = GAME_VIEW_SCENE.instantiate()
		add_child(view)
		await get_tree().process_frame
		await get_tree().process_frame
		g = view.game
	else:
		g = Game.new()
		add_child(g)
		await get_tree().process_frame

	var resolved : Array[bool] = [false]
	g.show_resolved.connect(func(_w: bool, _s: int, _go: int) -> void: resolved[0] = true)

	# Place every card the Entrance offers, cell by cell in row-major order and then stacking
	# once the grid is full. A FIXED walk, not a search: the two runs have to make the same
	# choices for their boards to be comparable at all.
	var placements := 0
	while placements < 200:
		var slot := first_occupied_slot(g)
		if slot == -1: break
		var held : CardData = g.state.upper_zone[slot].datas.back()
		var n := placements % 25
		await g.place_card_in_grid(held, BoardCoord.new(0, n % 5, n / 5, 0))
		placements += 1
	g.end_show()
	var out := {
		"digest": TestGridFixtures.board_digest(g.state),
		"placements": placements,
		"resolved": resolved[0],
	}

	if with_view:
		view.queue_free()
		await get_tree().process_frame
	else:
		remove_child(g)
		g.free()
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	return out

## The leftmost Entrance slot holding a card, or -1 when the Entrance is empty.
func first_occupied_slot(g: Game) -> int:
	for col : int in g.state.upper_zone.size():
		if not g.state.upper_zone[col].datas.is_empty(): return col
	return -1

