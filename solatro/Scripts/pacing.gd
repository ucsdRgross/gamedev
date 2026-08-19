class_name Pacing
extends RefCounted
## Pause-respecting timer for game code (PLAN.md §1.6, D6, `Q75`=b) — not wall-specific, which is
## why it lives here rather than under Scripts/Wall/.
##
## ⚠ **A `SceneTreeTimer` CANNOT EXPRESS THIS CONTRACT, and that is why this returns a node.** It
## has no node binding at all: its `process_always` flag keys on the TREE's pause flag and nothing
## else. §1.6 holds `get_tree().paused = true` for the WHOLE SESSION, so `create_timer(secs, false)`
## — what this helper used to return — never fires AT ALL, in any screen, live or frozen.
## Measured with a real focused screen under the real paused tree: a `Pacing.wait()` did not fire
## inside a 1.5 s window; a `Timer` child of that same screen fired at its nominal delay, and a
## `Timer` child of an unfocused screen did not. `game.gd`'s scoring cascade awaits one of these,
## so the shipped game stalled mid-reveal forever.
##
## D6 wants "a frozen screen's pacing freezes with it"; the thing that knows whether a screen is
## frozen is that screen's own `process_mode` (`Main` flips the focused screen's root to ALWAYS and
## every other to PAUSABLE, S12). A `Timer` NODE obeys its host's effective process mode, so
## parenting the timer to the waiting node is what makes the contract true — and it also gives the
## right behaviour for free when a screen freezes MID-WAIT: the timer holds, and resumes with the
## remaining time when the screen comes back, matching L4's freeze-don't-free semantics.

## Godot rejects a `Timer.wait_time` of zero. This is the engine's floor, NOT a tunable: a caller
## asking for 0 means "next frame", and at any frame rate this delivers that.
const MIN_WAIT := 0.001

## `secs` seconds of PACING owned by `host`, which must be inside the tree — usage is
## `await Pacing.wait(self, secs).timeout`. The timer frees itself once it fires, and dies with
## `host` if `host` is freed first (a screen that goes away cancels its own pending waits).
static func wait(host: Node, secs: float) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(secs, MIN_WAIT)
	if not host.is_inside_tree():
		# A timer outside the tree never processes, which would stall the awaiting cascade
		# silently — exactly the failure this helper exists to end. Say so instead.
		push_error("Pacing.wait() host %s is not inside the tree; its timer will never fire"
				% host)
	host.add_child(timer)
	timer.timeout.connect(timer.queue_free)
	timer.start()
	return timer
