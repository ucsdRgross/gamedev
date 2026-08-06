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
	await test_the_section_signal_carries_plain_cards()
	await test_each_section_reveals_then_ends_its_reveal()
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
	behavior_section("S14: THE ORIGIN ALLOCATOR")
	test_origins_spread_and_never_share_a_y()
	test_origins_take_the_nearest_free()
	test_origins_assign_sorted_pairs_never_cross()
	test_a_shrinking_section_keeps_the_NEAREST_lights()
	test_origins_subdivide_when_exhausted()
	test_origins_assign_subdivides_for_a_larger_section()
	test_origins_respread_only_above_the_viewport()
	test_a_beam_never_points_upward()

	finish()


# ==============================================================================
# FIXTURES
# ==============================================================================

func rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.spotlit = true
	return c

## ⚠ The `TypePaper` is LOAD-BEARING, not decoration: `is_spotlit()` lives on `CardModifier`, so the
## S3/S4 tests ask a card whether it is lit by going through one of its modifiers, and
## `TestFactories.m_card` builds a card with no type at all. Without this, `card.type.is_spotlit()`
## is a call on `Nil` — a RUNTIME error that aborts the test function silently, leaving the suite
## banner saying PASSED with five tests' worth of checks simply never run. Every real card has a
## type (`Decks/deck.gd:36`), so this makes the fixture match the game rather than working around it.
func play_card(rank: int, suit_id: int) -> CardData:
	var c := TestFactories.m_card(float(rank), suit_id)
	c.with_type(TypePaper.new())
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

## ⚠ **THE GAP-005 REGRESSION GUARD, AND IT IS THE ONE TEST PHASE 2 DID NOT HAVE.** The beam lights
## the SECTION BEING SCORED, whose cards are ordinary numerals with no skill at all — so this scores
## a column of entirely PLAIN cards and asserts the signal carries every one of them.
##
## The bug this exists for: S14 drew the beam from `spotlight_cued`, which `Q246`=(a) filters to
## skills implementing `on_spotlight`. Exactly one non-test skill in the shipped game does, so the
## light set was permanently empty and no beam ever appeared in the running game — invisibly, because
## every other spotlight test supplies a fixture skill that DOES implement the hook. **A test whose
## cards all have skills cannot see this failure. That is why these have none.**
func test_the_section_signal_carries_plain_cards() -> void:
	var g := make_game()
	var seen : Array[Array] = []
	g.spotlight_section_changed.connect(func(cards: Array[CardData]) -> void: seen.append(cards))
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		return [play_card(3, TestFactories.uc()), play_card(4, TestFactories.uc()),
				play_card(5, TestFactories.uc())] as Array[CardData])
	var plain := col_cards(g, 0)
	for data : CardData in plain:
		check(data.skill == null, "precondition: this section's cards carry NO skill at all")
	await score_column(g, 0)
	check(not seen.is_empty(), "scoring a section of plain cards EMITS the beam's membership",
			"emits=%d" % seen.size())
	var first : Array[CardData] = seen[0] as Array[CardData]
	check(first.size() == plain.size(),
			"...carrying every card in the section, unfiltered (GAP-005)",
			"%d of %d" % [first.size(), plain.size()])
	# ⚠ A duplicate, not the section's live array: `refresh()` rebuilds `section.cards` in place, so
	# a receiver holding the original would watch it mutate mid-frame.
	check(not is_same(first, plain),
			"...as a COPY, so a receiver cannot watch the section mutate under it")
	seen.clear()
	await g._release_spotlight()
	check(seen.size() == 1 and (seen[0] as Array[CardData]).is_empty(),
			"and the release emits an EMPTY set, which is the whole retirement (QR2=d)",
			"emits=%d" % seen.size())
	free_game(g)

