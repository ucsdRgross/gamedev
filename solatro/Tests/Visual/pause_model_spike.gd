extends Node2D
# res://Tests/Visual/pause_model_spike.gd
# ==============================================================================
# PAUSE-MODEL SPIKE (owner question, pre-S12) -- measures, does NOT decide, whether §1.6's shipped
# model ("the wall stays paused permanently; PROCESS_MODE_ALWAYS keeps the wall/camera alive") or
# the owner's proposed alternative ("the wall is never paused; screens default to
# PROCESS_MODE_DISABLED instead") is safe -- by running real Godot behaviour and printing what
# actually happened, per repo rule 4 ("verify by eye / measure it", not by reasoning about it).
# D6, Q75, QR6.
#
# Four questions, in order:
#   Q-A  paused=true,  PROCESS_MODE_ALWAYS    node -- does _process keep running?
#   Q-B  paused=false, PROCESS_MODE_DISABLED  node -- does _process stop?
#   Q-C  paused=false, PROCESS_MODE_DISABLED  node -- does a SceneTreeTimer THAT NODE'S OWN
#        script created BEFORE being disabled still fire, and does the await on it still resume?
#        THE DECISIVE ONE: this is the question that tells us whether disabling a screen node
#        actually stops its in-flight waits, or only stops its per-frame _process.
#   Q-D  paused=true,  PROCESS_MODE_PAUSABLE  node (the ordinary default) -- does a timer created
#        via Pacing.wait fire, and does a bare get_tree().create_timer fire? Run twice: once
#        created WHILE already paused, once already counting and THEN paused mid-flight (the
#        latter is TEST_PLAN.md U5's own fixture shape).
#
# Not a repeatable regression test -- a one-off diagnostic, run windowed by hand:
#     <console exe> --path solatro res://Tests/Visual/pause_model_spike.tscn
# Prints one PAUSE_MODEL_SPIKE line per question, then quits. Deliberately NOT in all_tests.tscn:
# it pauses/unpauses the GLOBAL tree, which is unsafe inside the shared suite run -- the exact trap
# ASSUMPTIONS.md's S10 entry on TestWallRender already hit and documented.
# ==============================================================================

## Real-time settle: long enough to be unambiguous against a 60fps frame, short enough the spike
## stays fast. The wait itself uses an explicit process_always=true timer, uncontested Godot
## behaviour that S1's pause_time_spike already relies on to wait 20 REAL seconds while paused.
const SETTLE_SECS := 0.3

func _ready() -> void:
	await _question_a()
	await _question_b()
	await _question_c()
	await _question_d_created_while_paused()
	await _question_d_paused_mid_flight()
	print("PAUSE_MODEL_SPIKE done")
	get_tree().quit()

## A plain per-frame counter, reused for Q-A and Q-B -- the only difference between the two
## questions is process_mode and the tree's own paused state at the time.
class Ticker extends Node2D:
	var ticks := 0
	func _process(_delta: float) -> void:
		ticks += 1

## Q-A: get_tree().paused = true, node PROCESS_MODE_ALWAYS -- does it keep processing? (This is
## the claim §1.6 rests on: the wall/camera are not frozen by the global pause flag.)
func _question_a() -> void:
	var node := Ticker.new()
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(node)
	get_tree().paused = true
	await get_tree().create_timer(SETTLE_SECS, true).timeout
	get_tree().paused = false
	print(("PAUSE_MODEL_SPIKE Q-A: paused=true, PROCESS_MODE_ALWAYS node ticked %d times over "
			+ "%.2fs -- %s") % [node.ticks, SETTLE_SECS,
			"KEPT PROCESSING" if node.ticks > 0 else "DID NOT PROCESS"])
	node.queue_free()

## Q-B: tree NOT paused, node PROCESS_MODE_DISABLED -- does _process stop?
func _question_b() -> void:
	var node := Ticker.new()
	node.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(node)
	await get_tree().create_timer(SETTLE_SECS, true).timeout
	print(("PAUSE_MODEL_SPIKE Q-B: paused=false, PROCESS_MODE_DISABLED node ticked %d times over "
			+ "%.2fs -- %s") % [node.ticks, SETTLE_SECS,
			"STOPPED" if node.ticks == 0 else "KEPT PROCESSING"])
	node.queue_free()

