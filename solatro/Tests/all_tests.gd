extends Node
## Root of all_tests.tscn: waits for every TestSuite child suite to finish, prints a
## grand total split by category, then QUITS with exit code = failure count (so the play
## window closes itself when the run ends — full output is preserved in the log files).
##
## Output: every suite routes its section/PASS/FAIL/banner lines (and the VISUAL LAYERS dumper
## its draw-order dumps) through TestLog, which ALWAYS tees to two log files — overwritten each
## run — and prints to the terminal per `terminal_output` below.

## Terminal verbosity for this run. ALL prints every routed line; ERRORS_ONLY prints only FAIL
## lines (both log files still receive everything either way).
enum TerminalOutput { ALL, ERRORS_ONLY }
@export var terminal_output : TerminalOutput = TerminalOutput.ALL
## Auto-close the run when every suite finishes (default on — the log files keep the full output).
## Turn OFF to keep the tree alive in the editor for live inspection of nodes after a run.
@export var close_when_done : bool = true
## The base_delay the animated suites (UI PROPS / VISUAL LAYERS / E2E) run their awaited
## animations at — near-instant by default so the whole run is fast. Raise it from the editor to
## WATCH a run (e.g. 0.2). Published to TestLog.speed_base_delay in _enter_tree (before any
## suite's _ready). Tests that sample mid-flight motion keep their own slower absolute delays.
@export_range(0.001, 1.0, 0.001) var speed_base_delay : float = 0.01

## Configure + truncate the log files in _enter_tree — this runs BEFORE any child suite's _ready
## (Godot calls _enter_tree parent-first), so the terminal mode is live and the files are opened
## exactly once before the first suite writes a line. @export values are applied before _enter_tree.
func _enter_tree() -> void:
	TestLog.begin(terminal_output == TerminalOutput.ERRORS_ONLY)
	TestLog.speed_base_delay = speed_base_delay
	TestLog.line("test logs (overwritten each run): %s" % TestLog.paths())

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
	# ⚠ THE ENGINE'S OWN ERROR STREAM COUNTS AS A FAILURE — see _scan_engine_errors().
	failed += _scan_engine_errors()
	# Placeholder warnings are reported but never affect the verdict or the exit code — they mark
	# surfaces still carrying hardcoded values, not breakage (TestSuite.warn).
	var warn_tag := "" if warned == 0 else (" [%d placeholder warnings]" % warned)
	if failed == 0:
		TestLog.line("======== ALL %d SUITES: %d CHECKS PASSED%s ========"
				% [suites.size(), passed, warn_tag])
	else:
		TestLog.line("======== ALL %d SUITES: %d passed, %d FAILED (%d behavior, %d implementation)%s ========"
				% [suites.size(), passed, failed, failed_behavior, failed_impl, warn_tag], true)
	TestLog.line("full logs: %s" % TestLog.paths())
	# Close the run when done (headless always quits for CI exit codes; in the editor this closes
	# the play window unless close_when_done is turned off for live inspection).
	if DisplayServer.get_name() == "headless" or close_when_done:
		get_tree().quit(mini(failed, 125))

