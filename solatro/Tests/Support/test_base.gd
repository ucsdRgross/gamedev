class_name TestSuite
extends Node
## Base class for every suite under res://Tests: category-tagged, non-freezing checks, no assert().

signal suite_finished

enum Category { BEHAVIOR, IMPLEMENTATION }

var _pass := 0
var _fail := 0
var _fail_behavior := 0
var _fail_impl := 0
var _warn := 0
var _category := Category.BEHAVIOR
var finished := false
# Suites run CONCURRENTLY, so their durations overlap and do not sum to the run length: what a run
# actually waits on is the LAST finish timestamp. all_tests.gd ranks its tail by finish_msec and
# prints elapsed_msec beside it.
var elapsed_msec := 0
var finish_msec := 0
var _enter_msec := 0

## Suite tag printed in every FAIL line and the summary banner, e.g. "BOARD".
func suite_name() -> String:
	return "TEST"

# Stamps the suite's start, isolates the settings file (a suite scene run ALONE has no all_tests
# above it, and the pacing write would reach the player's settings.tres) and puts EVERY suite on
# the run's pacing. ⚠ A suite with its own _enter_tree must call super() or it loses all three.
func _enter_tree() -> void:
	_enter_msec = Time.get_ticks_msec()
	SettingsManager.isolated = true
	apply_test_speed()

# The run's pacing (TestLog.speed_base_delay) on the settings every concurrent suite shares; call
# it again after deliberately slowing down. ⚠ Skips a write that changes nothing: the setter emits
# regardless, and one suite's finish() then restyled every live FxAttachment in a sibling's shot.
func apply_test_speed() -> void:
	if SettingsManager.settings.base_delay == TestLog.speed_base_delay: return
	SettingsManager.settings.base_delay = TestLog.speed_base_delay

# ⚠ Waiting is a directed dependency: if A waits for B, B must not wait for A, directly or through
# a third suite, or both hang and the run never quits. A waiter takes its place in the chain in
# HEADLESS_TESTING.md "Suite ordering" and excludes every suite after it.
func await_siblings_except(exclude_names: Array[String]) -> void:
	if not get_parent(): return
	for sibling in get_parent().get_children():
		var suite := sibling as TestSuite
		if suite and suite != self and suite.suite_name() not in exclude_names \
				and not suite.finished:
			await suite.suite_finished

## Seconds a bounded wait for a DRAWN frame allows before it reports the drawing dead.
const DRAWN_FRAME_WATCHDOG_SECS := 10.0

# A bare `await RenderingServer.frame_post_draw` never returns when the engine runs its main loop
# while drawing nothing, and the whole run then dies with no verdict for any suite. Bounded, the
# same event costs one named failure. `Engine.get_frames_drawn()` counts what that signal marks.
func await_drawn_frames(count: int) -> void:
	var target := Engine.get_frames_drawn() + count
	var waited := 0.0
	while Engine.get_frames_drawn() < target and waited < DRAWN_FRAME_WATCHDOG_SECS:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if Engine.get_frames_drawn() < target:
		check(false, "the engine is still drawing, so a frame this check reads can arrive",
				("waited %.0fs for %d drawn frame(s) and got none while the main loop kept running; "
				+ "the window reports can_draw=%s")
				% [DRAWN_FRAME_WATCHDOG_SECS, count, DisplayServer.window_can_draw()])

# TWO ACCEPT PRESSES INSIDE THE TAP WINDOW ARE A TAP, not two selections, so a check about a lone
# accept on a focused card waits this out first. Read from the knob, never a frame count.
func await_the_tap_window() -> void:
	var waited := 0.0
	while waited <= PlayArea.settings().card_tap_window_ms / 1000.0:
		await get_tree().process_frame
		waited += get_process_delta_time()

# BEHAVIOR asserts WHAT the game does, so a failure means the game is wrong; IMPLEMENTATION pins
# HOW the code does it today, so a failure after a refactor may be an internal that rightly changed.
# Every check() inherits the open section; check_behavior()/check_impl() override one check.
func behavior_section(title: String) -> void:
	_category = Category.BEHAVIOR
	TestLog.line("\n--- [BEHAVIOR] %s ---" % title)

func implementation_section(title: String) -> void:
	_category = Category.IMPLEMENTATION
	TestLog.line("\n--- [IMPLEMENTATION] %s ---" % title)

