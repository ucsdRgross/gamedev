class_name TestSuite
extends Node
## Base class for every suite under res://Tests: category-tagged, non-freezing checks.

#It never uses assert(), so every failure names which KIND of test broke.

#BEHAVIOR asserts WHAT the game does - rules, outcomes, and invariants a player or the design doc
#cares about. These are the tests we want more of; a failure means the game is wrong, or a rule
#changed on purpose, in which case update the design doc and then the test.

#IMPLEMENTATION pins HOW the code currently does it: internal data structures, dispatch order,
#storage formats, pinned policies. A failure after a refactor may just mean the internals
#legitimately changed - verify the intent, then update the pin.

#Usage: override suite_name(), open groups with behavior_section() or implementation_section(),
#every check() inheriting the current category, use check_behavior() or check_impl() for a one-off
#that differs from its section, and call finish() at the end of _ready().

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

# The run's animation pacing (TestLog.speed_base_delay), applied to the live settings so no
# get_delay()-derived animation can run at the shipped 1 s. Call it again after deliberately
# slowing down to sample mid-flight motion — concurrent siblings share this object.
func apply_test_speed() -> void:
	SettingsManager.settings.base_delay = TestLog.speed_base_delay

#SUITE ORDERING - READ THIS BEFORE ADDING A SUITE THAT WAITS ON OTHERS. Most suites run
#concurrently. A few need near-exclusive access to global singletons that write to disk, and so
#wait for other suites to finish first, at the top of their _ready(), via await_siblings_except().

#⚠ THE OTHER SIDE OF THAT RULE, AND THE ONE THAT ACTUALLY BIT: waiting protects the suite that
#NEEDS the state. Nothing protects it from a suite that needs nothing and MUTATES it in passing.

#Constructing production objects has production side effects - building a Main clears the shared
#wall_info_mode as its own startup rule - and that failed WALL FOCUS, mid-await on that flag, from
#inside WALL RENDER, 2 runs in 3, naming a suite the change never touched.

#So if your fixture constructs something real, ask what it writes on the way up, and preserve and
#restore anything shared.

#⚠ THE DEADLOCK RULE: waiting is a directed dependency. If suite A waits for suite B then B
#must NOT wait for A, directly or transitively, or BOTH hang forever and the whole run never
#finishes - all_tests never quits and the log tails just stop.

#The canonical linear order, each waiter excluding every suite AFTER it plus itself: the engine and
#map suites wait for nothing, then PLAN VISUALS, INTERACTION, UI PROPS, VISUAL LAYERS, GRID LAYOUT,
#GRID VIEW, SETTINGS RANGE, E2E RUN, LEAK CANARY, WALL PAUSE.

#⚠ GRID LAYOUT joined the chain because it MEASURES THROUGH CardEnvironment.CURRENT and awaits
#frames: PlayArea._own_grid_row_height resolves its grid from get_current_game(), so a sample taken
#across an await answers about whichever board is CURRENT then.

#Concurrently, another suite took it and a two-deep row measured as a bare card height,
#indistinguishable from a row that never grew, and it failed 10 runs in 11.

#WALL PAUSE is the permanent tail: it constructs a real Wall whose _ready() sets
#get_tree().paused = true and never clears it, that persistence being what it tests, so nothing may
#run after it. It excludes nothing and every suite before it excludes "WALL PAUSE" by name.

#When you add a waiting suite: place it in this chain, pass the names of all suites that come AFTER
#it to await_siblings_except(), and add its name to the excludes of every suite BEFORE it. Never
#have two suites exclude-then-wait on each other.

#See the DEADLOCK RULE above: the excludes must be consistent across suites or the run hangs.

## Await every sibling suite to finish EXCEPT those named in `exclude_names`, and self.
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

#`ok == false` prints [WARN][PLACEHOLDER] and is counted separately: it never touches _fail, so the
#exit code, which is the failure count, is unchanged and nobody's build breaks (owner: warnings
#mean *"something in scene is still a placeholder"*, not that something is broken).

