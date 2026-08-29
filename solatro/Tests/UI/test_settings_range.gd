extends TestSuite
# res://Tests/UI/test_settings_range.gd
# ==============================================================================
# SETTINGS RANGE — every board invariant must hold at ANY setting value, not just
# the shipped ones.
#
# Owner ruling: *"tests should have its own settings it tests with over range of possible
# settings values, that way tuning settings wont break tests, and tests that any setting is
# valid."* Two claims live in that sentence and this suite covers both:
#
#   1. Tuning a knob cannot break a test — because a suite runs on its OWN PlayerSettings
#      (SettingsManager.isolated), never the player's file. Pinned below, since the whole
#      protection is one flag and a silent regression would restore the old damage: a run
#      killed by its timeout used to leave TEST values as the player's live settings.
#   2. Any setting value is valid — the geometry is swept across each knob's range rather than
#      asserted at one blessed number.
#
# ⚠ WHAT MAKES THIS NON-VACUOUS: a sweep that only checked "nothing crashed" would pass on a
# board where every card landed on the same pixel. Each case asserts a RELATIONSHIP that has to
# survive the scaling — stacks rise, a row shares one bottom line, the pitch tracks the knob that
# sets it — so a formula that ignored a knob fails here even though it never errors.
#
# CATEGORY MAP: BEHAVIOR — what the player sees stays correct however they have tuned the game.
# IMPLEMENTATION — the isolation flag itself.
# ==============================================================================

const PLAY_AREA_SCENE := preload("res://UI/play_area.tscn")
const WATCHDOG_SECS := 10.0

## The sweep. Deliberately includes the EDGES a shipped value never visits: a scale below 1, the
## shipped 1, and a scale well above it. `card_separation_scale` at 0 is the degenerate case where
## a stack has no fan at all, which is legal and must not divide by anything.
const CARD_SCALES : Array[float] = [0.5, 1.0, 2.5]
const SEPARATION_SCALES : Array[float] = [0.0, 1.0, 3.0]

func suite_name() -> String:
	return "SETTINGS RANGE"

func _ready() -> void:
	await await_siblings_except(["E2E RUN", "LEAK CANARY", "WALL PAUSE"])
	TestLog.line("============ SETTINGS RANGE TEST PASS ============")
	backup_real_settings()
	use_own_settings()   # this suite sweeps VALUES, so it owes nothing to the player's tuning
	check_all_tests_registered()
	await run_a_suite_never_writes_the_players_settings_test()
	await run_the_board_holds_its_shape_at_any_card_scale_test()
	await run_the_fan_tracks_its_own_knob_at_any_separation_scale_test()
	restore_real_settings()
	finish()

# ==============================================================================
# The isolation itself — claim 1.
# ==============================================================================
func run_a_suite_never_writes_the_players_settings_test() -> void:
	implementation_section("A SUITE NEVER WRITES THE PLAYER'S SETTINGS")
	check(SettingsManager.isolated,
			"backup_real_settings() put the manager in isolated mode",
			"isolated = %s" % SettingsManager.isolated)

	# ⚠ The instrument is the FILE's modification time, not its existence: the player's file is
	# supposed to still be sitting there untouched, so "it does not exist" would be the wrong
	# assertion and "it exists" would prove nothing.
	var path := "user://settings.tres"
	var before := FileAccess.get_modified_time(ProjectSettings.globalize_path(path)) \
			if FileAccess.file_exists(path) else -1
	SettingsManager.settings.card_scale = 3.7
	SettingsManager.save_settings()   # asked directly, not just via the setter
	var after := FileAccess.get_modified_time(ProjectSettings.globalize_path(path)) \
			if FileAccess.file_exists(path) else -1
	check(before == after,
			"a knob write, and an explicit save_settings(), leave the player's file untouched",
			"mtime %d -> %d" % [before, after])

	# And the suite really is scribbling on something — otherwise the check above is about a
	# settings object nobody is using.
	check(is_equal_approx(SettingsManager.settings.card_scale, 3.7),
			"...while the suite's OWN settings did take the value",
			"card_scale = %f" % SettingsManager.settings.card_scale)
	SettingsManager.settings.card_scale = 1.0

