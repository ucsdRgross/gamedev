extends TestSuite
# The units model: a drag threshold is a fraction of the CARD being dragged, a touch target a
# fraction of the WINDOW's smaller dimension. Neither is clamped, and no screen density is read
# anywhere in the project -- the last test walks every script to keep it that way.

## The row's reference card: the numbers below are this card's width times the shipped knob.
const REFERENCE_CARD := Vector2(216.0, 286.0)

# Split so this suite never itself contains the names the deletion gate greps for.
const RETIRED_DENSITY_TOKENS : Array[String] = ["mm_to" + "_px", "screen_get_d" + "pi"]
const RETIRED_KNOBS : Array[String] = ["grid_swipe_threshold" + "_mm",
		"grid_swipe_threshold" + "_min_mm", "grid_swipe_threshold" + "_max_mm",
		"wall_touch_target" + "_mm", "wall_touch_target" + "_min_px",
		"wall_touch_target" + "_max_px"]

func suite_name() -> String:
	return "GESTURE METRICS"

func _ready() -> void:
	TestLog.line("============ GESTURE METRICS TEST PASS ============")
	check_all_tests_registered()
	run_drag_threshold_tests()
	run_touch_target_tests()
	run_no_density_reading_survives_test()
	run_the_millimetre_knobs_are_gone_test()
	finish()

# ==============================================================================
# The card basis
# ==============================================================================
func run_drag_threshold_tests() -> void:
	behavior_section("A DRAG THRESHOLD IS A FRACTION OF THE CARD (M3, M4, M5)")
	var settings := PlayerSettings.new()
	check(is_equal_approx(settings.card_drag_threshold, 0.25),
			"the shipped knob is the quarter-card the answer asked for (2.1)",
			"card_drag_threshold=%f" % settings.card_drag_threshold)

	var at_rest := GestureMetrics.drag_threshold_px(REFERENCE_CARD, settings)
	check(is_equal_approx(at_rest, 54.0),
			"a 216 px card gives a 54 px threshold (2.1)", "%f px" % at_rest)

	var zoomed := GestureMetrics.drag_threshold_px(REFERENCE_CARD * 2.0, settings)
	check(is_equal_approx(zoomed, 108.0),
			"...and the SAME card at zoom 2.0 gives 108 px, so the gesture scales with the thing "
			+ "being dragged (2.2)", "%f px" % zoomed)

	var default_card := GestureMetrics.drag_threshold_px(CardVisual.card_size_play, settings)
	check(default_card > 0.0 and is_equal_approx(default_card,
			CardVisual.card_size_play.x * settings.card_drag_threshold),
			"a gesture with NO card under it still has a reference: the default card at the current "
			+ "zoom (2.6, Q296=a)",
			"card %s -> %f px" % [CardVisual.card_size_play, default_card])

# ==============================================================================
# The window basis
# ==============================================================================
func run_touch_target_tests() -> void:
	behavior_section("A TOUCH TARGET IS A FRACTION OF THE WINDOW (M7, M8)")
	var settings := PlayerSettings.new()
	check(is_equal_approx(settings.touch_target_fraction, 0.06),
			"the shipped knob is the 6 % the answer asked for (2.3)",
			"touch_target_fraction=%f" % settings.touch_target_fraction)

	var landscape := GestureMetrics.touch_target_px(Vector2(1920.0, 1080.0), settings)
	check(is_equal_approx(landscape, 64.8),
			"a 1920x1080 window gives a 64.8 px target (2.3)", "%f px" % landscape)

	var ultrawide := GestureMetrics.touch_target_px(Vector2(3840.0, 1080.0), settings)
	check(is_equal_approx(ultrawide, landscape),
			"...and a 3840x1080 window gives the SAME target: the SMALLER dimension is the one "
			+ "every screen has (2.4)", "%f px" % ultrawide)

	var tiny := GestureMetrics.touch_target_px(Vector2(192.0, 108.0), settings)
	var giant := GestureMetrics.touch_target_px(Vector2(19200.0, 10800.0), settings)
	check(is_equal_approx(tiny, landscape * 0.1) and is_equal_approx(giant, landscape * 10.0),
			"nothing clamps it: a tenth of the window is a tenth of the target and ten times the "
			+ "window is ten times the target (2.3, Q301=a)",
			"tiny=%f giant=%f" % [tiny, giant])

	check(is_equal_approx(WallInput.touch_target_px(Vector2(1920.0, 1080.0), settings), landscape),
			"WallInput.touch_target_px() is the same model under its old name, so every caller "
			+ "kept its seam (M9, Q305=b)")

# ==============================================================================
# The deletion gate
# ==============================================================================
func run_no_density_reading_survives_test() -> void:
	implementation_section("NO SCREEN-DENSITY READING SURVIVES (M1, L14, 2.5)")
	var offenders : Array[String] = []
	for path : String in gd_scripts_under("res://"):
		var text := FileAccess.get_file_as_string(path)
		for token : String in RETIRED_DENSITY_TOKENS:
			if text.contains(token): offenders.append("%s names %s" % [path, token])
	check(offenders.is_empty(),
			"no script outside addons/ reads the screen's density or converts millimetres (2.5)",
			"\n".join(offenders))

func run_the_millimetre_knobs_are_gone_test() -> void:
	implementation_section("EVERY MILLIMETRE KNOB WENT WITH THE MODEL (L14, 8.3)")
	var settings := PlayerSettings.new()
	var survivors : Array[String] = []
	for knob : String in RETIRED_KNOBS:
		if knob in settings: survivors.append(knob)
	check(survivors.is_empty(),
			"not one of the six millimetre or px-bound knobs is still a setting (8.3)",
			", ".join(survivors))
