class_name TestSuite
extends Node
## Base class for every suite under res://Tests. Provides category-tagged, non-freezing
## checks (never assert()) so every failure names which KIND of test broke:
##
##   BEHAVIOR — asserts WHAT the game does: rules, outcomes, and invariants a player or
##   the design doc cares about. These are the tests we want more of; a failure means the
##   game is wrong (or a rule changed on purpose — update the design doc, then the test).
##
##   IMPLEMENTATION — pins HOW the code currently does it: internal data structures,
##   dispatch order, storage formats, pinned policies. These exist mostly as sanity checks
##   that code (often agent-written) does what it looks like it does. A failure after a
##   refactor may just mean the internals legitimately changed — verify the intent, then
##   update the pin.
##
## Usage: override suite_name(), open groups of checks with behavior_section("TITLE") /
## implementation_section("TITLE") (every check() inherits the current category), use
## check_behavior()/check_impl() for a one-off check that differs from its section, and
## call finish() at the end of _ready(). FAIL lines print as
## [FAIL][BEHAVIOR] SUITE: ctx   or   [FAIL][IMPLEMENTATION] SUITE: ctx.

signal suite_finished

enum Category { BEHAVIOR, IMPLEMENTATION }

var _pass := 0
var _fail := 0
var _fail_behavior := 0
var _fail_impl := 0
var _category := Category.BEHAVIOR
var finished := false

## Suite tag printed in every FAIL line and the summary banner, e.g. "BOARD".
func suite_name() -> String:
	return "TEST"

# ==============================================================================
# SUITE ORDERING — READ THIS BEFORE ADDING A SUITE THAT WAITS ON OTHERS.
#
# Most suites run concurrently. A few need near-exclusive access to global singletons
# (CardEnvironment.CURRENT, Main.save_info, SettingsManager — which write to disk) and so wait
# for other suites to finish first, at the top of their _ready(), via await_siblings_except().
#
# ⚠️ THE DEADLOCK RULE: waiting is a directed dependency. If suite A waits for suite B, then B
# must NOT wait for A — directly OR transitively — or BOTH hang forever and the whole run never
# finishes (all_tests never quits; log tails just stop). A real deadlock shipped once because a
# new suite (VISUAL LAYERS) waited for INTERACTION while INTERACTION still waited for it.
#
# The canonical linear order (each waiter excludes every suite AFTER it, plus itself):
#     <engine/map suites: no wait>  →  INTERACTION  →  UI PROPS  →  VISUAL LAYERS  →  E2E RUN  →  LEAK CANARY
#
# When you add a waiting suite: place it in this chain, pass the names of all suites that come
# AFTER it to await_siblings_except(), and add its name to the excludes of every suite BEFORE it.
# Never have two suites exclude-then-wait on each other.
# ==============================================================================

## Await every sibling suite to finish EXCEPT those named in `exclude_names` (and self). See the
## DEADLOCK RULE above — the excludes must be consistent across suites or the run hangs.
func await_siblings_except(exclude_names: Array[String]) -> void:
	if not get_parent(): return
	for sibling in get_parent().get_children():
		var suite := sibling as TestSuite
		if suite and suite != self and suite.suite_name() not in exclude_names \
				and not suite.finished:
			await suite.suite_finished

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

## Disk-test isolation. The save/load suites write and delete user://run_save/run.tres —
## the SAME file a real run uses. Rather than skip when a real save exists (which made the
## tests dependent on unrelated player state), the disk suites call backup_real_save()
## before touching disk and restore_real_save() after, so they ALWAYS run full and a real
## run is preserved. The backup uses a non-.tres suffix so has_save() (which keys on
## run.tres) never sees it.
const REAL_RUN_PATH := "user://run_save/run.tres"
const REAL_RUN_BAK := "user://run_save/run.tres.testbak"

func backup_real_save() -> void:
	if FileAccess.file_exists(REAL_RUN_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_RUN_PATH),
				ProjectSettings.globalize_path(REAL_RUN_BAK))

