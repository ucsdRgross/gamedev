class_name EventLog
extends RefCounted
## **THE EVENT LOG.** A timestamped, frame-numbered record of what the game DID — every light set,
## every dim transition, every prop spawn, every board mutation, every mod that fired — so that
## behaviour which can otherwise only be judged by watching can instead be READ.
##
## Built 2026-08-04 at the owner's request: *"emit some sort of logs for you to read of literally
## every single thing that happens on visual layer and their timestamp."* Widened to the data layer
## the same day, and the widening is the important part:
##
## ⚠ **ONE TIMELINE, TWO CHANNEL GROUPS — NOT TWO LOGS.** The owner asked whether the data layer
## should get its own log for headless debugging. It gets its own **group** instead, because the
## single most valuable question a log answers is *"did the data layer do X before or after the
## visual layer did Y"* — the beam-versus-board-rebuild ordering that this instrument was built to
## settle is exactly that shape. **Two logs are two timelines with no reliable way to interleave
## them, so splitting them destroys the answer.** `begin(GROUP_DATA)` gives a data-only capture
## without giving up the shared clock, and the frame counter is exact headless, so nothing about the
## data group needs the visual layer to be running.
##
## ⚠ **FRAME NUMBER IS THE GROUND TRUTH FOR "PARALLEL VS SEQUENTIAL", NOT THE TIMESTAMP.** The owner
## expected timestamps to be enough and worried they would not survive headless. Both halves of that
## are worth correcting, because the answer is better than hoped:
##
##   * A wall-clock timestamp is AMBIGUOUS. Two events 0.3 ms apart may be one frame's worth of work
##     (parallel — the player sees them together) or two frames at 3000 fps (sequential). Under the
##     act speed-up, which compresses every duration in this game, that ambiguity is the normal case
##     rather than the edge case.
##   * `Engine.get_process_frames()` is EXACT and it is what the player actually perceives: two
##     things in the same frame are one moment on screen, and two things in different frames are not.
##     **It is also frame-accurate headless**, where wall-clock is meaningless because nothing waits
##     for a vsync. So the concern about headless resolves the opposite way — the frame column is the
##     one that always works, and the microsecond column is the one to distrust.
##
## Both are recorded. Read `f=` first and `t=` only to see how long something took.
##
## ⚠ **OFF BY DEFAULT AND FREE WHEN OFF.** Every call site is `if not EventLog.enabled: return` on a
## static bool — no allocation, no string building, no file handle. It is turned on for a focused
## test and turned off again; it is NOT a thing the shipped game runs with.
## ⚠ **Build the detail string at the CALL SITE only when enabled** — `EventLog.event(&"x", "y" %
## [expensive()])` evaluates its arguments before the guard inside can reject them. The `is_on()`
## helper exists for call sites whose detail costs anything to compute.

## The master switch. Static, so a call site needs no reference to anything.
static var enabled := false

## ⚠ **A HARD CAP, BECAUSE AN UNBOUNDED LOG IS A LOG NOBODY CAN READ** (owner, 2026-08-04: *"Make
## sure log size is not massive before you read it to avoid overloading your context"*). The visual
## layer emits per-frame events, so a 60-second capture is tens of thousands of lines — enough to
## bury an agent's whole context in noise and enough to make the file itself slow to open.
##
## When the cap is hit, recording STOPS and says so. It does not ring-buffer: the START of a capture
## is the part that explains what happened, and silently discarding it to keep the tail would throw
## away the evidence while still looking like a complete log. **Truncated-with-a-warning beats
## complete-and-unreadable, and both beat quietly-missing-the-beginning.**
static var max_events := 20000
static var _overflowed := false

## One recorded event. ⚠ A typed class, NOT a `Dictionary` — this project treats warnings as errors,
## and every read out of a `Dictionary` is a `Variant`, so `int(e["f"])` does not compile. The typed
## form is also self-documenting about what a log line contains.
class Event extends RefCounted:
	## The process frame it happened on. **THE ordering truth** — see the class comment.
	var frame : int = 0
	## Microseconds since `begin()`. Informative, not authoritative.
	var usec : int = 0
	var channel : StringName = &""
	var what : String = ""
	var detail : String = ""