#Use it for drift that is real but deliberate, such as a colour still hardcoded in a surface whose
#art has not been made yet. Anything that is actually WRONG is a check(), not a warn.

## A PLACEHOLDER notice, not a failure.
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

#The save and load suites write and delete user://run_save/run.tres, the SAME file a real run uses.
#Rather than skip when a real save exists, which made the tests dependent on unrelated player
#state, the disk suites park the real one and restore it, so they ALWAYS run full.

#The backup uses a non-.tres suffix so has_save(), which keys on run.tres, never sees it.
const REAL_RUN_PATH := "user://run_save/run.tres"

#⚠ PER-CALLER BACKUP PATH, AND IT IS `tag` THAT MAKES IT ONE. A single shared
#run.tres.testbak lets suites that do not await_siblings_except run concurrently and park or
#restore across each other.

#One suite's restore then deletes run.tres and moves ITS backup home while another is mid-write,
#which surfaces as a missing file and a torn parse error, intermittently, in a DIFFERENT suite than
#the one at fault - which makes the whole suite banner untrustworthy.

#Pass a tag unique to the PURPOSE, not to the moment: a suite passes suite_tag(), its own name, and
#an external harness passes its own literal. Two callers sharing a tag share a backup, which is
#the bug.
static func run_bak_path(tag: String) -> String:
	return "user://run_save/run.tres.%s.testbak" % tag

#⚠ STATIC, because harnesses outside the test tree call RunManager.new_run() too, and each
#hand-rolled its own park before this was callable - one of them not at all, silently overwriting
#the player's run.
static func backup_real_save(tag: String) -> void:
#Self-healing, matching backup_real_settings(): an ABORTED earlier run may have left the real file
#parked under this tag, so put it back before parking again, or that run's throwaway save becomes
#"the real one" and the player's run is lost for good.
	restore_real_save(tag)
	if FileAccess.file_exists(REAL_RUN_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(REAL_RUN_PATH),
				ProjectSettings.globalize_path(run_bak_path(tag)))

static func restore_real_save(tag: String) -> void:
	var bak := run_bak_path(tag)
	if not FileAccess.file_exists(bak):
		return
#A test may have left its own run.tres behind: clear it before restoring the real one.
	if FileAccess.file_exists(REAL_RUN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL_RUN_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(bak),
			ProjectSettings.globalize_path(REAL_RUN_PATH))

#Its own name, so no two suites can collide. Mirrors _settings_bak_path()'s derivation, and is kept
#public so a diagnostic scene that subclasses TestSuite can use it too.

## The tag a SUITE parks under.
func suite_tag() -> String:
	return suite_name().to_lower().replace(" ", "_")

#SettingsManager writes user://settings.tres on EVERY knob write, so a suite that scribbles on the
#live PlayerSettings is editing the player's real file line by line. Restoring the VALUES at the end
#is not enough: a suite killed midway leaves the player's knobs on test values.

#So the real file is parked aside for the duration, and every write during the suite lands in a
#throwaway settings.tres that restore deletes. Pair with snapshot_settings() and
#restore_settings_snapshot(), which put the LIVE resource back for later suites in the run.

#⚠ EVERY SUITE USES THESE NOW, and a local copy must not be reintroduced: each copy hardcoded
#ONE backup path, so two suites running concurrently could park and restore across each other.
#_settings_bak_path() derives the name from the suite, which is why it is a function, not a const.
const REAL_SETTINGS_PATH := "user://settings.tres"

#Suites that do not await_siblings_except run CONCURRENTLY, so a single shared backup path would
#let one suite's park and restore swallow another's.

## Per-SUITE backup name.
func _settings_bak_path() -> String:
	return "user://settings.tres.%s.testbak" % suite_name().to_lower().replace(" ", "_")