## ⚠ **GAP-006: THE SHOW PULSES PER SECTION, AND NOTHING ASSERTED THAT BEFORE.** Owner, 2026-08-04:
## *"spotlight + dim occurs as cards of section get revealed, with both spotlight and dim effect
## fading away as scoring starts to happen. When next section is revealed, spotlight and dim effect
## are visible again, moving to new location, then fade away again."*
##
## The measured failure this pins: the dim rose ONCE and fell ONCE across EIGHT scored sections,
## because `QR2`=(d) ties it to "are there beams" and `Q16`=(c) never empties the light set between
## sections — so it could not fall mid-act at all. **Every piece was individually right; the
## composition was never checked, and no test looked at the pairing.**
##
## Asserted at the SIGNAL seam rather than on pixels: one `reveal_ended` per scored section, each
## after that section's `section_changed`. Headless, no light layer needed.
func test_each_section_reveals_then_ends_its_reveal() -> void:
	var g := make_game()
	var order : Array[String] = []
	g.spotlight_section_changed.connect(func(cards: Array[CardData]) -> void:
		order.append("section:%d" % cards.size()))
	g.spotlight_reveal_ended.connect(func() -> void: order.append("reveal_ended"))
	fill_lower(g, 1, func(_c: int) -> Array[CardData]:
		return [play_card(3, TestFactories.uc()), play_card(4, TestFactories.uc()),
				play_card(5, TestFactories.uc())] as Array[CardData])
	await score_column(g, 0)
	check(order.has("reveal_ended"),
			"a scored section ENDS its reveal, so the show can fade before scoring (GAP-006)",
			str(order))
	# The ordering is the substance: the fade must follow the reveal it belongs to, never precede it.
	var first_section := order.find("section:3")
	var first_end := order.find("reveal_ended")
	check(first_section >= 0 and first_end > first_section,
			"...and it ends AFTER the section was revealed, not before",
			"section at %d, reveal_ended at %d" % [first_section, first_end])
	# ⚠ EXACTLY ONE per scored section — a reveal that ended twice would fade a show that was already
	# down, and one that never ended is the bug this test exists for.
	var ends := 0
	for e : String in order:
		if e == "reveal_ended": ends += 1
	check(ends == 1, "exactly one reveal_ended for one scored section", "%d" % ends)
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

# ------------------------------------------------------------------ S14: THE ORIGIN ALLOCATOR
# Chart I. None of these are things an eye can check — "no two share a y" and "a beam never points
# upward" are assertions over every pair, not a look at one frame — which is why the allocator is a
# plain RefCounted with no node, no material and no frame.

## I2 + I3: `k0` is the section size with a floor of 4 (`Q109`=a), the spread is even in x, and
## ⚠ **NO TWO ORIGINS SHARE A Y** (`Q113`=d, the owner: *"no beam origins should have identical y
## level even if target cards have identical y level on same row"*). The scatter exists for that one
## reason, so the test is over every PAIR rather than a spot check.
func test_origins_spread_and_never_share_a_y() -> void:
	var o := SpotlightOrigins.new()
	o.begin(2, 1280.0, 100.0)
	check(o.count() == SpotlightOrigins.MIN_ORIGINS,
			"a section smaller than the floor still gets MIN_ORIGINS lamps (Q109=a)", str(o.count()))
	o.begin(6, 1280.0, 100.0)
	check(o.count() == 6, "and a bigger section gets one lamp each", str(o.count()))
	var ys : Array[float] = []
	var xs : Array[float] = []
	for i : int in o.count():
		ys.append(o.origin_of(i).y)
		xs.append(o.origin_of(i).x)
	var shared := false
	for a : int in ys.size():
		for b : int in range(a + 1, ys.size()):
			if is_equal_approx(ys[a], ys[b]): shared = true
	check(not shared, "NO TWO ORIGINS SHARE A Y (Q113=d)", str(ys))
	# Even in x: the gaps between consecutive lamps are all the same.
	xs.sort()
	var gap := xs[1] - xs[0]
	var even := true
	for i : int in range(1, xs.size() - 1):
		if not is_equal_approx(xs[i + 1] - xs[i], gap): even = false
	check(even, "and the spread is even across the band", str(xs))
	# Every lamp is ABOVE the board top it was given, by the rise.
	var all_above := true
	for i : int in o.count():
		if o.origin_of(i).y >= 100.0: all_above = false
	check(all_above, "and every lamp sits above the board it lights (Q114)")