## Every event since `begin()`, in order. Kept in memory rather than streamed, so a run that crashes
## still yields whatever `dump()` can be persuaded out of it, and so the ordering can never be
## confused by file buffering.
static var _events : Array[Event] = []
## `Time.get_ticks_usec()` when `begin()` ran — every `t` is relative to it, because an absolute
## microsecond count since boot is unreadable and the only interesting quantity is elapsed.
static var _origin_usec : int = 0
## Channels to record. Empty = all of them. A focused test narrows this so the noise of an unrelated
## subsystem does not bury the twenty lines that matter.
static var _channels : Dictionary[StringName, bool] = {}

## Known channels. ⚠ Not an enum: a `StringName` prints itself, and the log is read by a human or an
## agent rather than parsed, so a readable tag beats an integer that needs a lookup table.
##
## VISUAL — things with pixels. Meaningless headless, where none of these fire.
const CH_SPOTLIGHT := &"spotlight"   ## the director: sections arriving, lights taken, beams retired
const CH_LIGHT := &"light"           ## the layer: light sets, dim transitions, brightness
const CH_BOARD := &"board"           ## PlayArea: rebuilds, slot binds, card visuals in and out
const CH_PROP := &"prop"             ## PropLayer: spawns, despawns, ticks
const CH_SCORE := &"score"           ## popups, banked line scores
## DATA — things with no pixels. These fire headless, which is the point of the group.
const CH_ACT := &"act"               ## the act's phases — the spine the rest is located against
const CH_MOVE := &"move"             ## board mutation: stacks moved, cards drawn, discarded, dealt
const CH_MOD := &"mod"               ## mod dispatch: which modifier fired for which hook
const CH_STATE := &"state"           ## GameData: revision bumps, undo/redo, save and resume
const CH_INPUT := &"input"           ## player actions: submit, undo, drags — what the PLAYER did

## ⚠ **THE GROUPS ARE THE ANSWER TO "SHOULD THE DATA LAYER GET ITS OWN LOG"** — it gets a group,
## sharing one clock and one timeline. See the class comment for why two logs would be worse.
const GROUP_VISUAL : Array[StringName] = [CH_SPOTLIGHT, CH_LIGHT, CH_BOARD, CH_PROP, CH_SCORE]
const GROUP_DATA : Array[StringName] = [CH_ACT, CH_MOVE, CH_MOD, CH_STATE, CH_INPUT]

## Start recording. `channels` empty means EVERYTHING — pass `GROUP_DATA` for a headless-meaningful
## capture, `GROUP_VISUAL` for a presentation-only one, or a hand-built list to chase one question.
##
## ⚠ Narrowing the channels is the FIRST remedy when a capture overflows `max_events`, and it is a
## better one than raising the cap: a log that fits is a log that gets read.
static func begin(channels: Array[StringName] = [] as Array[StringName]) -> void:
	_events = []
	_channels = {}
	_overflowed = false
	for c : StringName in channels: _channels[c] = true
	_origin_usec = Time.get_ticks_usec()
	enabled = true

static func end() -> void:
	enabled = false

## Is this channel being recorded right now? For call sites whose detail string costs something to
## build — check this BEFORE building it, since arguments evaluate before `event()` can reject them.
static func is_on(channel: StringName) -> bool:
	return enabled and (_channels.is_empty() or _channels.has(channel))

## Record one thing that happened.
##
## `what` is the event, short and stable — grep-able. `detail` is whatever makes it diagnosable.
static func event(channel: StringName, what: String, detail: String = "") -> void:
	if not enabled: return
	if not _channels.is_empty() and not _channels.has(channel): return
	if _events.size() >= max_events:
		if not _overflowed:
			_overflowed = true
			push_warning(("EventLog: hit max_events (%d) — recording STOPPED. Narrow the channels " +
					"passed to begin(), or shorten the capture; do not just raise the cap, because " +
					"the point of it is that the log stays readable.") % max_events)
		return
	var e := Event.new()
	e.frame = int(Engine.get_process_frames())
	e.usec = Time.get_ticks_usec() - _origin_usec
	e.channel = channel
	e.what = what
	e.detail = detail
	_events.append(e)

## The whole log as text, one event per line, aligned so the frame column can be read down.
##
## Format: `f=<frame> t=<ms> [channel] what — detail`
static func dump() -> String:
	var out := PackedStringArray()
	out.append("=== VISUAL LOG: %d events ===" % _events.size())
	out.append("f = process frame (THE ordering truth) · t = ms since begin()")
	for e : Event in _events:
		var line := "f=%-7d t=%9.3f  [%-9s] %s" % [
			e.frame, float(e.usec) / 1000.0, String(e.channel), e.what]
		if not e.detail.is_empty():
			line += "  —  " + e.detail
		out.append(line)
	return "\n".join(out)

