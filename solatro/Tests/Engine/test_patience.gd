extends TestSuite
# res://Tests/Engine/test_patience.gd
# ==============================================================================
# PATIENCE (2026-07-20) — the per-round idle-move pressure: card moves tick a counter down, a
# move that triggers a qualifying card modifier holds it, and 0 auto-presses Next. Runs fully
# headless (view == null), like test_game_headless: a bare Game.new() never added to the tree,
# with CardEnvironment.CURRENT set by hand so rules skills resolve `game`.
#
# WHICH HOOK COUNTS: try_place moves cards with trigger_mods = false, so the ONLY dispatch a
# placement performs is the legality query on_can_place_stack — which is exactly why
# _note_mod_fired was extended to the return_first_* paths (owner ruling A3). The probes below
# therefore hold/skip patience through an on_can_place_stack implementation.
#
# SETTINGS COVERAGE: every patience knob is exercised at a NON-DEFAULT value as well as its
# shipped one (the defaults were the only thing playtested by hand) — see the per-stage toggle
# sweep, the uniques-off case, the reset-policy pair, the disabled-hook case and the max
# floor/grant case. Settings isolation: the player's real settings.tres is parked aside for the
# whole suite (SettingsManager writes it on EVERY knob write, so an aborted run would otherwise
# strand the player's knobs on test values) and the live resource is snapshot/restored.
#
# CATEGORY MAP: all BEHAVIOR (what the player experiences) except the seen-set storage pins.
# ==============================================================================

func suite_name() -> String:
	return "PATIENCE"

## The player's live knob values, captured once and re-applied before EVERY test so no test
## inherits another's tweaks (and restored for good at the end).
var _settings_snapshot : Dictionary = {}

## Stage -> the settings toggle that decides whether a trigger from it holds patience. The
## sweep below drives each one both off (shipped default) and on.
const STAGE_KNOBS : Dictionary = {
	CardData.Stage.DRAW: "patience_influence_draw",
	CardData.Stage.ZONE: "patience_influence_zone",
	CardData.Stage.DISCARD: "patience_influence_discard",
	CardData.Stage.RULES: "patience_influence_rules",
}

func _ready() -> void:
	TestLog.line("============ PATIENCE TEST PASS ============")
	backup_real_settings()
	# scoped to "patience_" ONLY: this suite runs concurrently with the other unordered suites,
	# so restoring every knob would stomp whatever they are mid-way through setting
	_settings_snapshot = snapshot_settings("patience_")
	behavior_section("SPENDING & HOLDING")
	await test_idle_move_spends()
	await test_trigger_holds_then_seen_spends()
	await test_uniques_off_holds_every_time()
	await test_disabled_hook_does_not_hold()
	behavior_section("PER-STAGE INFLUENCE TOGGLES (each off AND on)")
	await test_every_stage_influence_toggle()
	await test_play_influence_off()
	behavior_section("AUTO-NEXT, RESET & UNDO")
	await test_auto_next_at_zero_and_undo_refunds()
	await test_seen_set_reset_policies()
	await test_next_commits_a_seen_set_only_change()
	test_patience_max_floor_and_grant()
	behavior_section("CARD DESCRIPTION MARKER")
	test_describe_card_seen_marker()
	restore_settings_snapshot(_settings_snapshot)
	restore_real_settings()
	finish()

## Back to the player's values — called at the top of every test.
func fresh_settings() -> void:
	restore_settings_snapshot(_settings_snapshot)

# ==============================================================================
# FIXTURE
# ==============================================================================

## A board-card TYPE that implements the placement legality query without ever claiming a
## placement ([] = "not my call"), so it FIRES (and can hold patience) while leaving the real
## placer in charge of legality. Fixed combo_key: an inner class's script has no resource_path,
## so the default key would be empty (= opted out of patience entirely).
class ProbeType extends CardModifierType:
	var key : String = "probe"
	func get_str() -> String: return "Probe"
	func get_description() -> String: return "probe"
	func get_frame() -> int: return 0
	func combo_key(_hook: StringName = &"") -> String: return key
	func on_can_place_stack(_stack: Array[CardData], _target: CardData) -> Array[CardData]:
		return [] as Array[CardData]

func rules_card(skill: CardModifierSkill) -> CardData:
	var c := CardData.new().with_skill(skill)
	c.stage = CardData.Stage.RULES
	skill.active = true
	return c