## ⚠ **THE SUITE NOW FAILS ON UNEXPECTED ENGINE ERRORS, AND THIS IS THE HOLE THAT LET TWO FALSE
## GREENS THROUGH** (owner: *"suite should fail on unexpected errors in error stream so
## visible to an agent testing to immediately fix, instead of current behavior where I have to copy
## paste it to agent"*).
##
## Before this, the verdict came only from `check()` calls. Godot's own errors — emitted from C++
## straight to stderr — reached nobody: `test_output_errors.log` is `TestLog`'s OWN channel and holds
## only FAIL lines. Both of this session's false greens were exactly that shape:
##
##   * five spotlight tests ABORTING on `Nonexistent function 'is_spotlit' in base 'Nil'` — an
##     aborted test emits no failures, so the banner said PASSED with the checks simply never run;
##   * an `_on_screen()` flood of `Condition "!is_inside_tree()" is true`, thousands of lines, which
##     the owner had to paste in by hand because the run reported itself green.
##
## ⚠ **THE SOURCE IS GODOT'S OWN LOG FILE, NOT A HOOK.** GDScript cannot intercept the engine's error
## stream, but the engine mirrors it to `user://logs/godot.log` (file logging is on by default in
## debug builds) — and `godot.log` is THIS run, older sessions having been rotated to timestamped
## siblings. So the check is: read it, subtract what is deliberate, fail on the rest.
##
## ⚠ **THE ALLOWLIST IS THE WHOLE DESIGN PROBLEM.** Several suites push errors ON PURPOSE — that is
## what they assert. An allowlist that is too broad restores the blindness this exists to remove, so
## every entry names the suite that owns it and must stay a SUBSTRING match, never a prefix wildcard.
const ENGINE_ERROR_ALLOW : Array[String] = [
	"Palette index",              # test_palette asserts the clamp WARNS — it is the behaviour
	"LeakSentinel:",              # test_leak_canary deliberately abandons cards and reports it
	"Condition \"p_index",        # bounds asserts inside deliberate degenerate-input suites
	"comparator_buckets:",        # test_comparator asserts a grouping rule's invented card is REFUSED
	"ProfileManagerClass:",       # test_wall_profile (R6) asserts a corrupt profile file REPORTS
	"user://profile.tres",       # test_wall_profile (R6) also triggers ResourceLoader's OWN native
	                              # parse-failure errors (3 lines) on the deliberately corrupted
	                              # file, on top of ProfileManagerClass's single deliberate one
]

## GAP-007 (owner option b): each `ENGINE_ERROR_ALLOW` entry is permitted up to this many lines
## over the WHOLE run — a further occurrence still fails it. Every number below was read off an
## ACTUAL green run, twice, and was identical both times; matching is first-fragment-wins in
## `ENGINE_ERROR_ALLOW`'s own order, which is why the single line both "ProfileManagerClass:" and
## "user://profile.tres" match (the deliberate push_error interpolates the path into its own text)
## is attributed to "ProfileManagerClass:" and not double-counted here.
## ⚠ `-1` = uncounted, kept ONLY for "comparator_buckets:" — its true count is driven by
## `Tests/Engine/test_mod_fuzz.gd`'s randomized seed and measured genuinely unstable run to run
## (703 vs 310 on two back-to-back green runs). Forcing a flaky entry to a number would trade a
## known blind spot for a flaky gate, which is a worse failure mode than the one GAP-007 closes.
const ENGINE_ERROR_EXPECT : Dictionary[String, int] = {
	"Palette index": 2,
	"LeakSentinel:": 1,
	"Condition \"p_index": 0,
	"comparator_buckets:": -1,
	"ProfileManagerClass:": 1,
	"user://profile.tres": 3,
}

## Returns the number of unexpected engine errors, and prints them so the agent reading the run has
## the actual text rather than a count.
func _scan_engine_errors() -> int:
	var text := FileAccess.get_file_as_string("user://logs/godot.log")
	if text.is_empty():
		# Not fatal, but say so — a silent zero here would be indistinguishable from a clean run, and
		# that is the exact failure mode this function exists to end.
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
	# ⚠ Only ever printed when there ARE errors — the owner asked for the stream in the output
	# "basically only if error", and a clean run has nothing to say beyond the one line above.
	TestLog.line("======== %d UNEXPECTED ENGINE ERRORS ========" % bad.size(), true)
	# Deduplicated with counts: the flood that started all this was one bug repeated thousands of
	# times, and printing it thousands of times would bury every other error under it.
	var seen : Dictionary[String, int] = {}
	var order : Array[String] = []
	for line : String in bad:
		if not seen.has(line): order.append(line)
		seen[line] = seen.get(line, 0) + 1
	for line : String in order:
		TestLog.line("  x%-5d %s" % [seen[line], line], true)
	return order.size()
