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
var _warn := 0
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
# ⚠️ THE OTHER SIDE OF THAT RULE, AND THE ONE THAT ACTUALLY BIT: waiting protects the suite that
# NEEDS the state. Nothing protects it from a suite that needs nothing and MUTATES it in passing.
# Constructing production objects has production side effects — building a `Main` clears the shared
# `wall_info_mode` (C3, its own startup rule), and that failed WALL FOCUS, mid-await on that flag,
# from inside WALL RENDER, which was only building a Main to test an unrelated debug gate. It
# failed 2 runs in 3 and named a suite the change never touched. So: if your fixture constructs
# something real, ask what it writes on the way up, and preserve/restore anything shared.
#
# ⚠️ THE DEADLOCK RULE: waiting is a directed dependency. If suite A waits for suite B, then B
# must NOT wait for A — directly OR transitively — or BOTH hang forever and the whole run never
# finishes (all_tests never quits; log tails just stop). A real deadlock shipped once because a
# new suite (VISUAL LAYERS) waited for INTERACTION while INTERACTION still waited for it.
#
# The canonical linear order (each waiter excludes every suite AFTER it, plus itself):
#     <engine/map suites: no wait>  →  INTERACTION  →  UI PROPS  →  VISUAL LAYERS  →  E2E RUN  →
#     LEAK CANARY  →  WALL PAUSE
#
# WALL PAUSE (S12) is the permanent tail: it constructs a real Wall whose _ready() sets
# get_tree().paused = true and never clears it (that persistence is what U1 tests), so nothing may
# run after it. It excludes nothing (waits for literally everyone) and every suite before it in the
# chain excludes "WALL PAUSE" by name.
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

## A PLACEHOLDER notice, not a failure. `ok == false` prints [WARN][PLACEHOLDER] and is counted
## separately: it never touches _fail, so the exit code (= failure count) is unchanged and nobody's
## build breaks (owner: warnings mean *"something in scene is still a placeholder"*, not
## something is broken). Use it for drift that is real but deliberate — a colour still hardcoded in a
## surface whose art has not been made yet. Anything that is actually WRONG is a check(), not a warn.
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

## Disk-test isolation. The save/load suites write and delete user://run_save/run.tres —
## the SAME file a real run uses. Rather than skip when a real save exists (which made the
## tests dependent on unrelated player state), the disk suites call backup_real_save(tag)
## before touching disk and restore_real_save(tag) after, so they ALWAYS run full and a real
## run is preserved. The backup uses a non-.tres suffix so has_save() (which keys on
## run.tres) never sees it.
const REAL_RUN_PATH := "user://run_save/run.tres"

## ⚠ PER-CALLER BACKUP PATH, and it is `tag` that makes it one. A single shared
## `run.tres.testbak` let suites that do not `await_siblings_except` run concurrently and park or
## restore across each other: one suite's restore deleted `run.tres` and moved ITS backup home
## while another was mid-write, which surfaced as `fuzz iter N wrote run.tres -- no file on disk`
## and a torn `Parse Error: Unterminated string`, intermittently, in a DIFFERENT suite than the one
## at fault. That made the whole suite banner untrustworthy, which is worse than any single failure.
## `_settings_bak_path()` below already derived a per-suite name for exactly this reason; this is
## the same fix for the run save.
##
## Pass a tag unique to the PURPOSE, not to the moment: a suite passes `suite_tag()` (its own name),
## an external harness passes its own literal. Two callers sharing a tag share a backup, which is
## the bug.
static func run_bak_path(tag: String) -> String:
	return "user://run_save/run.tres.%s.testbak" % tag

## ⚠ STATIC: harnesses outside the test tree (`spotlight_tool -- --trace`, `reveal_shot`) run
## `RunManager.new_run()` too, and each hand-rolled its own park before this was callable — one of
## them not at all, silently overwriting the player's run (reveal_shot.gd records the symptom).
static func backup_real_save(tag: String) -> void:
	# Self-healing, matching backup_real_settings(): an ABORTED earlier run may have left the real
	# file parked under this tag, so put it back before parking again — otherwise that run's
	# throwaway save becomes "the real one" and the player's run is lost for good.
	restore_real_save(tag)
	if FileAccess.file_exists(REAL_RUN_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_RUN_PATH),
				ProjectSettings.globalize_path(run_bak_path(tag)))

static func restore_real_save(tag: String) -> void:
	var bak := run_bak_path(tag)
	if not FileAccess.file_exists(bak):
		return
	# a test may have left its own run.tres behind — clear it before restoring the real one
	if FileAccess.file_exists(REAL_RUN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_RUN_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(bak),
			ProjectSettings.globalize_path(REAL_RUN_PATH))

## The tag a SUITE parks under — its own name, so no two suites can collide. Mirrors
## `_settings_bak_path()`'s derivation; kept public so a diagnostic scene that subclasses TestSuite
## can use it too.
func suite_tag() -> String:
	return suite_name().to_lower().replace(" ", "_")