## The minimal show that supports a legal placement: classic grabber/placer rules and two lower
## columns of ascending, distinct-suit pairs (plus the paired upper zone, so state.validate()
## holds). No view. History is seeded so undo has somewhere to land.
func make_game(patience_max: int = 3) -> Game:
	SettingsManager.settings.patience_max = patience_max
	var g := Game.new()
	var s := GameData.new()
	s.rules_deck = [
		rules_card(SkillGrabberOgLower.new()),
		rules_card(SkillPlacerOgLower.new()),
	] as Array[CardData]
	for zone_x in 2:
		var types : Array[CardData] = []
		var cols : Array[ArrayCardData] = []
		for c in 2:
			var header := TestFactories.m_card(1, TestFactories.uc())
			header.stage = CardData.Stage.ZONE
			types.append(header)
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
	g.state.reset_patience(SettingsManager.settings.patience_max)
	g.save_state()
	return g

func free_game(g: Game) -> void:
	CardEnvironment.CURRENT = null
	g.free()

## Park a probe-carrying card at `stage` in the collection that stage belongs to, so its
## on_can_place_stack fires from THERE during the next placement's legality query. ZONE reuses
## an existing header (adding a column would have to keep zone/zone_type in lockstep, I2).
## ⚠️ RULES goes to the FRONT of rules_deck: on_can_place_stack runs through
## return_first_data_array_result, which stops at the first mod returning a non-empty answer —
## the real placer lives in rules_deck, so a probe appended after it would never fire at all.
## (The engine rules skills themselves can't stand in for the probe: they return "" from
## combo_key, which opts them out of combo AND patience by design.)
func plant_probe(g: Game, stage: int, key: String) -> void:
	var probe := ProbeType.new()
	probe.key = key
	if stage == CardData.Stage.ZONE:
		g.state.upper_zone_type[0].with_type(probe)
	else:
		var card := TestFactories.m_card(9, TestFactories.uc()).with_type(probe)
		card.stage = stage
		match stage:
			CardData.Stage.DRAW: g.state.draw_deck.append(card)
			CardData.Stage.DISCARD: g.state.discard_deck.append(card)
			CardData.Stage.RULES: g.state.rules_deck.insert(0, card)
	g.state.revision += 1

## ONE real, legal board move: push a fresh card (optionally carrying a probe modifier, which
## then fires its on_can_place_stack during the legality query) onto lower column 0, push a
## rank+1 distinct-suit target onto column 1, and place the first onto the second. Built fresh
## each time so legality never depends on what earlier moves left behind.
func do_move(g: Game, probe_key: String = "") -> bool:
	var moving := TestFactories.m_card(4, TestFactories.uc())
	if not probe_key.is_empty():
		var probe := ProbeType.new()
		probe.key = probe_key
		moving.with_type(probe)
	moving.stage = CardData.Stage.PLAY
	g.state.lower_zone[0].datas.append(moving)
	var target := TestFactories.m_card(5, TestFactories.uc())
	target.stage = CardData.Stage.PLAY
	g.state.lower_zone[1].datas.append(target)
	g.state.revision += 1
	return await g.try_place([moving] as Array[CardData], target)

# ==============================================================================
# SPENDING & HOLDING
# ==============================================================================

func test_idle_move_spends() -> void:
	fresh_settings()
	var g := make_game(3)
	check(g.state.patience == 3, "a fresh show starts at patience_max", str(g.state.patience))
	check(await do_move(g), "precondition: the move is legal")
	check(g.state.patience == 2, "an idle move spends one patience", str(g.state.patience))
	free_game(g)

func test_trigger_holds_then_seen_spends() -> void:
	fresh_settings()
	SettingsManager.settings.patience_track_uniques = true
	var g := make_game(3)
	check(await do_move(g, "hold-probe"), "precondition: the probe card places legally")
	check(g.state.patience == 3, "a move that triggers a new PLAY-stage mod holds patience",
			str(g.state.patience))
	check_impl(g.state.patience_seen_mods.has("hold-probe"),
			"the triggered mod is recorded in the seen-set", str(g.state.patience_seen_mods))
	# the SAME probe key again: the audience has seen it, so this move is boring
	check(await do_move(g, "hold-probe"), "precondition: the second move is legal")
	check(g.state.patience == 2, "re-triggering an already-seen mod spends patience anyway",
			str(g.state.patience))
	free_game(g)

