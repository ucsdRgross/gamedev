extends TestSuite
# res://Tests/Engine/test_spotlight.gd
# ==============================================================================
# SPOTLIGHT phase 1 (solatro/design/spotlight/PLAN.md §2, steps S1-S10). The mechanical
# spotlight only: the section abstraction, the forced state, the block seam, the activation
# sweep, compact-and-follow, hand re-evaluation, release, and the momentary cue seam.
# NO PIXELS — every Game here runs with view == null, which is also gate G1.7's whole point.
#
# The plan's acceptance gates and where they are asserted:
#   G1.3  save migration ......... test_migration_pre_rename_save()
#   G1.4  buried card lit only during its phase ... test_buried_card_lit_during_its_phase()
#   G1.5  revision unbumped ...... test_forced_spotlight_never_bumps_revision()
#   G1.6  runaway terminates ..... test_self_feeding_chain_ends_at_act_cap()
#   G1.7  mod-fire log ........... test_mod_fire_log_is_deterministic() prints the line the
#                                  windowed and headless runs are diffed on.
#
# CATEGORY MAP: mostly BEHAVIOR — spotlight is a rule the player sees (a buried card's ability
# firing while it scores). The section's shape and the cue signal are IMPLEMENTATION pins.
# ==============================================================================

const MIGRATION_PATH := "user://spotlight_migration_test.tres"

func suite_name() -> String:
	return "SPOTLIGHT"

func _ready() -> void:
	TestLog.line("============ SPOTLIGHT TEST PASS ============")
	implementation_section("S1: THE SCORING SECTION")
	test_section_from_row()
	test_section_from_column()
	test_section_refresh_tracks_the_board()

	behavior_section("S3: THE BLOCK SEAM")
	test_covering_card_blocks_by_default()
	test_kuroko_unhides_the_card_beneath()
	test_revealing_is_a_property_of_the_card_itself()
	test_forced_spotlight_bypasses_the_seam()

	behavior_section("S4: FORCED SPOTLIGHT STATE")
	test_forced_spotlight_lights_a_buried_card()
	test_forced_spotlight_never_bumps_revision()
	await test_undo_clears_the_forced_spotlight()

	behavior_section("S5: THE SECTION SPOTLIGHT PHASE")
	await test_buried_card_lit_during_its_phase()
	await test_already_spotlit_card_fires_nothing()

	behavior_section("S6: IMMEDIATE MUTATION + RE-DERIVE")
	await test_hook_added_card_activates_in_the_same_phase()

	behavior_section("S7: COMPACT AND FOLLOW")
	await test_discard_compacts_and_the_replacement_activates()
	await test_self_feeding_chain_ends_at_act_cap()

	behavior_section("S8: HAND RE-EVALUATION")
	await test_broken_meld_rescores()
	await test_emptied_section_scores_nothing()

	behavior_section("S9: RELEASE + HEADLESS PARITY")
	await test_release_spares_a_naturally_spotlit_card()
	await test_mod_fire_log_is_deterministic()

	implementation_section("S10: THE MOMENTARY CUE SEAM")
	await test_cue_fires_once_per_transition()
	await test_cue_skips_a_skill_with_no_hook()

	behavior_section("G1.3: THE SAVE MIGRATION")
	test_migration_pre_rename_save()
	finish()


# ==============================================================================
# FIXTURES
# ==============================================================================

func rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.spotlit = true
	return c

func play_card(rank: int, suit_id: int) -> CardData:
	var c := TestFactories.m_card(float(rank), suit_id)
	c.stage = CardData.Stage.PLAY
	return c

## A bare Game with the real scorer rules cards and an EMPTY lower board. Tests fill the zone
## themselves so each one owns the exact column shape it is asserting about. Never added to the
## tree (its board logic is tree-safe) and `view` is left null throughout.
func make_game() -> Game:
	var g := Game.new()
	var s := GameData.new()
	s.rules_deck = [
		rules_card(SkillScorerCascadeLower.new()),
		rules_card(SkillEvalPokerBest.new()),
	] as Array[CardData]
	g.state = s
	CardEnvironment.CURRENT = g
	return g