## Settings isolation. SettingsManager writes user://settings.tres on EVERY knob
## write (on_settings_changed -> save_settings), so a suite that scribbles on the live
## PlayerSettings is editing the player's real file line by line. Restoring the VALUES at the
## end is not enough: a suite killed midway (or a crash) leaves the player's knobs on test
## values. So park the real file aside for the duration — every write during the suite lands in
## a throwaway settings.tres that restore deletes. Pair with snapshot_settings()/
## restore_settings_snapshot(), which put the LIVE resource back for later suites in the run.
##
## ⚠ **EVERY SUITE USES THESE NOW**. UI PROPS, VISUAL LAYERS and LEAK CANARY used to
## carry their own copy-pasted `REAL_SETTINGS_PATH`/`REAL_SETTINGS_BAK` pair, which forced the
## awkward `SETTINGS_FILE` name here — GDScript rejects a child const that shadows a parent's. The
## copies are gone and the const has its obvious name back. **Do not reintroduce a local pair:** the
## copies hardcoded ONE backup path each (`.testbak`, `.testbak2`, `.testbak3`), so two suites
## running concurrently could park and restore across each other; `_settings_bak_path()` below
## derives the name from the suite, which is why it is a function and not a constant.
const REAL_SETTINGS_PATH := "user://settings.tres"

## Per-SUITE backup name. Suites that don't await_siblings_except run CONCURRENTLY, so a single
## shared backup path would let one suite's park/restore swallow another's.
func _settings_bak_path() -> String:
	return "user://settings.tres.%s.testbak" % suite_name().to_lower().replace(" ", "_")

func backup_real_settings() -> void:
	# self-healing: a previously ABORTED run may have left the real file parked in this suite's
	# backup, so put it back before parking again (else that run's throwaway becomes "real")
	_move_settings_backup_home()
	if FileAccess.file_exists(REAL_SETTINGS_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_PATH),
				ProjectSettings.globalize_path(_settings_bak_path()))

func restore_real_settings() -> void:
	_move_settings_backup_home()

# Drop whatever the suite wrote and move this suite's parked real file back over it.
func _move_settings_backup_home() -> void:
	var bak := _settings_bak_path()
	if not FileAccess.file_exists(bak):
		return
	if FileAccess.file_exists(REAL_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_SETTINGS_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(bak),
			ProjectSettings.globalize_path(REAL_SETTINGS_PATH))

## Current values of every knob whose name starts with `prefix`, so a suite can scribble on the
## live settings and put them back without naming fields (a hand-listed restore silently leaks
## whichever knob someone forgot into every later suite). Reference values are copied so the
## snapshot can't alias them.
## ⚠️ SCOPE THE PREFIX to the knobs your suite actually owns. The live PlayerSettings is SHARED
## and concurrent suites interleave — restoring a full snapshot would stomp another suite's
## in-flight knobs. "" (everything) is only safe for a suite that waits for its siblings.
## ⚠ ONLY CAPTURES `@export`ed KNOBS. The filter below needs `PROPERTY_USAGE_STORAGE`, which a plain
## `var` does not carry — so de-exporting a knob silently drops it out of every snapshot/restore in
## the suite, and it then leaks across tests with nothing to say so. `wall_info_mode` is deliberately
## a plain `var` (session state, not persisted) and is restored by hand where it matters.
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

## ⚠ EVERY `func run_*` this suite defines must actually be CALLED from `_ready`.
##
## A test that is written but never invoked is indistinguishable from a passing one: the
## banner still reads ALL CHECKS PASSED, and nothing anywhere says the assertions never ran.
## That has happened — six planned tests shipped defined-but-unregistered and were reported as
## added. This reads the suite's own source, so a suite gets the guard by calling it rather
## than by anyone remembering.
##
## Name a helper `_something` rather than `run_something` to exempt it: `run_` is the
## entry-point convention this checks.
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
		if raw.begins_with("func run_"):
			defined.append(raw.substr(5, raw.find("(") - 5))
	var unregistered : Array[String] = []
	for name : String in defined:
		if not ready_body.contains(name + "("): unregistered.append(name)
	check(not defined.is_empty(), "the gate found this suite's tests at all", path)
	check(unregistered.is_empty(),
			"every run_* test defined in this suite is called from _ready",
			"never called: %s" % ", ".join(unregistered))

## Print the suite banner + per-category failure split, then signal the aggregate runner
## (all_tests.gd) that this suite is done.
func finish() -> void:
	var total := _pass + _fail
	var warned := "" if _warn == 0 else (" [%d placeholder warnings]" % _warn)
	if _fail == 0:
		TestLog.line("============ %s: ALL %d CHECKS PASSED%s ============"
				% [suite_name(), total, warned])
	else:
		TestLog.line("============ %s: %d passed, %d FAILED (behavior %d, implementation %d) of %d%s ============"
				% [suite_name(), _pass, _fail, _fail_behavior, _fail_impl, total, warned], true)
	finished = true
	suite_finished.emit()
