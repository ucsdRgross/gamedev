extends Node
## Root of all_tests.tscn: waits for every TestSuite child to finish, totals, then QUITS.

#The exit code is the failure count, so the play window closes itself when the run ends and the
#full output is preserved in the log files.

#Every suite routes its section, PASS, FAIL and banner lines through TestLog, which ALWAYS tees to
#two log files, overwritten each run, and prints to the terminal per `terminal_output` below.

#ALL prints every routed line; ERRORS_ONLY prints only FAIL lines. Both log files still receive
#everything either way.

## Terminal verbosity for this run.
enum TerminalOutput { ALL, ERRORS_ONLY }
@export var terminal_output : TerminalOutput = TerminalOutput.ALL
#Turn it OFF to keep the tree alive in the editor for live inspection of nodes after a run.

## Auto-close the run when every suite finishes; the log files keep the full output.
@export var close_when_done : bool = true
#Near-instant by default so the whole run is fast. Raise it from the editor to WATCH a run, at
#0.2 say. Published to TestLog.speed_base_delay in _enter_tree, before any suite's _ready, and
#tests that sample mid-flight motion keep their own slower absolute delays.

## The base_delay the animated suites run their awaited animations at.
@export_range(0.001, 1.0, 0.001) var speed_base_delay : float = 0.01

var _run_start_msec := 0
# The selection, passed to the scene after `--`: `@logic` for the tier group, anything else a
# case-insensitive substring of the NODE name (a scene's filename is not always its script's name —
# test_scoring.gd lives in test_score.tscn). Empty = every suite, the only run that can be green.
var _filter : PackedStringArray = []
var _total_suites := 0

# ⚠ Pruning runs in _enter_tree and frees IMMEDIATELY: by _ready every child has already run, and
# queue_free() defers past the child's own _ready so the suite runs anyway. The child list is
# duplicated because it is mutated mid-propagation. Removal only — never a reorder.

#Godot calls _enter_tree parent-first, so this runs BEFORE any child suite's _ready: the terminal
#mode is live and the files are opened exactly once before the first suite writes a line. @export
#values are applied before _enter_tree.

#⚠ SettingsManager.isolated IS SET HERE TOO, NOT IN _ready(). _ready() fires bottom-up, so a
#suite whose own backup_real_settings() or use_own_settings() call is not the very first line of
#its _ready has a real window in which a knob write reaches the player's settings.tres.

#_enter_tree fires parent-first, before ANY child suite exists, so setting it here closes that
#window completely instead of only covering suites that remember to isolate before their writes.

## Configure and truncate the log files.
func _enter_tree() -> void:
	_run_start_msec = Time.get_ticks_msec()
	SettingsManager.isolated = true
	_total_suites = get_child_count()
	_filter = OS.get_cmdline_user_args()
	TestLog.begin(terminal_output == TerminalOutput.ERRORS_ONLY)
	TestLog.speed_base_delay = speed_base_delay
	TestLog.line("test logs (overwritten each run): %s" % TestLog.paths())
	if not _filter.is_empty():
		for child : Node in get_children().duplicate():
			if _matches_filter(child): continue
			remove_child(child)
			child.free()
		TestLog.line("======== %s ========" % _filter_scope(get_child_count()))
		_print_filter_warning()

# A tier is a GROUP on the suite node, so the scene stays the registry it already is everywhere
# else: a list of tier members in this script would drift the moment a suite is added. Groups are
# set at instantiation, so they are readable here, before any child has entered the tree.
func _matches_filter(suite: Node) -> bool:
	for pattern : String in _filter:
		if pattern.begins_with("@"):
			if suite.is_in_group(pattern.substr(1)): return true
		elif String(suite.name).to_lower().contains(pattern.to_lower()): return true
	return false

# Selected-of-total, named in the opening line and again in the grand total, so a filtered run's
# transcript never contains the sentence "ALL N SUITES: ... CHECKS PASSED" at either end.
func _filter_scope(kept: int) -> String:
	return "FILTERED %d of %d SUITES [%s]" % [kept, _total_suites, " ".join(_filter)]