## Give the lower zone `columns` columns, each holding the cards `builder` returns for it.
func fill_lower(g: Game, columns: int, builder: Callable) -> void:
	var types : Array[CardData] = []
	var cols : Array[ArrayCardData] = []
	for c in columns:
		var header := play_card(1, TestFactories.uc())
		header.stage = CardData.Stage.ZONE
		types.append(header)
		var cards : Array[CardData] = builder.call(c)
		cols.append(TestFactories.col(cards))
	g.state.lower_zone_type = types
	g.state.lower_zone = cols
	g.state.revision += 1

func free_game(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

func col_cards(g: Game, c: int) -> Array[CardData]:
	return g.state.lower_zone[c].datas

## The spotlit set of the whole board, as tags/objects, so two derivations can be compared.
func spotlit_set(g: Game) -> Array[CardData]:
	var out : Array[CardData] = []
	for data in CardDataIterator.new(g):
		if data.skill and data.skill.spotlit: out.append(data)
	return out


# ==============================================================================
# S1 — ScoringSection
# ==============================================================================

func test_section_from_row() -> void:
	var g := make_game()
	# ragged on purpose: col 0 is 2 deep, col 1 is 1 deep. Row 1 exists in col 0 only.
	fill_lower(g, 2, func(c: int) -> Array[CardData]:
		if c == 0:
			return [play_card(3, TestFactories.uc()), play_card(4, TestFactories.uc())] \
					as Array[CardData]
		return [play_card(5, TestFactories.uc())] as Array[CardData])
	var row0 := ScoringSection.of_line(g.state.lower_zone, true, 0)
	check(row0.cards.size() == 2 and row0.origin == &"row" and row0.index == 0,
			"a ROW section is the cards at that index across every column", str(row0.cards.size()))
	var row1 := ScoringSection.of_line(g.state.lower_zone, true, 1)
	check(row1.cards.size() == 1 and row1.cards[0] == col_cards(g, 0)[1],
			"a ragged row skips the columns that are not that deep", str(row1.cards.size()))
	free_game(g)

func test_section_from_column() -> void:
	var g := make_game()
	fill_lower(g, 2, func(_c: int) -> Array[CardData]:
		return [play_card(3, TestFactories.uc()), play_card(4, TestFactories.uc()),
				play_card(5, TestFactories.uc())] as Array[CardData])
	var col0 := ScoringSection.of_line(g.state.lower_zone, false, 0)
	check(col0.cards == col_cards(g, 0) and col0.origin == &"col",
			"a COLUMN section is that column's cards, bottom to top", str(col0.cards.size()))
	check(col0.zone == g.state.lower_zone,
			"the section carries its zone as opaque provenance")
	free_game(g)

func test_section_refresh_tracks_the_board() -> void:
	var g := make_game()
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		return [play_card(3, TestFactories.uc()), play_card(4, TestFactories.uc())] \
				as Array[CardData])
	var section := ScoringSection.of_line(g.state.lower_zone, false, 0)
	check(not section.refresh(), "refresh() on an unchanged board reports no change")
	col_cards(g, 0).remove_at(0)
	check(section.refresh() and section.cards.size() == 1,
			"refresh() re-reads the section after the board moved (Q252=b)",
			str(section.cards.size()))
	free_game(g)


# ==============================================================================
# S3 — the block seam
# ==============================================================================

## The DEFAULT is that a covering card hides the talent beneath it — which is today's whole
## coverage rule, now expressed as the general question instead of "am I last".
func test_covering_card_blocks_by_default() -> void:
	var g := make_game()
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		return [play_card(3, TestFactories.uc()), play_card(4, TestFactories.uc())] 				as Array[CardData])
	check(col_cards(g, 0)[1].type.is_spotlit(), "the topmost card is spotlit")
	check(not col_cards(g, 0)[0].type.is_spotlit(),
			"a plain covering card hides the talent underneath it (A8 default = blocks)")
	# A zone header is spotlit exactly when its column is empty — the same rule, for headers.
	check(not g.state.lower_zone_type[0].type.is_spotlit(),
			"a header under a non-empty column is blocked by it")
	g.state.lower_zone[0].datas.clear()
	g.state.revision += 1
	check(g.state.lower_zone_type[0].type.is_spotlit(),
			"...and is spotlit once its column empties")
	free_game(g)

