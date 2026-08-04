extends Node
## **THE SPOTLIGHT TRACE HARNESS** — runs ONE real submit on a REAL `GameView` with `EventLog`
## recording, then writes the log, the by-frame view, and a PNG at every transition.
##
## Built 2026-08-04 at the owner's request: *"as part of testing you should do frame checks at
## transitionary moments and take images to check working behavior, or emit some sort of logs for you
## to read of literally every single thing that happens on visual layer and their timestamp."*
##
## It exists to answer questions of the form *"why did the beams do THAT"* without asking anyone to
## watch the screen and remember. It is a DIAGNOSTIC, not a test: it asserts nothing and cannot fail.
## Its output is evidence to read.
##
## Run it (owner's editor closed, WINDOWED — a dummy renderer cannot compile the light shader, so
## headless would capture black):
##
##     <godot> --path solatro res://Tools/spotlight_trace.tscn
##
## Output lands in `user://spotlight_trace/`:
##   * `visual_log.log`          every event, `f=` frame and `t=` ms
##   * `visual_log_by_frame.log` one line per frame — **this is the parallel-vs-sequential answer**
##   * `NN_<what>.png`           the screen at each transition, named for the event that caused it
##
## ⚠ **NO MOCKS** (project rule 5): a real `RunState`, the real seeded deck, the real `GameView`, the
## real `Game`. The only thing this file supplies is the decision to press submit.

const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
## ⚠ **ALL LOGS LIVE UNDER `user://logs/`** (owner, 2026-08-04: *"saved logs should go in its own log
## folder for easy referencing during tests on specific setups by agent"*). One folder per named
## setup, so "the log from the deep-board run" is a path rather than a memory.
## ⚠ The LOGS go to `EventLog.DIR` (`user://logs/visual/<run>/`), which the log owns — this harness
## does not get to decide where the visual log lives, because it is not the only thing that writes
## one. Only the SHOTS are the harness's own, and they sit beside the logs for the same run.
const SHOT_DIR := EventLog.DIR + "spotlight_trace/"

## Captures are the expensive part (a full viewport read-back each), so they are taken on TRANSITIONS
## rather than per frame. This is the list of `what` values worth a picture.
const CAPTURE_ON : Array[StringName] = [
	&"score_line", &"lights_set", &"retire", &"dim_settled",
]

var _shots : int = 0
var _seen : int = 0
var _view : GameView = null
var _label : Label = null

func _ready() -> void:
	_prepare_dir()
	add_child(_Watchdog.new())
	_status("starting")
	# A real run on the seeded deck — the same setup the VISUAL LAYERS suite uses, so what this
	# harness watches is the same board those tests assert about.
	var run := RunManager.new_run(TestDecks.seeded_deck(), TestDecks.standard_rules())
	Main.save_info = run
	run.pending_goal = 1
	run.pending_node_id = 2
	EventLog.begin()
	_view = GAME_VIEW_SCENE.instantiate()
	add_child(_view)
	await get_tree().process_frame
	await get_tree().process_frame
	EventLog.event(EventLog.CH_ACT, "view_ready")
	var g : Game = _view.game
	_pump.call()
	await g.next()
	_view.play_area.flush_rebuild()
	await get_tree().process_frame
	EventLog.event(EventLog.CH_ACT, "board_dealt",
			"cards=%d" % _view.play_area.data_card.size())
	await _capture("board_dealt")

	# ⚠ **SCENARIO 1 IS THE EMPTY BOARD, AND IT IS A REAL SCENARIO, NOT A BLOCKER.** Submit fires
	# whenever the button is pressed regardless of what is on the board (owner, 2026-08-04), so
	# "submit with nothing placed" is a case the spotlight has to survive, not a reason to stop. What
	# it proves: an act that scores nothing must light nothing and must leave the dim down.
	_status("scenario 1/3 — empty board")
	EventLog.event(EventLog.CH_ACT, "SCENARIO empty_board")
	await _run_submit()
	# ⚠ Scenario 2 onward need cards on the board. `place_hand()` moves real hand cards to real
	# column ends through `Game.move_data_to_coord`, which is the same path the player's drag takes —
	# no mock, and the board that results is one the game could actually reach.
	_status("scenario 2/3 — one shallow row")
	EventLog.event(EventLog.CH_ACT, "SCENARIO one_shallow_row")
	await _place_hand(3, 1)
	await _run_submit()
	_status("scenario 3/3 — deep columns")
	EventLog.event(EventLog.CH_ACT, "SCENARIO deep_columns")
	await g.next()
	await _place_hand(6, 3)
	await _run_submit()
	EventLog.event(EventLog.CH_ACT, "SCENARIOS done")
	await get_tree().process_frame
	await _capture("scenarios_done")
	EventLog.end()
	_write()
	get_tree().quit(0)