# ⚠ A filtered run must be unable to LOOK green: the suite count is the load-failure detector and
# a filter voids it. Printed at both ends of the log, because neither end is read alone.
func _print_filter_warning() -> void:
	TestLog.line("⚠ FILTERED RUN — NOT A GREEN SIGNAL FOR THE PROJECT. The unmatched suites never "
			+ "ran, so the suite count cannot detect a suite that failed to load, and nothing here "
			+ "says the project is green. Only the full unfiltered run is a verdict.")

# Waits for every suite to report, then prints the grand total and the finish-time ranking — a
# run's length is its LAST FINISHER, not the sum of the durations, because suites overlap.
func _ready() -> void:
	var suites: Array[TestSuite] = []
	for child in get_children():
		if child is TestSuite:
			suites.append(child)
	for suite in suites:
		if not suite.finished:
			await suite.suite_finished
	var passed := 0
	var failed := 0
	var failed_behavior := 0
	var failed_impl := 0
	var warned := 0
	for suite in suites:
		passed += suite._pass
		failed += suite._fail
		failed_behavior += suite._fail_behavior
		failed_impl += suite._fail_impl
		warned += suite._warn
	TestLog.line("")
#⚠ THE ENGINE'S OWN ERROR STREAM COUNTS AS A FAILURE - see _scan_engine_errors().
	failed += _scan_engine_errors()
#Placeholder warnings are reported but never affect the verdict or the exit code: they mark
#surfaces still carrying hardcoded values, not breakage.
	var warn_tag := "" if warned == 0 else (" [%d placeholder warnings]" % warned)
	var scope := "ALL %d SUITES" % suites.size()
	if not _filter.is_empty():
		scope = _filter_scope(suites.size())
	if failed == 0:
		TestLog.line("======== %s: %d CHECKS PASSED%s ========" % [scope, passed, warn_tag])
	else:
		TestLog.line("======== %s: %d passed, %d FAILED (%d behavior, %d implementation)%s ========"
				% [scope, passed, failed, failed_behavior, failed_impl, warn_tag], true)
	if not _filter.is_empty():
		_print_filter_warning()
	var ranked : Array[TestSuite] = suites.duplicate()
	ranked.sort_custom(func(a: TestSuite, b: TestSuite) -> bool:
			return a.finish_msec > b.finish_msec)
	TestLog.line("---- suites by finish time (seconds since run start), slowest tail first ----")
	for suite : TestSuite in ranked:
		TestLog.line("  finished %7.2fs   took %6.2fs   %s" % [
				float(suite.finish_msec - _run_start_msec) / 1000.0,
				float(suite.elapsed_msec) / 1000.0, suite.suite_name()])
	TestLog.line("full logs: %s" % TestLog.paths())
#Close the run when done. Headless always quits for CI exit codes; in the editor this closes the
#play window unless close_when_done is turned off for live inspection.
	if DisplayServer.get_name() == "headless" or close_when_done:
		get_tree().quit(mini(failed, 125))

#⚠ THE SUITE FAILS ON UNEXPECTED ENGINE ERRORS (owner: *"suite should fail on unexpected errors
#in error stream so visible to an agent testing to immediately fix, instead of current behavior
#where I have to copy paste it to agent"*).

#A verdict from check() calls alone reaches none of Godot's own errors, which are emitted from C++
#straight to stderr, while test_output_errors.log is TestLog's OWN channel and holds only FAIL
#lines. Two false greens had exactly that shape.

#One was five spotlight tests ABORTING on a nonexistent function, an aborted test emitting no
#failures so the banner said PASSED with the checks never run. The other was a flood of thousands
#of "Condition !is_inside_tree() is true" lines the owner had to paste in by hand.