func test_kuroko_unhides_the_card_beneath() -> void:
	var g := make_game()
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var cover := play_card(4, TestFactories.uc())
		cover.with_stamp(SpotlightTestKuroko.new())
		return [play_card(3, TestFactories.uc()), cover] as Array[CardData])
	check(col_cards(g, 0)[0].type.is_spotlit(),
			"a Kuroko-style cover opts out of blocking, so the card beneath stays spotlit")
	# One opting-out modifier is enough for its whole card: the cover's type and suit still
	# block by default and must not out-vote its stamp.
	check(col_cards(g, 0)[1].type.is_spotlit(), "the Kuroko card itself is unaffected")
	free_game(g)

func test_revealing_is_a_property_of_the_card_itself() -> void:
	var g := make_game()
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var bottom := play_card(3, TestFactories.uc())
		bottom.with_stamp(StampRevealing.new())
		return [bottom, play_card(4, TestFactories.uc()),
				play_card(5, TestFactories.uc())] as Array[CardData])
	check(col_cards(g, 0)[0].stamp.is_spotlit(),
			"Revealing keeps its own card spotlit anywhere on the board, however deeply covered")
	free_game(g)

func test_forced_spotlight_bypasses_the_seam() -> void:
	var g := make_game()
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		return [play_card(3, TestFactories.uc()), play_card(4, TestFactories.uc())] 				as Array[CardData])
	var bottom := col_cards(g, 0)[0]
	check(not bottom.type.is_spotlit(), "precondition: blocked by the card above it")
	g.state.forced_spotlight[bottom] = true
	check(bottom.type.is_spotlit(),
			"a FORCED spotlight bypasses the coverage rule entirely (Q6=a)")
	free_game(g)


# ==============================================================================
# S4 — the forced state
# ==============================================================================

func test_forced_spotlight_lights_a_buried_card() -> void:
	var g := make_game()
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		return [play_card(3, TestFactories.uc()), play_card(4, TestFactories.uc()),
				play_card(5, TestFactories.uc())] as Array[CardData])
	var buried := col_cards(g, 0)[0]
	check(not buried.type.is_spotlit(), "precondition: the buried card is not spotlit")
	g.state.forced_spotlight[buried] = true
	check(buried.type.is_spotlit(), "forced_spotlight lights a card two cards deep")
	# A6 sits AFTER the stage check: a stale entry for a card that left the board cannot force it.
	buried.stage = CardData.Stage.DISCARD
	check(not buried.type.is_spotlit(),
			"a stale forced entry cannot light a card that left the board (A6 ordering)")
	free_game(g)

func test_forced_spotlight_never_bumps_revision() -> void:
	var g := make_game()
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		return [play_card(3, TestFactories.uc()), play_card(4, TestFactories.uc())] \
				as Array[CardData])
	var before := g.state.revision
	g.state.forced_spotlight[col_cards(g, 0)[0]] = true
	var _lit := col_cards(g, 0)[0].type.is_spotlit()
	g.state.forced_spotlight.clear()
	check(g.state.revision == before,
			"writing, reading and clearing forced_spotlight never bumps revision (G1.5, Q17=a)",
			"%d -> %d" % [before, g.state.revision])
	free_game(g)

func test_undo_clears_the_forced_spotlight() -> void:
	var g := make_game()
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		return [play_card(3, TestFactories.uc()), play_card(4, TestFactories.uc())] \
				as Array[CardData])
	g.save_state()
	g.state.revision += 1
	g.save_state()
	g.state.forced_spotlight[col_cards(g, 0)[0]] = true
	g.undo()
	check(g.state.forced_spotlight.is_empty(),
			"undo restores a board with NO forced spotlight on it (Q18=a)",
			str(g.state.forced_spotlight.size()))
	free_game(g)


# ==============================================================================
# S5 — the section spotlight phase
# ==============================================================================