## I7 / `Q111`=(a): the NEAREST free origin, which is what keeps beams mostly vertical and mostly
## non-crossing without a rule about either.
func test_origins_take_the_nearest_free() -> void:
	var o := SpotlightOrigins.new()
	o.begin(4, 1280.0, 100.0)
	var left := o.take(Vector2(10.0, 400.0))
	var right := o.take(Vector2(1270.0, 400.0))
	check(o.origin_of(left).x < o.origin_of(right).x,
			"a target on the left takes a lamp left of the one a right-hand target takes",
			"%f vs %f" % [o.origin_of(left).x, o.origin_of(right).x])
	# Taken means taken: the same target twice gets two different lamps.
	var again := o.take(Vector2(10.0, 400.0))
	check(again != left, "and an origin already in use is not handed out twice", str(again))
	o.release(left)
	check(o.take(Vector2(10.0, 400.0)) == left, "releasing puts it back in the pool")

## **THE OWNER'S BAND RULE (GAP-008): the top bar is divided by ROW, widening outward.**
##
## > *"middle of top gets first `-1-`, 2nd row gets lamp area surrounding first row `-212-`, and so on
## > with `-32123-`, with each lamp within a row section choosing its closest."*
##
## ⚠ **THE COLUMN IS THE CASE THAT MATTERS AND THE ONE "NEAREST" GOT WRONG.** Every card in a column
## shares one x, so `Q111`=(a)'s "nearest free origin" is a four-way tie and the greedy order leaves
## the FARTHEST lamp for the last card, whose beam then crosses all the others — the owner saw exactly
## that (*"seeing beams cross over for no good reason in scenario s4 column section"*). Asserted on a
## column, because a ROW passes under either rule, which is why this survived every row-shaped test.
func test_origins_assign_sorted_pairs_never_cross() -> void:
	var o := SpotlightOrigins.new()
	o.begin(4, 1280.0, 100.0)
	# A COLUMN: four targets, one x, descending the screen.
	var column : Array[Vector2] = [Vector2(640.0, 200.0), Vector2(640.0, 260.0),
			Vector2(640.0, 320.0), Vector2(640.0, 380.0)]
	var idx := o.assign(column)
	check(idx.size() == 4, "every card in the section is assigned a lamp", str(idx.size()))
	var used : Dictionary[int, bool] = {}
	for i : int in idx: used[i] = true
	check(used.size() == 4, "and no lamp is handed out twice", str(used.size()))
	# ⚠ NO CAP AND NO SUBDIVISION: `begin(4, …)` builds exactly four, so any index past 3 would mean
	# the allocator grew when it did not need to — the owner's *"last spotlight is not part of initial
	# even distribution"*.
	var max_idx := 0
	for i : int in idx: max_idx = maxi(max_idx, i)
	check(max_idx <= 3,
			"a 4-card column uses the 4 evenly-spread initial origins — no subdivision, no outlier",
			"highest origin index %d of 4" % max_idx)

	# **THE BAND PROPERTY: a DEEPER card's lamp is never CLOSER to the column than a shallower one's.**
	# That is what makes the fan crossing-free — a lamp further out lands lower, so two beams on one
	# side converge without meeting, and two on opposite sides can only meet at the column's x, which
	# they reach at different heights.
	var last_dist := -1.0
	var monotone := true
	for n : int in column.size():
		var d := absf(o.origin_of(idx[n]).x - column[n].x)
		if d + 0.001 < last_dist: monotone = false
		last_dist = maxf(last_dist, d)
	check(monotone,
			"GAP-008: lamp distance from the column grows with DEPTH — the fan",
			"a deeper card took a lamp closer in than a shallower one")
	# ⚠ The topmost card's beam points STRAIGHT DOWN — the owner's *"beam right above it would point
	# straight down to topmost card"*. It is the nearest lamp in the column's own section.
	var top_dist := absf(o.origin_of(idx[0]).x - column[0].x)
	var any_nearer := false
	for n : int in column.size():
		if absf(o.origin_of(idx[n]).x - column[n].x) + 0.001 < top_dist: any_nearer = true
	check(not any_nearer,
			"…and the TOPMOST card takes the lamp nearest its column — it points straight down")

	# AND NO CROSSINGS, stated geometrically: for every pair of beams, they do not intersect between
	# the bar and their targets.
	var crossings := 0
	for a : int in column.size():
		for b : int in column.size():
			if a >= b: continue
			if _beams_cross(o.origin_of(idx[a]), column[a], o.origin_of(idx[b]), column[b]):
				crossings += 1
	check(crossings == 0, "…so no two beams in a column cross", "%d crossing pair(s)" % crossings)

	# ⚠ **THE INTERLEAVED SET — THE CASE THAT CAUGHT THE FIRST IMPLEMENTATION.** Six cards alternating
	# depth 0 / depth 1 across six columns. Partitioning the bar by ROW pulls the shallow cards to the
	# middle and pushes the deep ones to the edges, which INVERTS the x order: measured, `col0 -> lamp2`
	# while `col1 -> lamp0`, three crossings, and the owner saw it as *"beam separation looks wrong"*.
	# Partitioning by COLUMN cannot do that, because the sections are disjoint and in x order.
	var z := SpotlightOrigins.new()
	z.begin(6, 1280.0, 100.0)
	var zig : Array[Vector2] = [Vector2(100.0, 200.0), Vector2(240.0, 260.0),
			Vector2(380.0, 200.0), Vector2(520.0, 260.0),
			Vector2(660.0, 200.0), Vector2(800.0, 260.0)]
	var zidx := z.assign(zig)
	var zig_cross := 0
	for a : int in zig.size():
		for b : int in zig.size():
			if a >= b: continue
			if _beams_cross(z.origin_of(zidx[a]), zig[a], z.origin_of(zidx[b]), zig[b]):
				zig_cross += 1
	check(zig_cross == 0,
			"an INTERLEAVED set (alternating depths across six columns) has no crossings either",
			"%d crossing pair(s) — the bar is being partitioned by ROW, not by COLUMN" % zig_cross)
	# And the lamps run left to right with the columns, which is what "no crossing" means here.
	var ordered := true
	for a : int in zig.size() - 1:
		if z.origin_of(zidx[a]).x >= z.origin_of(zidx[a + 1]).x: ordered = false
	check(ordered, "…because each column's section of the bar is left of the next column's")

	# A ROW must still spread across the FULL width — every card is its own column, so the sections
	# run left to right. This is the case the fan must not regress.
	var w := SpotlightOrigins.new()
	w.begin(4, 1280.0, 100.0)
	var row : Array[Vector2] = [Vector2(1000.0, 300.0), Vector2(200.0, 300.0),
			Vector2(600.0, 300.0), Vector2(80.0, 300.0)]
	var widx := w.assign(row)
	var row_cross := 0
	for a : int in row.size():
		for b : int in row.size():
			if a >= b: continue
			if _beams_cross(w.origin_of(widx[a]), row[a], w.origin_of(widx[b]), row[b]):
				row_cross += 1
	check(row_cross == 0, "a ROW still pairs across the whole bar with no crossings",
			"%d crossing pair(s)" % row_cross)
	# The leftmost card takes the leftmost lamp — the even spread a row has always had.
	check(w.origin_of(widx[3]).x < w.origin_of(widx[0]).x,
			"and the leftmost card's lamp is left of the rightmost card's",
			"%f vs %f" % [w.origin_of(widx[3]).x, w.origin_of(widx[0]).x])