#⚠ THE SOURCE IS GODOT'S OWN LOG FILE, NOT A HOOK. GDScript cannot intercept the engine's error
#stream, but the engine mirrors it to user://logs/godot.log, which is THIS run - older sessions are
#rotated to timestamped siblings. So the check is: read it, subtract what is deliberate, fail on the rest.

#⚠ THE ALLOWLIST IS THE WHOLE DESIGN PROBLEM. Several suites push errors ON PURPOSE, that being
#what they assert. An allowlist that is too broad restores the blindness this exists to remove, so
#every entry names the suite that owns it and must stay a SUBSTRING match, never a prefix wildcard.
const ENGINE_ERROR_ALLOW : Array[String] = [
	"Palette index",
	"LeakSentinel:",
	"Condition \"p_index",
	"comparator_buckets:",
	"ProfileManagerClass:",
	"user://profile.tres",
]

#Each ENGINE_ERROR_ALLOW entry is permitted up to this many lines over the WHOLE run; a further
#occurrence still fails it. Every number below was read off an ACTUAL green run, twice, and was
#identical both times.

#Matching is first-fragment-wins in ENGINE_ERROR_ALLOW's own order, which is why the single line
#both "ProfileManagerClass:" and "user://profile.tres" match - the deliberate push_error
#interpolates the path into its own text - is attributed to the first and not double-counted.

#⚠ -1 means uncounted and is kept ONLY for "comparator_buckets:": its true count is driven by
#test_mod_fuzz.gd's randomized seed and measured genuinely unstable run to run, 703 against 310 on
#two back-to-back green runs. Forcing a flaky entry to a number trades a blind spot for a flaky gate.
const ENGINE_ERROR_EXPECT : Dictionary[String, int] = {
	"Palette index": 2,
	"LeakSentinel:": 1,
	"Condition \"p_index": 0,
	"comparator_buckets:": -1,
	"ProfileManagerClass:": 1,
	"user://profile.tres": 3,
}

#It prints them too, so the agent reading the run has the actual text rather than a count.

## Returns the number of unexpected engine errors.
func _scan_engine_errors() -> int:
	var text := FileAccess.get_file_as_string("user://logs/godot.log")
	if text.is_empty():
#Not fatal, but say so: a silent zero here would be indistinguishable from a clean run, and that
#is the exact failure mode this function exists to end.
		TestLog.line("[engine-errors] SKIPPED — user://logs/godot.log unreadable "
				+ "(file logging off?). This run's engine stream was NOT checked.", true)
		return 0
	var bad : Array[String] = []
	var match_counts : Dictionary[String, int] = {}
	for raw : String in text.split("\n"):
		var line := raw.strip_edges()
		if not (line.begins_with("ERROR:") or line.begins_with("SCRIPT ERROR:")): continue
		var matched := ""
		for frag : String in ENGINE_ERROR_ALLOW:
			if frag in line:
				matched = frag
				break
		if matched.is_empty():
			bad.append(line)
			continue
		match_counts[matched] = match_counts.get(matched, 0) + 1
		var expect : int = ENGINE_ERROR_EXPECT.get(matched, 0)
		if expect >= 0 and match_counts[matched] > expect: bad.append(line)
	if bad.is_empty():
		TestLog.line("[engine-errors] clean — 0 unexpected lines in the engine stream")
		return 0
#⚠ Only ever printed when there ARE errors - the owner asked for the stream in the output
#"basically only if error", and a clean run has nothing to say beyond the one line above.
	TestLog.line("======== %d UNEXPECTED ENGINE ERRORS ========" % bad.size(), true)
#Deduplicated with counts: the flood that started all this was one bug repeated thousands of times,
#and printing it thousands of times would bury every other error under it.
	var seen : Dictionary[String, int] = {}
	var order : Array[String] = []
	for line : String in bad:
		if not seen.has(line): order.append(line)
		seen[line] = seen.get(line, 0) + 1
	for line : String in order:
		TestLog.line("  x%-5d %s" % [seen[line], line], true)
	return order.size()