## Score column `c` through the REAL cascade: the rules deck's SkillEvalPokerBest gathers the
## column, the real Scoring.PokerHands evaluates it, and IT calls score_line. Nothing here builds
## a Scoring.Result by hand — a stand-in cannot disagree with what it models (project rule 5).
func score_column(g: Game, c: int) -> void:
	await g.run_all_mods(&"on_score_col", g.state.lower_zone, c)

func test_buried_card_lit_during_its_phase() -> void:
	var g := make_game()
	var seen : Array[bool] = []
	var spy := SpotlightTestSkill.make("buried",
			func(s: SpotlightTestSkill) -> void: seen.append(s.is_spotlit()))
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var bottom := play_card(3, TestFactories.uc())
		bottom.with_skill(spy)
		return [bottom, play_card(4, TestFactories.uc())] as Array[CardData])
	check(not spy.is_spotlit(), "precondition: the buried spy is dark")
	await score_column(g, 0)
	check(spy.spotlight_calls == 1 and seen == ([true] as Array[bool]),
			"a buried card in the section is spotlit DURING its phase and its hook fires once",
			"calls=%d seen=%s" % [spy.spotlight_calls, str(seen)])
	await g._release_spotlight()
	check(not spy.is_spotlit() and not spy.spotlit and spy.unspotlight_calls == 1,
			"and is dark again after the release (G1.4)",
			"unspotlight_calls=%d" % spy.unspotlight_calls)
	free_game(g)

func test_already_spotlit_card_fires_nothing() -> void:
	var g := make_game()
	var spy := SpotlightTestSkill.make("topmost")
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var top := play_card(4, TestFactories.uc())
		top.with_skill(spy)
		return [play_card(3, TestFactories.uc()), top] as Array[CardData])
	await g.skill_spotlight_check()
	check(spy.spotlit and spy.spotlight_calls == 1,
			"precondition: the topmost card is naturally spotlit and announced once")
	await score_column(g, 0)
	check(spy.spotlight_calls == 1,
			"force-spotlighting an ALREADY spotlit card fires nothing (Q13, Q15)",
			"calls=%d" % spy.spotlight_calls)
	free_game(g)


# ==============================================================================
# S6 — immediate mutation + re-derive
# ==============================================================================

func test_hook_added_card_activates_in_the_same_phase() -> void:
	var g := make_game()
	var arrival := SpotlightTestSkill.make("arrival")
	# The buried spy's hook drops a NEW card on top of its own column, which joins the section
	# (Q25=b immediate mutation) and must activate before the phase ends (Q252=b re-derive).
	var opener := SpotlightTestSkill.make("opener", func(s: SpotlightTestSkill) -> void:
		var extra := play_card(9, TestFactories.uc())
		extra.with_skill(arrival)
		s.game.state.lower_zone[0].datas.append(extra)
		s.game.state.revision += 1)
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var bottom := play_card(3, TestFactories.uc())
		bottom.with_skill(opener)
		return [bottom, play_card(4, TestFactories.uc())] as Array[CardData])
	await score_column(g, 0)
	check(arrival.spotlight_calls == 1 and arrival.spotlit,
			"a card a hook added to the section activates in the SAME phase (S6)",
			"calls=%d" % arrival.spotlight_calls)
	free_game(g)


# ==============================================================================
# S7 — compact and follow
# ==============================================================================

func test_discard_compacts_and_the_replacement_activates() -> void:
	var g := make_game()
	var replacement := SpotlightTestSkill.make("replacement")
	var doomed_ref : Array[CardData] = []
	# The BOTTOM card's hook discards the card in the middle of its own column. The column is a
	# plain Array, so erasing index 1 slides index 2 down into the vacated slot for free
	# (Q198=a); that card joins the section and must go through the whole activation (Q204=a).
	var trigger := SpotlightTestSkill.make("trigger", func(s: SpotlightTestSkill) -> void:
		if doomed_ref.is_empty(): return
		var doomed : CardData = doomed_ref.pop_back()
		await s.game.discard_data(doomed))
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var bottom := play_card(3, TestFactories.uc())
		bottom.with_skill(trigger)
		var middle := play_card(4, TestFactories.uc())
		var top := play_card(5, TestFactories.uc())
		top.with_skill(replacement)
		return [bottom, middle, top] as Array[CardData])
	doomed_ref.append(col_cards(g, 0)[1])
	var slot_owner_before := col_cards(g, 0)[1]
	await score_column(g, 0)
	check(col_cards(g, 0).size() == 2 and col_cards(g, 0)[1] != slot_owner_before,
			"the column compacted: the covering card took the discarded card's slot (Q198=a)",
			"depth=%d" % col_cards(g, 0).size())
	check(col_cards(g, 0)[1].skill == replacement and replacement.spotlit
			and replacement.spotlight_calls == 1,
			"the replacement is in the lit slot, spotlit, and activated (S7 done-when)",
			"calls=%d" % replacement.spotlight_calls)
	free_game(g)

