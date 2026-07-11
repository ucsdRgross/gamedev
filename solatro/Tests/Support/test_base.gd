class_name SolatroTest
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

func behavior_section(title: String) -> void:
	_category = Category.BEHAVIOR
	print("\n--- [BEHAVIOR] %s ---" % title)

func implementation_section(title: String) -> void:
	_category = Category.IMPLEMENTATION
	print("\n--- [IMPLEMENTATION] %s ---" % title)

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
		print("  [PASS] ", ctx)
		return
	_fail += 1
	if cat == Category.BEHAVIOR:
		_fail_behavior += 1
	else:
		_fail_impl += 1
	var tag := "BEHAVIOR" if cat == Category.BEHAVIOR else "IMPLEMENTATION"
	printerr("[FAIL][%s] %s: %s" % [tag, suite_name(), ctx],
			"" if detail.is_empty() else (" -- " + detail))

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

## Print the suite banner + per-category failure split, then signal the aggregate runner
## (all_tests.gd) that this suite is done.
func finish() -> void:
	var total := _pass + _fail
	if _fail == 0:
		print("============ %s: ALL %d CHECKS PASSED ============" % [suite_name(), total])
	else:
		printerr("============ %s: %d passed, %d FAILED (behavior %d, implementation %d) of %d ============"
				% [suite_name(), _pass, _fail, _fail_behavior, _fail_impl, total])
	finished = true
	suite_finished.emit()