## Do two beams cross between the lamp bar and their targets? Standard segment intersection —
## written out rather than eyeballed from indices, because the CLAIM is geometric.
func _beams_cross(o1: Vector2, t1: Vector2, o2: Vector2, t2: Vector2) -> bool:
	var d := (t1 - o1).cross(t2 - o2)
	if is_zero_approx(d): return false
	var s : float = (o2 - o1).cross(t2 - o2) / d
	var u : float = (o2 - o1).cross(t1 - o1) / d
	# Strictly inside both segments: a shared endpoint is a convergence, not a crossing.
	return s > 0.001 and s < 0.999 and u > 0.001 and u < 0.999

## I8 / I9: the pool empties, midpoints become candidates, and the rig GROWS rather than refusing.
## ⚠ `Q107` refuses a cap — *"No cap. soft cap at how many cards can fit on screen"* — so running out
## of origins may never be a reason a card goes unlit.
func test_origins_subdivide_when_exhausted() -> void:
	var o := SpotlightOrigins.new()
	o.begin(4, 1280.0, 100.0)
	var handed : Array[int] = []
	for i : int in 12:
		var idx := o.take(Vector2(float(i) * 100.0, 400.0))
		check(idx >= 0, "request %d is satisfied — the rig subdivides rather than refusing" % i)
		handed.append(idx)
	check(o.count() > 4, "the rig grew past its initial four", str(o.count()))
	var dup := false
	for a : int in handed.size():
		for b : int in range(a + 1, handed.size()):
			if handed[a] == handed[b]: dup = true
	check(not dup, "and no lamp was handed out twice across the subdivision")