## G1.6 — the §1.5 loop is UNBOUNDED by design (Q201=b): only the act-level runaway guard stops
## it. The spy carries its own emergency brake, so if the cap ever fails to trip this test FAILS
## instead of hanging — that brake is the bounded watchdog the gate asks for.
func test_self_feeding_chain_ends_at_act_cap() -> void:
	const WATCHDOG := 40
	var g := make_game()
	var generations : Array[int] = [0]
	var respawn : Callable = func(s: SpotlightTestSkill) -> void:
		generations[0] += 1
		if generations[0] >= WATCHDOG: return      # the brake: never spin past the watchdog
		var heir := play_card(6, TestFactories.uc())
		heir.with_skill(SpotlightTestSkill.make("gen%d" % generations[0], s.behaviour))
		s.game.state.lower_zone[0].datas.append(heir)
		await s.game.discard_data(s.data)
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var seed_card := play_card(5, TestFactories.uc())
		seed_card.with_skill(SpotlightTestSkill.make("gen0", respawn))
		return [seed_card] as Array[CardData])
	# Park act_calls just under the cap instead of editing the SHARED settings resource, which
	# concurrent suites are also reading. Same trip, no cross-suite damage.
	g._begin_act()
	g.act_calls = SettingsManager.settings.act_event_cap - 4
	await score_column(g, 0)
	check(g.act_overrun, "the self-feeding chain tripped act_event_cap",
			"act_calls=%d generations=%d" % [g.act_calls, generations[0]])
	check(generations[0] < WATCHDOG,
			"...and it was the CAP that stopped it, not the test's own watchdog (G1.6)",
			"generations=%d of %d" % [generations[0], WATCHDOG])
	free_game(g)


# ==============================================================================
# S8 — hand re-evaluation
# ==============================================================================

func test_broken_meld_rescores() -> void:
	var g := make_game()
	# A pair of 7s plus a 2. The bottom card's hook discards one 7, so by the time the hand is
	# re-evaluated (Q22=b, Q23=a) there is no pair left and the line banks a high card instead.
	var doomed_ref : Array[CardData] = []
	var breaker := SpotlightTestSkill.make("breaker", func(s: SpotlightTestSkill) -> void:
		if doomed_ref.is_empty(): return
		var doomed : CardData = doomed_ref.pop_back()
		await s.game.discard_data(doomed))
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var bottom := play_card(2, TestFactories.uc())
		bottom.with_skill(breaker)
		return [bottom, play_card(7, TestFactories.uc()),
				play_card(7, TestFactories.uc())] as Array[CardData])
	doomed_ref.append(col_cards(g, 0)[2])
	var pair_score : int = (await Scoring.PokerHands.score(col_cards(g, 0)))[0].score
	await score_column(g, 0)
	check(g.state.col_total > 0 and g.state.col_total < pair_score,
			"a hook that breaks the meld banks the RE-EVALUATED, smaller hand (S8)",
			"banked=%d, original pair=%d" % [g.state.col_total, pair_score])
	free_game(g)

