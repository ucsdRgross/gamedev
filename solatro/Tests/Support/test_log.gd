class_name TestLog
extends RefCounted
## Central sink for test output so a run can (a) tee everything to log files and (b) throttle the
## terminal. Every TestSuite routes its section headers, PASS/FAIL lines, and banners through here;
## the VISUAL LAYERS dumper routes its (large) draw-order dumps here too. all_tests.gd calls
## begin() once at the start of a run to pick the terminal verbosity and OVERWRITE both log files.
##
##   test_output_all.log    — every routed line (PASS + FAIL + sections + dumps)
##   test_output_errors.log — FAIL lines only
##
## Terminal: ALL prints everything; ERRORS_ONLY prints only FAIL lines (files still get everything).

const ALL_PATH := "user://test_output_all.log"
const ERR_PATH := "user://test_output_errors.log"

static var terminal_errors_only := false
## The base_delay animated suites run at — set once by all_tests.gd's @export speed_base_delay
## (editor-tunable, near-instant default) before any suite's _ready; suites read this instead of
## a per-suite FAST_DELAY constant. Tests that deliberately SLOW DOWN to sample mid-flight motion
## keep their own absolute local delays and must not read this.
static var speed_base_delay : float = 0.05
static var _all_file : FileAccess = null
static var _err_file : FileAccess = null
static var _started := false

## Open (truncate) both log files and set the terminal mode. Safe to call again — reopens fresh.
static func begin(errors_only: bool) -> void:
	terminal_errors_only = errors_only
	LeakSentinel.test_mode = true  # suites abandon cards on purpose — keep the sentinel quiet
	_all_file = FileAccess.open(ALL_PATH, FileAccess.WRITE)
	_err_file = FileAccess.open(ERR_PATH, FileAccess.WRITE)
	_started = true

## Absolute on-disk paths, for printing where the logs went.
static func paths() -> String:
	return "%s , %s" % [ProjectSettings.globalize_path(ALL_PATH),
			ProjectSettings.globalize_path(ERR_PATH)]

## Route one line. `is_error` marks it a FAIL (goes to the errors file + always shows in terminal).
static func line(text: String, is_error: bool = false) -> void:
	if not _started:
		begin(false)   # a suite logged before begin() (e.g. run straight from its own scene)
	if _all_file:
		_all_file.store_line(text)
		_all_file.flush()
	if is_error and _err_file:
		_err_file.store_line(text)
		_err_file.flush()
	if is_error:
		printerr(text)
	elif not terminal_errors_only:
		print(text)