## Move up to `count` cards from the hand onto the lower board, `per_col` deep per column.
## ⚠ Failures are logged and SWALLOWED: a rejected move (the board says no) is information about the
## scenario, not a reason to abandon the run — and a half-filled board still exercises the light.
func _place_hand(count: int, per_col: int) -> void:
	var g : Game = _view.game
	var placed := 0
	var col := 0
	# ⚠ THE "HAND" IS THE UPPER ZONE — there is no `GameData.hand`. Cards are played by moving them
	# from an upper column to a lower one, which is exactly what a drag does.
	for i : int in count:
		var card : CardData = null
		for uc : ArrayCardData in g.state.upper_zone:
			if uc and not uc.datas.is_empty():
				card = uc.datas[uc.datas.size() - 1]
				break
		if card == null: break
		await g.move_data_to_coord(card, Vector3i(1, col, -1), 1, true)
		placed += 1
		if placed % per_col == 0: col += 1
	_view.play_area.flush_rebuild()
	await get_tree().process_frame
	EventLog.event(EventLog.CH_BOARD, "hand_placed",
			"placed=%d board=%d" % [placed, _view.play_area.data_card.size()])

func _run_submit() -> void:
	var g : Game = _view.game
	EventLog.event(EventLog.CH_ACT, "submit_begin")
	# ⚠ `.call()` DELIBERATELY, not `await` and not a bare call. `submit()` is one long coroutine, so
	# the watcher has to run BESIDE it; `await _pump()` would block until the pump finished (it never
	# does) and a bare `_pump()` will not compile, because GDScript refuses to start a `void`
	# coroutine without a decision about its result. `Callable.call()` starts it detached, which is
	# exactly what a watcher is.
	await g.submit()
	EventLog.event(EventLog.CH_ACT, "submit_end")
	await get_tree().process_frame
	await _capture("submit_end")

## Capture on transitions WHILE the act runs. `submit()` is one long `await`, so nothing else gets a
## turn unless something is watching from a parallel coroutine — this is that watcher. It polls the
## log for new capture-worthy events and shoots one frame each.
func _pump() -> void:
	while EventLog.enabled:
		await get_tree().process_frame
		var events : Array[EventLog.Event] = EventLog._events
		while _seen < events.size():
			var e : EventLog.Event = events[_seen]
			_seen += 1
			if StringName(e.what) in CAPTURE_ON:
				await _capture(e.what)

## One PNG of the whole viewport, numbered in order so the filenames sort into a flipbook.
func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null: return
	_shots += 1
	var path := "%s%02d_%s.png" % [SHOT_DIR, _shots, tag]
	img.save_png(path)

func _prepare_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

## ⚠ **A BLANK WINDOW THAT NEVER CLOSES IS A BROKEN TOOL, EVEN WHEN THE RUN SUCCEEDS** (owner,
## 2026-08-04: *"window never closes when done and has no indication it is running anything, just
## blank screen, so I just close myself after you seem to be done"*). Two separate faults, two fixes:
##
##   * **No indication:** this label. It names the scenario in progress and the event count, so the
##     window says what it is doing rather than looking hung.
##   * **Never closes:** the harness quits itself at the end, and `_Watchdog` quits it even if the
##     run wedges. ⚠ **Neither helps when the SCRIPT ITSELF fails to parse** — then nothing runs at
##     all and the window sits blank forever. That is what the owner actually hit, and it can only be
##     bounded from OUTSIDE: always launch this with a `WaitForExit(<timeout>)` and kill the process
##     if it outlives it. A parse error in a harness cannot rescue itself.
func _status(text: String) -> void:
	if _label == null:
		_label = Label.new()
		_label.add_theme_font_size_override(&"font_size", 22)
		_label.position = Vector2(24, 24)
		_label.z_index = 4096
		add_child(_label)
	_label.text = "SPOTLIGHT TRACE\n%s\nevents=%d shots=%d" % [text, EventLog.count(), _shots]

func _write() -> void:
	var dir := EventLog.save("spotlight_trace")
	print("=== SPOTLIGHT TRACE: %d events, %d shots ===" % [EventLog.count(), _shots])
	print("logs:  " + dir)
	print("shots: " + ProjectSettings.globalize_path(SHOT_DIR))
	# The SUMMARY to stdout, not the full dump — it is the small one, and printing thousands of event
	# lines into a terminal is how a log stops being read.
	print(EventLog.summary())

## Quits no matter what, so the window cannot outlive the run. Independent of the scenario coroutine
## precisely so that a wedged `await` in there still ends the process.
class _Watchdog extends Node:
	var seconds : float = 180.0
	var _elapsed : float = 0.0
	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= seconds:
			push_error("spotlight_trace: watchdog fired after %.0fs — quitting" % seconds)
			get_tree().quit(2)
