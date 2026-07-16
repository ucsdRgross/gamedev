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
	for suite in suites:
		passed += suite._pass
		failed += suite._fail
		failed_behavior += suite._fail_behavior
		failed_impl += suite._fail_impl
	TestLog.line("")
	if failed == 0:
		TestLog.line("======== ALL %d SUITES: %d CHECKS PASSED ========" % [suites.size(), passed])
	else:
		TestLog.line("======== ALL %d SUITES: %d passed, %d FAILED (%d behavior, %d implementation) ========"
				% [suites.size(), passed, failed, failed_behavior, failed_impl], true)
	TestLog.line("full logs: %s" % TestLog.paths())
	# Close the run when done (headless always quits for CI exit codes; in the editor this closes
	# the play window unless close_when_done is turned off for live inspection).
	if DisplayServer.get_name() == "headless" or close_when_done:
		get_tree().quit(mini(failed, 125))