## Non-freezing check in the current section's category.
func check(ok: bool, ctx: String, detail: String = "") -> void:
	_check_cat(ok, _category, ctx, detail)

## One-off category overrides for a check that differs from its section.
func check_behavior(ok: bool, ctx: String, detail: String = "") -> void:
	_check_cat(ok, Category.BEHAVIOR, ctx, detail)

func check_impl(ok: bool, ctx: String, detail: String = "") -> void:
	_check_cat(ok, Category.IMPLEMENTATION, ctx, detail)

## Deliberate drift, e.g. art not yet made — never something wrong. Counted apart from _fail.
func warn(ok: bool, ctx: String, detail: String = "") -> void:
	if ok:
		_pass += 1
		TestLog.line("  [PASS] " + ctx)
		return
	_warn += 1
	TestLog.line("[WARN][PLACEHOLDER] %s: %s%s" % [suite_name(), ctx,
			"" if detail.is_empty() else (" -- " + detail)])

func _check_cat(ok: bool, cat: Category, ctx: String, detail: String) -> void:
	if ok:
		_pass += 1
		TestLog.line("  [PASS] " + ctx)
		return
	_fail += 1
	if cat == Category.BEHAVIOR:
		_fail_behavior += 1
	else:
		_fail_impl += 1
	var tag := "BEHAVIOR" if cat == Category.BEHAVIOR else "IMPLEMENTATION"
	TestLog.line("[FAIL][%s] %s: %s%s" % [tag, suite_name(), ctx,
			"" if detail.is_empty() else (" -- " + detail)], true)

## The real run's save; disk suites park it via backup_real_save(tag) rather than skip if it exists.
const REAL_RUN_PATH := "user://run_save/run.tres"

# Per-CALLER backup path, keyed by `tag`: one shared name let concurrent suites park and restore
# across each other, and one suite's restore deleted run.tres under another mid-write. A tag names
# the PURPOSE (a suite passes suite_tag()); two callers sharing one share the bug.
static func run_bak_path(tag: String) -> String:
	return "user://run_save/run.tres.%s.testbak" % tag

# STATIC so harnesses outside the test tree (spotlight_tool --trace, reveal_shot) share it: one of
# them once overwrote the player's run. Restores first: an ABORTED run may have left the real file
# parked under this tag, and parking again would make its throwaway save "the real one".
static func backup_real_save(tag: String) -> void:
	restore_real_save(tag)
	if FileAccess.file_exists(REAL_RUN_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_RUN_PATH),
				ProjectSettings.globalize_path(run_bak_path(tag)))

# Drops the run.tres a test left behind before moving the real one back.
static func restore_real_save(tag: String) -> void:
	var bak := run_bak_path(tag)
	if not FileAccess.file_exists(bak):
		return
	if FileAccess.file_exists(REAL_RUN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_RUN_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(bak),
			ProjectSettings.globalize_path(REAL_RUN_PATH))

## The tag a suite parks under: its own name, so no two collide. Public for diagnostic scenes.
func suite_tag() -> String:
	return suite_name().to_lower().replace(" ", "_")

## The player's settings file. No local copies: per-suite backup names keep concurrent parks apart.
const REAL_SETTINGS_PATH := "user://settings.tres"

## Per-suite backup name: concurrent suites sharing one path swallow each other's park/restore.
func _settings_bak_path() -> String:
	return "user://settings.tres.%s.testbak" % suite_name().to_lower().replace(" ", "_")

# A suite gets its OWN PlayerSettings and the player's file is never written (owner ruling): a
# suite killed by its timeout once left test values live, and later runs hung at an unchanged
# commit. The file-parking underneath only heals a save left by a run from before this.
func backup_real_settings() -> void:
	_move_settings_backup_home()
	SettingsManager.isolated = true

# Fresh settings, so swept values owe nothing to the player's tuning. ⚠ Call it BEFORE the suite
# builds anything: swapping the resource leaves anything holding the old one reading it — a live
# Wall kept its _ready capture and two checks failed. Live-object suites: backup_real_settings().
func use_own_settings() -> PlayerSettings:
	SettingsManager.isolated = true
	SettingsManager.settings = PlayerSettings.new()
	apply_test_speed()
	return SettingsManager.settings