func restore_real_save() -> void:
	if not FileAccess.file_exists(REAL_RUN_BAK):
		return
	# a test may have left its own run.tres behind — clear it before restoring the real one
	if FileAccess.file_exists(REAL_RUN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_RUN_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_RUN_BAK),
			ProjectSettings.globalize_path(REAL_RUN_PATH))

## Settings isolation (2026-07-20). SettingsManager writes user://settings.tres on EVERY knob
## write (on_settings_changed -> save_settings), so a suite that scribbles on the live
## PlayerSettings is editing the player's real file line by line. Restoring the VALUES at the
## end is not enough: a suite killed midway (or a crash) leaves the player's knobs on test
## values. So park the real file aside for the duration — every write during the suite lands in
## a throwaway settings.tres that restore deletes. Pair with snapshot_settings()/
## restore_settings_snapshot(), which put the LIVE resource back for later suites in the run.
## NOTE the deliberately un-obvious name: three older suites (UI PROPS, VISUAL LAYERS, LEAK
## CANARY) still declare their own `REAL_SETTINGS_PATH`/`REAL_SETTINGS_BAK` pair, and GDScript
## rejects a child const that shadows a parent's. Renaming here keeps them compiling; they can
## migrate onto these helpers later (todo.md).
const SETTINGS_FILE := "user://settings.tres"

## Per-SUITE backup name. Suites that don't await_siblings_except run CONCURRENTLY, so a single
## shared backup path would let one suite's park/restore swallow another's.
func _settings_bak_path() -> String:
	return "user://settings.tres.%s.testbak" % suite_name().to_lower().replace(" ", "_")

func backup_real_settings() -> void:
	# self-healing: a previously ABORTED run may have left the real file parked in this suite's
	# backup, so put it back before parking again (else that run's throwaway becomes "real")
	_move_settings_backup_home()
	if FileAccess.file_exists(SETTINGS_FILE):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(SETTINGS_FILE),
				ProjectSettings.globalize_path(_settings_bak_path()))

func restore_real_settings() -> void:
	_move_settings_backup_home()

# Drop whatever the suite wrote and move this suite's parked real file back over it.
func _move_settings_backup_home() -> void:
	var bak := _settings_bak_path()
	if not FileAccess.file_exists(bak):
		return
	if FileAccess.file_exists(SETTINGS_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(bak),
			ProjectSettings.globalize_path(SETTINGS_FILE))

## Current values of every knob whose name starts with `prefix`, so a suite can scribble on the
## live settings and put them back without naming fields (a hand-listed restore silently leaks
## whichever knob someone forgot into every later suite). Reference values are copied so the
## snapshot can't alias them.
## ⚠️ SCOPE THE PREFIX to the knobs your suite actually owns. The live PlayerSettings is SHARED
## and concurrent suites interleave — restoring a full snapshot would stomp another suite's
## in-flight knobs. "" (everything) is only safe for a suite that waits for its siblings.
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
		# copy reference values so the snapshot can't alias the live one (typed branches:
		# duplicate() on an inferred Variant is a warnings-as-errors failure)
		var value : Variant = s.get(prop_name)
		if value is Array:
			out[prop_name] = (value as Array).duplicate()
		elif value is Dictionary:
			out[prop_name] = (value as Dictionary).duplicate()
		else:
			out[prop_name] = value
	return out

## Put a snapshot_settings() capture back on the LIVE resource (later suites see the player's
## values, not this suite's). Does not touch the file — restore_real_settings() does that.
func restore_settings_snapshot(snap: Dictionary) -> void:
	var s := SettingsManager.settings
	for key : String in snap:
		s.set(key, snap[key])

## Print the suite banner + per-category failure split, then signal the aggregate runner
## (all_tests.gd) that this suite is done.
func finish() -> void:
	var total := _pass + _fail
	if _fail == 0:
		TestLog.line("============ %s: ALL %d CHECKS PASSED ============" % [suite_name(), total])
	else:
		TestLog.line("============ %s: %d passed, %d FAILED (behavior %d, implementation %d) of %d ============"
				% [suite_name(), _pass, _fail, _fail_behavior, _fail_impl, total], true)
	finished = true
	suite_finished.emit()