#⚠ A SUITE GETS ITS OWN PlayerSettings, AND THE PLAYER'S FILE IS NEVER WRITTEN. Owner ruling:
#*"tests should have its own settings it tests with over range of possible settings values, that
#way tuning settings wont break tests, and tests that any setting is valid."*

#SettingsManager.isolated stops every disk write for the duration, and the suite scribbles on a
#FRESH instance rather than the player's. Nothing to restore means nothing a killed run can leave
#half-undone, which is the failure this replaced.

#The old file-parking is kept underneath purely to heal a save left by a run from before this.
func backup_real_settings() -> void:
	_move_settings_backup_home()
	SettingsManager.isolated = true

#Pair with backup_real_settings().

#⚠ CALL THIS BEFORE THE SUITE BUILDS ANYTHING, AND NEVER MID-SUITE. Swapping the resource
#replaces the object, and anything already holding the previous one keeps reading it: a live Wall
#went on consulting the settings it captured in _ready while the test wrote to another object.

#Suites that scribble on live objects want backup_real_settings() alone, which stops the disk
#writes without moving the object.

## A suite's OWN PlayerSettings, so the values it sweeps owe nothing to the player's tuning.
func use_own_settings() -> PlayerSettings:
	SettingsManager.isolated = true
	SettingsManager.settings = PlayerSettings.new()
	apply_test_speed()
	return SettingsManager.settings

func restore_real_settings() -> void:
	_move_settings_backup_home()
#⚠ Deliberately does NOT clear SettingsManager.isolated: all_tests sets it for the whole run,
#and a suite finishing must not re-open the player's file to the suites after it.
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

#A suite can scribble on the live settings and put them back without naming fields, a hand-listed
#restore silently leaking whichever knob someone forgot into every later suite. Reference values
#are copied so the snapshot cannot alias them.

#⚠ SCOPE THE PREFIX to the knobs your suite actually owns. The live PlayerSettings is SHARED
#and concurrent suites interleave, so restoring a full snapshot would stomp another suite's
#in-flight knobs. An empty prefix is only safe for a suite that waits for its siblings.

#⚠ ONLY CAPTURES @exported KNOBS. The filter below needs PROPERTY_USAGE_STORAGE, which a plain
#var does not carry, so de-exporting a knob silently drops it out of every snapshot and restore in
#the suite. wall_info_mode is deliberately a plain var and is restored by hand where it matters.

## Current values of every knob whose name starts with `prefix`.
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
#Reference values are copied so the snapshot cannot alias the live one. The branches are typed
#because duplicate() on an inferred Variant is a warnings-as-errors failure.
		var value : Variant = s.get(prop_name)
		if value is Array:
			out[prop_name] = (value as Array).duplicate()
		elif value is Dictionary:
			out[prop_name] = (value as Dictionary).duplicate()
		else:
			out[prop_name] = value
	return out

#Later suites see the player's values, not this suite's. It does not touch the file, which is
#restore_real_settings()'s job.

## Put a snapshot_settings() capture back on the LIVE resource.
func restore_settings_snapshot(snap: Dictionary) -> void:
	var s := SettingsManager.settings
	for key : String in snap:
		s.set(key, snap[key])

#⚠ EVERY `func run_*` THIS SUITE DEFINES MUST ACTUALLY BE CALLED FROM _ready. A test that is
#written but never invoked is indistinguishable from a passing one: the banner still reads ALL
#CHECKS PASSED, and nothing anywhere says the assertions never ran.

#That has happened - six planned tests shipped defined-but-unregistered and were reported as added.
#This reads the suite's own source, so a suite gets the guard by calling it rather than by anyone
#remembering.

#Name a helper `_something` rather than `run_something` to exempt it: `run_` is the entry-point
#convention this checks.
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

#It also signals the aggregate runner that this suite is done.

## Print the suite banner and the per-category failure split.
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