# Keeps SettingsManager.isolated set: all_tests sets it for the whole run, and a finishing suite
# must not re-open the player's file to the suites after it.
func restore_real_settings() -> void:
	_move_settings_backup_home()
	SettingsManager.reload_from_disk()
	apply_test_speed()

# Drop whatever the suite wrote and move this suite's parked real file back over it.
func _move_settings_backup_home() -> void:
	var bak := _settings_bak_path()
	if not FileAccess.file_exists(bak):
		return
	if FileAccess.file_exists(REAL_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(bak),
			ProjectSettings.globalize_path(REAL_SETTINGS_PATH))

# Every @export knob under `prefix`, copied, so a restore names no fields (a hand-listed one leaks
# the knob someone forgot). ⚠ Scope the prefix to the knobs the suite owns: settings are shared
# by concurrent suites, so a full restore stomps a sibling's knobs. A plain `var` is not captured.
func snapshot_settings(prefix: String = "") -> Dictionary:
	var out : Dictionary = {}
	var s := SettingsManager.settings
	for prop : Dictionary in s.get_property_list():
		var usage : int = prop["usage"]
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_STORAGE):
			continue
		var prop_name : String = prop["name"]
		if not prop_name.begins_with(prefix):
			continue
		var value : Variant = s.get(prop_name)
		if value is Array:
			out[prop_name] = (value as Array).duplicate()
		elif value is Dictionary:
			out[prop_name] = (value as Dictionary).duplicate()
		else:
			out[prop_name] = value
	return out

## Puts a snapshot_settings() capture back on the live resource, never the file.
func restore_settings_snapshot(snap: Dictionary) -> void:
	var s := SettingsManager.settings
	for key : String in snap:
		s.set(key, snap[key])

# A test defined but never called from _ready is indistinguishable from a passing one: six shipped
# that way and were reported as added. Reads the suite's own source, so calling this is the whole
# guard. Name a helper `_x`, not `run_x` or `test_x`, to exempt it.
func check_all_tests_registered() -> void:
	implementation_section("REGISTRATION GATE")
	var path : String = get_script().resource_path
	var f := FileAccess.open(path, FileAccess.READ)
	check(f != null, "the registration gate can read this suite's source", path)
	if not f: return
	var lines := f.get_as_text().split("
")
	var ready_body := ""
	var in_ready := false
	for raw : String in lines:
		if raw.begins_with("func _ready("):
			in_ready = true
			continue
		if in_ready:
			if raw.begins_with("func "): break
			ready_body += raw + "
"
	var defined : Array[String] = []
	for raw : String in lines:
		if raw.begins_with("func run_") or raw.begins_with("func test_"):
			defined.append(raw.substr(5, raw.find("(") - 5))
	var unregistered : Array[String] = []
	for name : String in defined:
		if not ready_body.contains(name + "("): unregistered.append(name)
	check(not defined.is_empty(), "the gate found this suite's tests at all", path)
	check(unregistered.is_empty(),
			"every run_* or test_* test defined in this suite is called from _ready",
			"never called: %s" % ", ".join(unregistered))

## Prints the suite banner with its failure split and signals all_tests.gd that this suite is done.
func finish() -> void:
	apply_test_speed()
	finish_msec = Time.get_ticks_msec()
	elapsed_msec = finish_msec - _enter_msec
	var total := _pass + _fail
	var warned := "" if _warn == 0 else (" [%d placeholder warnings]" % _warn)
	var took := " [%.2fs]" % (float(elapsed_msec) / 1000.0)
	if _fail == 0:
		TestLog.line("============ %s: ALL %d CHECKS PASSED%s ============%s"
				% [suite_name(), total, warned, took])
	else:
		TestLog.line("============ %s: %d passed, %d FAILED (behavior %d, implementation %d) of %d%s ============%s"
				% [suite_name(), _pass, _fail, _fail_behavior, _fail_impl, total, warned, took], true)
	finished = true
	suite_finished.emit()

## Every .gd under `dir`, recursively. Skips addons/, which is vendored and not ours.
func gd_scripts_under(dir: String) -> Array[String]:
	var out : Array[String] = []
	var d := DirAccess.open(dir)
	if not d: return out
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full := dir.path_join(entry)
		if d.current_is_dir():
			if entry != "addons": out.append_array(gd_scripts_under(full))
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = d.get_next()
	d.list_dir_end()
	return out