## patience_track_uniques OFF (non-default): every trigger holds, forever, and nothing is
## ever recorded as seen.
func test_uniques_off_holds_every_time() -> void:
	fresh_settings()
	SettingsManager.settings.patience_track_uniques = false
	var g := make_game(3)
	check(await do_move(g, "repeat-probe"), "precondition: the first probe move is legal")
	check(await do_move(g, "repeat-probe"), "precondition: the second probe move is legal")
	check(g.state.patience == 3,
			"with uniques off, re-triggering the SAME mod keeps holding patience",
			str(g.state.patience))
	check_impl(g.state.patience_seen_mods.is_empty(),
			"with uniques off nothing is recorded as seen", str(g.state.patience_seen_mods))
	free_game(g)

## patience_disabled_hooks (non-default): an opted-out hook never holds, even from an
## approved stage.
func test_disabled_hook_does_not_hold() -> void:
	fresh_settings()
	SettingsManager.settings.patience_disabled_hooks = [&"on_can_place_stack"] as Array[StringName]
	var g := make_game(3)
	check(await do_move(g, "disabled-probe"), "precondition: the move is legal")
	check(g.state.patience == 2, "a hook in patience_disabled_hooks never holds patience",
			str(g.state.patience))
	free_game(g)

# ==============================================================================
# PER-STAGE INFLUENCE TOGGLES
# ==============================================================================

## Every non-PLAY stage toggle, driven BOTH ways. Off is the shipped default (only cards in
## play entertain the audience); on makes that stage's triggers hold. Turning RULES on is NOT
## the "nothing ever costs patience" footgun it looks like: the engine rules mods (grabber,
## placer) return "" from combo_key, which opts them out of patience as well as combo — so a
## rules-stage CONTENT card has to opt in before it can hold anything.
func test_every_stage_influence_toggle() -> void:
	for stage : int in STAGE_KNOBS:
		var knob : String = STAGE_KNOBS[stage]
		var label : String = str(CardData.Stage.find_key(stage))
		fresh_settings()
		var off_game := make_game(3)
		plant_probe(off_game, stage, "probe-off-%s" % label)
		check(await do_move(off_game), "precondition: move legal with a %s probe" % label)
		check(off_game.state.patience == 2,
				"a %s trigger does NOT hold patience while %s is off" % [label, knob],
				str(off_game.state.patience))
		free_game(off_game)
		fresh_settings()
		SettingsManager.settings.set(knob, true)
		var on_game := make_game(3)
		plant_probe(on_game, stage, "probe-on-%s" % label)
		check(await do_move(on_game),
				"precondition: move legal with a %s probe (%s on)" % [label, knob])
		check(on_game.state.patience == 3,
				"a %s trigger HOLDS patience once %s is on" % [label, knob],
				str(on_game.state.patience))
		free_game(on_game)

## patience_influence_play OFF (non-default): the shipped-on stage can be switched off too,
## and then even a PLAY-stage trigger is boring.
func test_play_influence_off() -> void:
	fresh_settings()
	SettingsManager.settings.patience_influence_play = false
	var g := make_game(3)
	check(await do_move(g, "play-probe"), "precondition: the move is legal")
	check(g.state.patience == 2,
			"a PLAY trigger does NOT hold once patience_influence_play is off",
			str(g.state.patience))
	free_game(g)

# ==============================================================================
# AUTO-NEXT, RESET & UNDO
# ==============================================================================

## Owner ruling A5: patience 0 is never a playable board. The move that empties the counter
## folds into the auto-Next and commits ONE snapshot, so undo returns to the board BEFORE that
## move with its patience intact — undo can never buy an extra action.
func test_auto_next_at_zero_and_undo_refunds() -> void:
	fresh_settings()
	var g := make_game(1)
	var history_before := g.save_history.size()
	check(g.state.patience == 1, "patience_max 1 = one idle move per round", str(g.state.patience))
	check(await do_move(g), "precondition: the move is legal")
	check(g.state.patience == 1, "hitting 0 auto-fired Next, which refilled patience",
			str(g.state.patience))
	check(g.save_history.size() == history_before + 1,
			"the move + auto-Next commit exactly ONE undo step",
			str(g.save_history.size() - history_before))
	g.undo()
	check(g.state.patience == 1, "undoing the auto-Next returns to a patience-1 board",
			str(g.state.patience))
	free_game(g)