## The log collapsed to one line per FRAME, which is the view that answers "parallel or sequential".
## Every event sharing a frame is one moment on screen; a frame per event is a sequence.
static func dump_by_frame() -> String:
	var out := PackedStringArray()
	var order : Array[int] = []
	var by_frame : Dictionary[int, Array] = {}
	for e : Event in _events:
		if not by_frame.has(e.frame):
			by_frame[e.frame] = [] as Array[Event]
			order.append(e.frame)
		(by_frame[e.frame] as Array[Event]).append(e)
	out.append("=== BY FRAME: %d frames carried %d events ===" % [order.size(), _events.size()])
	for f : int in order:
		var evs : Array[Event] = by_frame[f] as Array[Event]
		var names := PackedStringArray()
		for e : Event in evs: names.append(e.what)
		out.append("f=%-7d (%d) %s" % [f, evs.size(), ", ".join(names)])
	return "\n".join(out)

static func count() -> int:
	return _events.size()

## **READ THIS FIRST, ALWAYS.** A few dozen lines regardless of how long the capture ran: how big the
## log is, whether it overflowed, and a per-channel/per-event tally. It tells you which of the other
## dumps is worth opening and which would just cost you context for nothing.
##
## ⚠ The tally is the diagnostic in its own right more often than it looks. "`light_placed` 4,
## `lights_set` 4" against "`score_line` 12" says eight sections lit nothing at all, and that is a
## whole bug found without reading a single event line.
static func summary() -> String:
	var out := PackedStringArray()
	var by_channel : Dictionary[StringName, int] = {}
	var by_what : Dictionary[String, int] = {}
	var first_frame := -1
	var last_frame := -1
	for e : Event in _events:
		by_channel[e.channel] = by_channel.get(e.channel, 0) + 1
		by_what[e.what] = by_what.get(e.what, 0) + 1
		if first_frame < 0: first_frame = e.frame
		last_frame = e.frame
	out.append("=== VISUAL LOG SUMMARY ===")
	out.append("events=%d  frames=%d..%d  overflowed=%s (cap %d)"
			% [_events.size(), first_frame, last_frame, str(_overflowed), max_events])
	out.append("-- by channel --")
	for ch : StringName in by_channel:
		out.append("  %-10s %d" % [String(ch), by_channel[ch]])
	out.append("-- by event --")
	for w : String in by_what:
		out.append("  %-20s %d" % [w, by_what[w]])
	return "\n".join(out)

## ⚠ **THE VISUAL LOG'S OWN ROOT, AND IT IS GENERIC ON PURPOSE** (owner, 2026-08-04: *"visual logs
## should not be under spotlight trace since it should be 100% generic and reusable for all visual
## elements including player actions and all mods"*). The first version wrote to
## `logs/spotlight_trace/`, which quietly told every future reader that this instrument belongs to
## one feature. It does not: a `run` here is any capture — a scripted scenario, a mod being debugged,
## or the owner's own playtest.
##
## `logs/test/` (the suite's own PASS/FAIL output) is the SEPARATE sibling — see `TestLog.DIR`.
## ⚠ `logs/events/`, not `logs/visual/`: the log covers the data layer too, and a folder named for
## one of its two channel groups would mislead exactly the way `logs/spotlight_trace/` did.
const DIR := "user://logs/events/"

## Write all three views under `DIR/<run>/` and return the absolute folder path.
##
## `run` names the capture, so several can coexist and be referred to later — the whole reason the
## owner asked for a folder: *"for easy referencing during tests on specific setups by agent"*.
##
## ⚠ **`summary.log` IS WRITTEN FIRST AND IS ALWAYS SMALL.** Read it before either of the others; it
## says whether opening them is worth the context.
static func save(run: String = "run") -> String:
	var dir := "%s%s/" % [DIR, run]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_write_file(dir + "summary.log", summary())
	_write_file(dir + "visual_log.log", dump())
	_write_file(dir + "visual_log_by_frame.log", dump_by_frame())
	return ProjectSettings.globalize_path(dir)

static func _write_file(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