## A node whose OWN script starts a bare get_tree().create_timer() await while still enabled, so
## the caller can disable the node afterward and observe whether the in-flight await still
## resumes -- Q-C's whole point.
class TimerNodeC extends Node2D:
	var resumed := false
	func start() -> void:
		await get_tree().create_timer(0.3).timeout   # default process_always = true
		resumed = true

## Q-C -- THE DECISIVE ONE: tree NOT paused, node PROCESS_MODE_DISABLED. A SceneTreeTimer the
## node's OWN script created BEFORE being disabled -- does it still fire, and does the await on it
## still resume?
func _question_c() -> void:
	var node := TimerNodeC.new()
	add_child(node)
	node.start()                                       # await starts while node is still enabled
	node.process_mode = Node.PROCESS_MODE_DISABLED      # disabled AFTER the timer/await exists
	await get_tree().create_timer(SETTLE_SECS * 2.0, true).timeout
	print(("PAUSE_MODEL_SPIKE Q-C: paused=false, PROCESS_MODE_DISABLED node's OWN "
			+ "get_tree().create_timer() await resumed=%s -- %s")
			% [str(node.resumed), "TIMER FIRED AND THE AWAIT RESUMED" if node.resumed
					else "TIMER DID NOT FIRE / AWAIT DID NOT RESUME"])
	node.queue_free()

## A node whose OWN script starts BOTH a Pacing.wait() and a bare get_tree().create_timer() await,
## so Q-D can compare the two under an identical paused tree. Records the msec timestamp each
## fired at, relative to a start time the caller supplies.
class TimerNodeD extends Node2D:
	var pacing_fired := false
	var bare_fired := false
	var pacing_fired_at_msec := -1
	var bare_fired_at_msec := -1
	func start() -> void:
		_run_pacing()
		_run_bare()
	func _run_pacing() -> void:
		await Pacing.wait(self, 0.3).timeout      # process_always = false -- the pause-respecting helper S6 built
		pacing_fired = true
		pacing_fired_at_msec = Time.get_ticks_msec()
	func _run_bare() -> void:
		await get_tree().create_timer(0.3).timeout   # default process_always = true
		bare_fired = true
		bare_fired_at_msec = Time.get_ticks_msec()

## Q-D, scenario 1: tree is ALREADY paused when the timers are CREATED.
func _question_d_created_while_paused() -> void:
	var node := TimerNodeD.new()
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(node)
	var start_msec := Time.get_ticks_msec()
	get_tree().paused = true
	node.start()
	await get_tree().create_timer(SETTLE_SECS * 2.0, true).timeout   # 0.6s, STILL paused throughout
	print(("PAUSE_MODEL_SPIKE Q-D1 (created WHILE paused; still paused at +%.2fs): "
			+ "Pacing.wait fired=%s (at +%dms), bare create_timer fired=%s (at +%dms)")
			% [SETTLE_SECS * 2.0, str(node.pacing_fired),
			node.pacing_fired_at_msec - start_msec if node.pacing_fired else -1,
			str(node.bare_fired), node.bare_fired_at_msec - start_msec if node.bare_fired else -1])
	get_tree().paused = false
	node.queue_free()
	await get_tree().create_timer(0.1, true).timeout

## Q-D, scenario 2: the timers are ALREADY COUNTING, THEN the tree gets paused mid-flight -- the
## ordinary real-world shape (a wall transition pausing everything while a screen's own animation
## is already in progress), and TEST_PLAN.md U5's own fixture order ("paused = true, await
## Pacing.wait(0.1) with a 0.5s escape -> assert it did NOT fire").
func _question_d_paused_mid_flight() -> void:
	var node := TimerNodeD.new()
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(node)
	var start_msec := Time.get_ticks_msec()
	node.start()                                        # both timers start counting, UNPAUSED
	await get_tree().create_timer(0.05, true).timeout    # let them actually start counting first
	get_tree().paused = true
	await get_tree().create_timer(SETTLE_SECS * 2.0, true).timeout   # watch while STILL paused
	print(("PAUSE_MODEL_SPIKE Q-D2 (already counting, THEN paused; still paused at +%dms): "
			+ "Pacing.wait fired=%s (at +%dms), bare create_timer fired=%s (at +%dms)")
			% [Time.get_ticks_msec() - start_msec, str(node.pacing_fired),
			node.pacing_fired_at_msec - start_msec if node.pacing_fired else -1,
			str(node.bare_fired), node.bare_fired_at_msec - start_msec if node.bare_fired else -1])
	get_tree().paused = false
	node.queue_free()