func test_seen_set_reset_policies() -> void:
	fresh_settings()
	SettingsManager.settings.patience_track_uniques = true
	SettingsManager.settings.patience_reset_uniques_on_act = false
	var g := make_game(3)
	g.state.mark_seen("sticky")
	await g.next()
	check(g.state.patience_seen_mods.is_empty(),
			"by default the seen-set clears on Next", str(g.state.patience_seen_mods))
	free_game(g)
	fresh_settings()
	SettingsManager.settings.patience_reset_uniques_on_act = true
	var g2 := make_game(3)
	g2.state.mark_seen("sticky")
	await g2.next()
	check(g2.state.patience_seen_mods.has("sticky"),
			"with reset-on-act, Next leaves the seen-set alone")
	await g2.submit()
	check(g2.state.patience_seen_mods.is_empty(), "a Submit clears it instead")
	free_game(g2)

## Regression (fix 2026-07-20): a round where every move was INTERESTING leaves patience
## already full, so a Next's only change is the seen-set clear. The commit guard used to look
## at the counter alone, so on a board where on_next moved nothing that clear was never
## committed — and a resume brought the stale "already seen" mods back.
func test_next_commits_a_seen_set_only_change() -> void:
	fresh_settings()
	SettingsManager.settings.patience_track_uniques = true
	SettingsManager.settings.patience_reset_uniques_on_act = false
	var g := make_game(3)
	check(await do_move(g, "interesting"), "precondition: the interesting move is legal")
	check(g.state.patience == 3, "precondition: patience is still full (the move held it)",
			str(g.state.patience))
	check(not g.state.patience_seen_mods.is_empty(), "precondition: the seen-set is non-empty")
	var history_before := g.save_history.size()
	await g.next()   # this fixture has no input columns: on_next moves NOTHING
	check(g.state.patience_seen_mods.is_empty(), "Next cleared the seen-set in the live state")
	check(g.save_history.size() == history_before + 1,
			"a seen-set-only Next still COMMITS (no stale data on resume)",
			str(g.save_history.size() - history_before))
	check(g.save_history[-1].patience_seen_mods.is_empty(),
			"the committed snapshot carries the cleared seen-set",
			str(g.save_history[-1].patience_seen_mods))
	free_game(g)

func test_patience_max_floor_and_grant() -> void:
	fresh_settings()
	var s := SettingsManager.settings
	s.patience_max = 0
	check(s.patience_max == 1, "patience_max floors at 1", str(s.patience_max))
	# Owner ruling A1: raising the cap also grants the live counter (lowering never takes any).
	var g := make_game(2)
	s.patience_max_increased.connect(g._on_patience_max_increased)
	s.patience_max = 4
	check(g.state.patience == 4, "raising patience_max grants the live counter the same amount",
			str(g.state.patience))
	s.patience_max = 2
	check(g.state.patience == 4, "lowering patience_max does not take live patience away",
			str(g.state.patience))
	s.patience_max_increased.disconnect(g._on_patience_max_increased)
	free_game(g)

# ==============================================================================
# CARD DESCRIPTION MARKER
# ==============================================================================

## The card-description marker only exists inside a show with unique-tracking on: booster and
## deck previews (no Game) must never show it.
func test_describe_card_seen_marker() -> void:
	fresh_settings()
	SettingsManager.settings.patience_track_uniques = true
	var g := make_game(3)
	var probe := ProbeType.new()
	probe.key = "described"
	var card := TestFactories.m_card(4, TestFactories.uc()).with_type(probe)
	var unseen_text := ControlCard.describe_card(card)
	check(unseen_text.contains(TRANSLATION.find('PATIENCE_UNSEEN')),
			"an untriggered mod is marked unseen in a show", unseen_text)
	g.state.mark_seen("described")
	check(ControlCard.describe_card(card).contains(TRANSLATION.find('PATIENCE_SEEN')),
			"once seen, the description says so")
	SettingsManager.settings.patience_track_uniques = false
	check(not ControlCard.describe_card(card).contains(TRANSLATION.find('PATIENCE_SEEN')),
			"no marker at all when unique tracking is off")
	SettingsManager.settings.patience_track_uniques = true
	free_game(g)
	check(not ControlCard.describe_card(card).contains(TRANSLATION.find('PATIENCE_UNSEEN')),
			"no marker outside a show (booster/deck previews)")
