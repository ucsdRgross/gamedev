extends SolatroTest
# res://Tests/E2E/test_e2e_run.gd
# ==============================================================================
# END-TO-END, HEADLESS: the full player loop through the REAL production paths —
# RunManager.new_run with the shipped starter deck + rules, Game's fresh-show
# bootstrap (zone adders build the board, deck dealt & shuffled), Next cycles
# cascading cards into the performed zone, three Submit acts with real poker
# scoring, win -> fame, quit mid-show -> resume from disk, and the loss path.
# No view anywhere: this is the whole game with view == null.
#
# CATEGORY MAP: all BEHAVIOR — every check is an outcome the player experiences.
#
# Ordering: this suite deliberately runs LAST (it owns CardEnvironment.CURRENT,
# RunManager.run and Main.save_info while it runs) — it waits for every sibling
# suite to finish first.
# Safety: any real run.tres is moved aside (backup_real_save) before the scenarios and
# restored after, so it always runs full and never touches the player's save.
# ==============================================================================

func suite_name() -> String:
	return "E2E RUN"

func _ready() -> void:
	if get_parent():
		for sibling in get_parent().get_children():
			var suite := sibling as SolatroTest
			if suite and suite != self and not suite.finished:
				await suite.suite_finished
	print("============ END-TO-END RUN TEST PASS ============")
	behavior_section("FULL SHOW LOOP, HEADLESS")
	# Always run full: move any real run.tres aside so the scenarios can write/clear freely.
	backup_real_save()
	var real_run: RunState = RunManager.run
	var real_save_info: RunState = Main.save_info
	await run_win_and_resume_scenario()
	await run_loss_scenario()
	# Join any in-flight background save FIRST — otherwise a write queued by the last
	# save_state can land after clear_save and resurrect run.tres.
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save()   # put the player's real run.tres back
	RunManager.run = real_run
	Main.save_info = real_save_info
	finish()

func total_zone_cards(g: Game) -> int:
	var n := 0
	for zone: Array[ArrayCardData] in [g.state.upper_zone, g.state.lower_zone]:
		for col in zone:
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
	var run := RunManager.new_run(cards, TestDecks.standard_rules())
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
			and g.state.upper_zone.size() == g.state.upper_zone_type.size() \
			and g.state.lower_zone.size() > 0 \
			and g.state.lower_zone.size() == g.state.lower_zone_type.size(),
			"zone-adder rules cards build the board columns on game start")
	check(g.state.draw_deck.size() == deck_size,
			"the whole starter deck is dealt into the draw pile",
			"%d vs %d" % [g.state.draw_deck.size(), deck_size])
	check(g.save_history.size() == 1 and run.game_history.size() == 1,
			"the opening board is committed to history and the save")
	validate_ok(g, "fresh show")

	# --- Next cycles: cards enter the upper zone, then cascade to the lower ---
	var deck_before := g.state.draw_deck.size()
	await g.next()
	var drawn := deck_before - g.state.draw_deck.size()
	check(drawn > 0 and total_zone_cards(g) == drawn,
			"first Next deals cards into the input zone", "drawn %d" % drawn)
	validate_ok(g, "first Next")

	await g.next()
	var lower_cards := 0
	for col in g.state.lower_zone:
		lower_cards += col.datas.size()
	check(lower_cards == drawn,
			"second Next drops the first wave into the performed (lower) zone",
			"lower %d, expected %d" % [lower_cards, drawn])
	validate_ok(g, "second Next")

	# --- act 1: Submit scores the performed board and pays row x col ---
	await g.submit()
	check(g.submits_used == 1, "Submit consumes one act")
	check(g.state.total_score > 0, "a performed board pays a positive act score",
			str(g.state.total_score))
	var lower_empty := g.state.lower_zone.all(
			func(c: ArrayCardData) -> bool: return c.datas.is_empty())
	check(lower_empty, "Submit clears the performed board")
	validate_ok(g, "act 1")

	# --- quit mid-show: everything needed to resume must already be on disk ---
	var exp_total := g.state.total_score
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
	check(loaded.pending_node_id == 2 and loaded.game_submits == 1,
			"the save remembers which node and act the quit interrupted")

	# --- resume: a new Game rebuilds the exact interrupted show ---
	var g2 := Game.new()
	add_child(g2)
	await get_tree().process_frame
	await get_tree().process_frame  # _resume_after_visuals is deferred
	check(g2.submits_used == 1, "resume restores the act count")
	check(g2.state.total_score == exp_total, "resume restores the banked score",
			"%d vs %d" % [g2.state.total_score, exp_total])
	check(g2.state.goal == 1, "resume restores the show's goal")
	check(g2.save_history.size() == exp_history, "resume restores the undo history")
	check(not g2.processing, "a plain mid-show resume hands the board back to the player")
	validate_ok(g2, "resumed show")

	# --- acts 2 + 3: the show resolves; the win feeds fame ---
	var resolved: Array = []
	g2.show_resolved.connect(func(won: bool, score: int, goal: int) -> void:
			resolved.append([won, score, goal]))
	await g2.submit()
	check(resolved.is_empty(), "the show does not resolve before the final act")
	await g2.submit()
	check((resolved.size() == 1 and resolved[0][0] == true) as bool,
			"after the final act the show resolves as a win (goal met)", str(resolved))
	check(loaded.fame == 0,
			"the win is NOT banked at the outcome screen (it stays undoable until Continue)",
			"fame %d" % loaded.fame)

	# --- Continue: fame banks, the board sweeps back into the run deck for the map ---
	var ended: Array = []
	g2.game_ended.connect(func() -> void: ended.append(true))
	g2.exit_show()
	check(ended.size() == 1, "leaving a won show hands back to the map")
	check(loaded.fame == g2.state.total_score,
			"Continue banks the FULL score (incl. overscore) as fame",
			"fame %d, score %d" % [loaded.fame, g2.state.total_score])
	check(total_zone_cards(g2) == 0 and g2.state.discard_deck.is_empty(),
			"the board and discard pile are swept clean")
	check(g2.state.draw_deck.size() == deck_size,
			"every card returns to the run deck — none created or lost",
			"%d vs %d" % [g2.state.draw_deck.size(), deck_size])
	check(Main.save_info.game_history.is_empty(),
			"the finished show's history is dropped (Continue won't re-enter it)")
	remove_child(g2)
	g2.free()


# ==============================================================================
# SCENARIO 2: LOSS — an unreachable goal ends the run.
# ==============================================================================
func run_loss_scenario() -> void:
	# FROZEN test deck for the same reason as the win scenario: replay-stable regardless
	# of what happens to Decks/deck.gd.
	var run := RunManager.new_run(TestDecks.seeded_deck(), TestDecks.standard_rules())
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
	# Submit all three acts without performing anything: score stays under the goal.
	await g.submit()
	await g.submit()
	await g.submit()
	check((resolved.size() == 1 and resolved[0][0] == false) as bool,
			"failing the goal after the final act resolves the show as a loss", str(resolved))
	check(run.fame == 0, "a lost show banks no fame")

	var lost: Array = []
	g.run_lost.connect(func() -> void: lost.append(true))
	g.exit_show()
	check(lost.size() == 1, "leaving a lost show ends the whole run")
	remove_child(g)
	g.free()