func test_emptied_section_scores_nothing() -> void:
	var g := make_game()
	var doomed_ref : Array[CardData] = []
	var eraser := SpotlightTestSkill.make("eraser", func(s: SpotlightTestSkill) -> void:
		while not doomed_ref.is_empty():
			var doomed : CardData = doomed_ref.pop_back()
			await s.game.discard_data(doomed))
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var bottom := play_card(2, TestFactories.uc())
		bottom.with_skill(eraser)
		return [bottom, play_card(7, TestFactories.uc())] as Array[CardData])
	doomed_ref.append_array(col_cards(g, 0))
	check(g.state.col_total == 0, "precondition: nothing banked yet")
	await score_column(g, 0)
	check(g.state.col_total == 0,
			"a section emptied by its own effects scores NOTHING — there is no floor (Q244=a)",
			"col_total=%d" % g.state.col_total)
	free_game(g)


# ==============================================================================
# S9 — release and headless parity
# ==============================================================================

func test_release_spares_a_naturally_spotlit_card() -> void:
	var g := make_game()
	var top_spy := SpotlightTestSkill.make("top")
	var buried_spy := SpotlightTestSkill.make("buried")
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var bottom := play_card(3, TestFactories.uc())
		bottom.with_skill(buried_spy)
		var top := play_card(4, TestFactories.uc())
		top.with_skill(top_spy)
		return [bottom, top] as Array[CardData])
	await score_column(g, 0)
	await g._release_spotlight()
	check(top_spy.spotlit and top_spy.unspotlight_calls == 0,
			"release does NOT unspotlight a card that is still naturally spotlit (Q14=a)",
			"unspotlight_calls=%d" % top_spy.unspotlight_calls)
	check(not buried_spy.spotlit and buried_spy.unspotlight_calls == 1,
			"...and DOES release the buried one, exactly once",
			"unspotlight_calls=%d" % buried_spy.unspotlight_calls)
	check(g.state.forced_spotlight.is_empty(), "the forced set is empty after the act")
	free_game(g)

## G1.7 — the mechanical spotlight must fire identically with no view and no waits (Q19=a).
## Nothing in the phase-1 path touches `view`, so this prints a deterministic fire log for a
## fixed board; the WINDOWED and HEADLESS runs of the suite are diffed on this line.
func test_mod_fire_log_is_deterministic() -> void:
	SpotlightTestSkill.reset_statics()
	var g := make_game()
	fill_lower(g, 2, func(c: int) -> Array[CardData]:
		var bottom := play_card(3 + c, TestFactories.uc())
		bottom.with_skill(SpotlightTestSkill.make("c%d.bottom" % c))
		var top := play_card(5 + c, TestFactories.uc())
		top.with_skill(SpotlightTestSkill.make("c%d.top" % c))
		return [bottom, top] as Array[CardData])
	await g.run_all_mods(&"on_run_scorer")
	await g._release_spotlight()
	var line := "[G1.7 mod-fire] " + ",".join(SpotlightTestSkill.fire_log)
	TestLog.line(line)
	# Four cards, four sections (rows 0-1, then cols 0-1). The first sweep announces all four —
	# row 0 FORCES the two bottoms and the two tops are naturally spotlit already. Row 1 then
	# forces the tops (no transition, Q15=a) and RELEASES the bottoms: the forced spotlight
	# TRAVELS, so its membership is always the section being scored (Q16=c, design D20). The
	# column pass re-forces each bottom and it announces a second time. That second announcement
	# is the observable consequence of the set travelling rather than accumulating — pinned
	# here on purpose, because it is exactly what would go quiet if it ever accumulated.
	check(SpotlightTestSkill.fire_log == (["c0.bottom", "c1.bottom", "c0.top", "c1.top",
			"c0.bottom", "c1.bottom"] as Array[String]),
			"a full headless cascade announces the board, then re-announces each released card "
			+ "when its column section reaches it", line)
	check(g.view == null, "the whole phase ran with view == null (Q19=a)")
	free_game(g)


# ==============================================================================
# S10 — the momentary cue seam
# ==============================================================================