## The GROWING section (chart E4, preset S8's 3 -> 5): `assign()` finds fewer free lamps than
## targets and must subdivide — `take()` above exercises the other branch, and this one had no test
## although it is the branch the GAME hits when a later section is larger than `begin()` was sized
## for. Also pins the `advance()` regression: it used to re-spread by INDEX order, and after a
## subdivision index order no longer matches x order, so every taken lamp teleported horizontally.
func test_origins_assign_subdivides_for_a_larger_section() -> void:
	var o := SpotlightOrigins.new()
	o.begin(3, 1280.0, 100.0)   # lays out maxi(3, MIN_ORIGINS) = 4 lamps
	var first_targets : Array[Vector2] = [
		Vector2(200.0, 400.0), Vector2(400.0, 400.0), Vector2(600.0, 400.0)]
	var first := o.assign(first_targets)
	for idx : int in first:
		check(idx >= 0, "the first section's three cards all get lamps")
	# Two fresh targets with only one lamp free — assign() must grow the rig.
	var second_targets : Array[Vector2] = [Vector2(800.0, 400.0), Vector2(1000.0, 400.0)]
	var second := o.assign(second_targets)
	check(o.count() > 4, "the rig grew past its initial four for the larger section", str(o.count()))
	var seen : Dictionary[int, bool] = {}
	for idx : int in first: seen[idx] = true
	for idx : int in second:
		check(idx >= 0, "every extra card is lamped after the subdivision")
		check(not seen.has(idx), "and no lamp is shared with the first section")
		seen[idx] = true
	var taken : Array[int] = []
	for idx : int in seen: taken.append(idx)
	taken.sort_custom(func(a: int, b: int) -> bool: return o.origin_of(a).x < o.origin_of(b).x)
	var order_before := taken.duplicate()
	o.advance(0.0)
	taken.sort_custom(func(a: int, b: int) -> bool: return o.origin_of(a).x < o.origin_of(b).x)
	check(order_before == taken,
			"an advance() after subdivision keeps every taken lamp's x order (no teleport)")

## I10–I12: ⚠ `Q164` (*an origin does not move once assigned*) and `Q251`=(b) (*x re-spreads every
## frame*) are ONE answer, not a conflict — the re-spread only ever touches origins ABOVE the
## viewport, which is to say ones you cannot see. A lamp that has come on screen is pinned for good.
func test_origins_respread_only_above_the_viewport() -> void:
	var o := SpotlightOrigins.new()
	o.begin(4, 1280.0, 100.0)
	# Force one lamp on screen, leave the rest above it.
	var on_screen := 0
	var before := o.origin_of(on_screen)
	o._origins[on_screen] = Vector2(before.x, 200.0)
	var above_before : Array[float] = []
	for i : int in range(1, o.count()): above_before.append(o.origin_of(i).x)
	o.advance(0.0)
	check(is_equal_approx(o.origin_of(on_screen).x, before.x),
			"a lamp INSIDE the viewport is pinned and does not move (Q164)",
			"%f vs %f" % [o.origin_of(on_screen).x, before.x])
	var moved := false
	for i : int in range(1, o.count()):
		if not is_equal_approx(o.origin_of(i).x, above_before[i - 1]): moved = true
	check(moved, "while the ones above it re-spread to fill the width (Q251=b, Q262=a)")