# ==============================================================================
# Claim 2, part one: the board's shape at any card scale.
# ==============================================================================
func run_the_board_holds_its_shape_at_any_card_scale_test() -> void:
	behavior_section("THE BOARD HOLDS ITS SHAPE AT ANY CARD SCALE")
	for scale : float in CARD_SCALES:
		SettingsManager.settings.card_scale = scale
		var g := _stacked_board()
		var pa := await _stand_up()
		var pitch := float(CardVisual.card_separation_play_custom) + float(pa.separation)

		# A stack still rises, and by the pitch this scale implies — not by a constant.
		var lo := pa.slot_center_global(BoardCoord.new(0, 0, 0, 0)).y
		var hi := pa.slot_center_global(BoardCoord.new(0, 0, 0, 1)).y
		check(hi < lo,
				"card_scale %.2f: a stack still grows UPWARD" % scale,
				"h0 %.1f h1 %.1f" % [lo, hi])
		check(absf((lo - hi) - pitch) < 0.5,
				"card_scale %.2f: consecutive cards sit one depth pitch apart, and the pitch "
				% scale + "SCALED with the knob",
				"gap %.1f vs pitch %.1f" % [lo - hi, pitch])

		# A row still shares one bottom line, whatever the scale did to the cell heights.
		var left := pa.slot_center_global(BoardCoord.new(0, 0, 1, 0)).y
		var right := pa.slot_center_global(BoardCoord.new(0, 2, 1, 0)).y
		check(absf(left - right) < 0.5,
				"card_scale %.2f: two cells in a row still bottom out on one line" % scale,
				"%.1f vs %.1f" % [left, right])
		await _tear_down(g, pa)
	SettingsManager.settings.card_scale = 1.0

# ==============================================================================
# Claim 2, part two: the fan follows the knob that owns it, including at zero.
# ==============================================================================
func run_the_fan_tracks_its_own_knob_at_any_separation_scale_test() -> void:
	behavior_section("THE FAN TRACKS ITS OWN KNOB AT ANY SEPARATION SCALE")
	var gaps : Array[float] = []
	for sep_scale : float in SEPARATION_SCALES:
		SettingsManager.settings.card_separation_scale = sep_scale
		var g := _stacked_board()
		var pa := await _stand_up()
		var pitch := float(CardVisual.card_separation_play_custom) + float(pa.separation)
		var gap := pa.slot_center_global(BoardCoord.new(0, 0, 0, 0)).y \
				- pa.slot_center_global(BoardCoord.new(0, 0, 0, 1)).y
		check(absf(gap - pitch) < 0.5,
				"separation_scale %.1f: the arithmetic uses the pitch this knob produces"
				% sep_scale, "gap %.1f vs pitch %.1f" % [gap, pitch])
		check(gap >= 0.0,
				"separation_scale %.1f: the stack never inverts, however small the fan" % sep_scale,
				"gap %.1f" % gap)
		gaps.append(gap)
		await _tear_down(g, pa)
	# ⚠ THE CHECK THAT MAKES THE SWEEP MEAN SOMETHING: the gaps must actually DIFFER across the
	# range. If the geometry ignored this knob every case above would still pass.
	check(gaps.size() == 3 and gaps[2] > gaps[0],
			"a bigger separation scale really does fan the stack further — the sweep moved "
			+ "something, so the cases above are not all the same board",
			str(gaps))
	SettingsManager.settings.card_separation_scale = 1.0

# ==============================================================================
# Fixture
# ==============================================================================
## A 3x3 grid: one cell two deep (so a stack has a gap to measure) and two cells in row 1 with a
## card each (so a row has a bottom line to share).
func _stacked_board() -> Game:
	var g := Game.new()
	var s := GameData.new()
	var grid := GridData.new()
	grid.grid_width = 3
	grid.grid_height = 3
	grid.build_cells()
	for spot : Vector3i in [Vector3i(0, 0, 2), Vector3i(0, 1, 1), Vector3i(2, 1, 1)]:
		for _i : int in spot.z:
			var card := TestFactories.m_card(_i + 2, TestFactories.uc())
			card.stage = CardData.Stage.PLAY
			grid.cells[grid.cell_index(spot.x, spot.y)].datas.append(card)
	s.grids = [grid] as Array[GridData]
	g.state = s
	g._begin_act()
	CardEnvironment.CURRENT = g
	return g

func _stand_up() -> PlayArea:
	var pa : PlayArea = PLAY_AREA_SCENE.instantiate()
	add_child(pa)
	pa.size = Vector2(1152, 648)
	var waited := 0.0
	while not pa.visuals_ready() and waited < WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	pa.flush_rebuild()
	await get_tree().process_frame
	await get_tree().process_frame
	return pa

func _tear_down(g: Game, pa: PlayArea) -> void:
	pa.queue_free()
	CardEnvironment.CURRENT = null
	await get_tree().process_frame
	g.free()