func test_cue_fires_once_per_transition() -> void:
	var g := make_game()
	var cues : Array[Array] = []
	g.spotlight_cued.connect(func(cards: Array[CardData]) -> void: cues.append(cards))
	var spy := SpotlightTestSkill.make("cued")
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var only := play_card(3, TestFactories.uc())
		only.with_skill(spy)
		return [only] as Array[CardData])
	await g.skill_spotlight_check()
	var first_cue : Array = cues[0] if cues else []
	var cued_card : CardData = first_cue[0] if first_cue.size() == 1 else null
	check(cues.size() == 1 and cued_card == col_cards(g, 0)[0],
			"a card entering the spotlight emits exactly one cue carrying it (T1-T5)",
			"cues=%d" % cues.size())
	await g.skill_spotlight_check()
	check(cues.size() == 1,
			"a card that was ALREADY spotlit is not re-cued — which is also why loading a save "
			+ "emits zero (Q248=b, no suppression code)",
			"cues=%d" % cues.size())
	free_game(g)

func test_cue_skips_a_skill_with_no_hook() -> void:
	var g := make_game()
	var cues : Array[Array] = []
	g.spotlight_cued.connect(func(cards: Array[CardData]) -> void: cues.append(cards))
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var only := play_card(3, TestFactories.uc())
		only.with_skill(SkillExtraPoint.new())   # a real skill with no on_spotlight
		return [only] as Array[CardData])
	await g.skill_spotlight_check()
	check(col_cards(g, 0)[0].skill.spotlit and cues.is_empty(),
			"a skill with nothing to announce is spotlit but never cued (Q246=a)",
			"cues=%d" % cues.size())
	free_game(g)


# ==============================================================================
# G1.3 — the save migration
# ==============================================================================

## A `run.tres` written BEFORE the rename carries `active = true`, a key nothing reads now. It
## must load with the same spotlit set a fresh derive gives, and fire NO `on_spotlight` doing it
## — otherwise every existing save comes up with a board-wide re-activation storm.
func test_migration_pre_rename_save() -> void:
	var g := make_game()
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		var bottom := play_card(3, TestFactories.uc())
		bottom.with_skill(SpotlightTestSkill.make("saved.buried"))
		var top := play_card(4, TestFactories.uc())
		top.with_skill(SpotlightTestSkill.make("saved.top"))
		return [bottom, top] as Array[CardData])
	for data in CardDataIterator.new(g):
		if data.skill: data.skill.spotlit = data.skill.is_spotlit()
	var expected : Array[String] = []
	for data in spotlit_set(g): expected.append(str(data.skill.get_str()))
	expected.sort()

	var saved := g.state.to_saveable()
	var err := ResourceSaver.save(saved, MIGRATION_PATH)
	check_impl(err == OK, "the migration fixture wrote to disk", "err=%d" % err)
	if err != OK:
		free_game(g)
		return
	# Rewrite it as a PRE-rename save: that is exactly the one-word difference.
	var text := FileAccess.get_file_as_string(MIGRATION_PATH)
	var had_key := "spotlit = " in text
	var f := FileAccess.open(MIGRATION_PATH, FileAccess.WRITE)
	f.store_string(text.replace("spotlit = ", "active = "))
	f.close()
	check_impl(had_key, "the saved fixture really carried the renamed key")

	free_game(g)
	var loaded : GameData = ResourceLoader.load(MIGRATION_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var g2 := make_game()
	g2.state = loaded
	g2.state.restore_runtime()
	SpotlightTestSkill.reset_statics()
	for data in CardDataIterator.new(g2):
		if data.skill:
			check_impl(not data.skill.spotlit,
					"a pre-rename save loads with the flag absent and false (%s)"
							% data.skill.get_str())
	# THE migration: Game._resume_show's resync line, which fires no hooks by construction.
	for data in CardDataIterator.new(g2):
		if data.skill: data.skill.spotlit = data.skill.is_spotlit()
	var got : Array[String] = []
	for data in spotlit_set(g2): got.append(str(data.skill.get_str()))
	got.sort()
	check(got == expected,
			"the old save comes up with the SAME spotlit set a fresh check derives (G1.3)",
			"%s vs %s" % [str(got), str(expected)])
	check(SpotlightTestSkill.total_spotlight_calls == 0,
			"...and fired NO on_spotlight during the load (G1.3)",
			"calls=%d" % SpotlightTestSkill.total_spotlight_calls)
	free_game(g2)
	if FileAccess.file_exists(MIGRATION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MIGRATION_PATH))