## ⚠ **`Q117`, AND IT IS THE ONE RULE THE SHADER DELIBERATELY DOES NOT ENFORCE.** Owner: *"beam
## still draws from screen edge, but only if target is below viewport bottom. beam can never point
## upwards."* Keeping it here rather than in the shader means one copy: a shader that also clamped
## could disagree with the allocator, and the disagreement would be invisible.
func test_a_beam_never_points_upward() -> void:
	var o := SpotlightOrigins.new()
	o.begin(5, 1280.0, 100.0)
	var ok := true
	for i : int in o.count():
		if not SpotlightOrigins.points_down(o.origin_of(i), Vector2(640.0, 400.0)): ok = false
	check(ok, "every rig lamp points DOWN at a target on the board (Q117)")
	# A target BELOW the viewport is the case the rule exists for: the beam comes in from the top
	# edge instead of tilting up to reach it.
	var below := Vector2(640.0, 900.0)
	var edge := SpotlightOrigins.edge_origin_for(below, 0.0, 760.0, Vector2(640.0, -500.0))
	check(SpotlightOrigins.points_down(edge, below),
			"and a target BELOW the viewport is lit from the screen edge, still pointing down",
			str(edge))
	var normal := Vector2(640.0, 400.0)
	check(SpotlightOrigins.edge_origin_for(normal, 0.0, 760.0, Vector2(640.0, -500.0))
			== Vector2(640.0, -500.0),
			"while a target on screen keeps its rig lamp")


## **A SHRINKING SECTION MUST KEEP THE LIGHTS ALREADY NEAREST ITS TARGETS.**
##
## ⚠ **THE BUG THIS PINS SHIPPED AND WAS FOUND BY EYE, NOT BY A TEST** (owner, 2026-08-05: *"when
## spotlight chooses new targets and there are less cards, it doesnt choose nearest spotlights but
## leftmost ones, so left beams cross all the way to right while right beams disappear"*). Pairing two
## x-sorted lists cannot CROSS, which is why chart E2 does it — but with unequal counts the old code
## paired `leftover[0..pairs)`, so the survivors were always the LEFTMOST beams however far away they
## were, and the beams sitting on the targets retired. Non-crossing was true and still wrong.
##
## ⚠ Asserted on the ARITHMETIC (`nearest_window`) rather than through the director, because that is
## the whole of the rule and it is decidable headlessly — no board, no frame, no pixels.
func test_a_shrinking_section_keeps_the_NEAREST_lights() -> void:
	# Five lit cards spread across the board; the next section is the two on the RIGHT.
	var sources := PackedFloat32Array([100.0, 300.0, 500.0, 700.0, 900.0])
	var targets := PackedFloat32Array([700.0, 900.0])
	var start := SpotlightOrigins.nearest_window(sources, targets)
	check(start == 3,
			"a section shrinking to its RIGHT keeps the two RIGHTMOST lights",
			"window starts at %d (0 means it kept the leftmost and crossed the board)" % start)
	# ...and the mirror, so the fix cannot be "always take the last N" either.
	targets = PackedFloat32Array([100.0, 300.0])
	start = SpotlightOrigins.nearest_window(sources, targets)
	check(start == 0, "and a section shrinking to its LEFT keeps the two LEFTMOST",
			"window starts at %d" % start)
	# A middle target set: neither end.
	targets = PackedFloat32Array([300.0, 500.0])
	start = SpotlightOrigins.nearest_window(sources, targets)
	check(start == 1, "and a MIDDLE target set keeps the middle lights", "window starts at %d" % start)
	# Equal counts must be a no-op — every light travels, none retires.
	targets = PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0])
	check(SpotlightOrigins.nearest_window(sources, targets) == 0,
			"equal counts keep every light (window 0), so nothing is dropped")
	# ⚠ The window stays CONTIGUOUS and in order, which is what preserves E2's non-crossing property:
	# a nearest-each match would pick sources 4 and 3 for these targets and invert them.
	sources = PackedFloat32Array([0.0, 10.0, 20.0])
	targets = PackedFloat32Array([19.0, 21.0])
	start = SpotlightOrigins.nearest_window(sources, targets)
	check(start == 1, "the window is contiguous and ordered — no inversion is possible",
			"window starts at %d" % start)

	# **THE GROWING CASE — which TARGETS get the travelling lights** (owner: *"when spawning new
	# spotlights it should also prioritize nearest"*). Same helper, arguments swapped: the sources are
	# now the smaller list, so the window is over the TARGETS and the rest spawn in place.
	var lights := PackedFloat32Array([800.0, 900.0])
	var wanted := PackedFloat32Array([100.0, 300.0, 500.0, 800.0, 900.0])
	var tgt_start := SpotlightOrigins.nearest_window(wanted, lights)
	check(tgt_start == 3,
			"a growing section sends its two live lights to the NEAREST targets, and spawns the rest",
			"target window starts at %d (0 would drag both lights across the board)" % tgt_start)
