class_name Pacing
extends RefCounted
## Pause-respecting timer for game code (PLAN.md §1.6, D6, `Q75`=b) — not wall-specific, which is
## why it lives here rather than under Scripts/Wall/.
##
## ⚠ **Returns a NODE because a `SceneTreeTimer` cannot express the contract.** It has no node
## binding: `process_always` keys on the TREE's pause flag, which §1.6 holds on for the whole
## session — so `create_timer(secs, false)` never fires at all, in any screen. A `Timer` child obeys
## its host's effective process mode, which is what makes a frozen screen's pacing freeze and a live
## screen's run, and makes a screen frozen MID-WAIT resume with the time it had left (L4).
## See PICTURE_WALL.md's landmine for the same rule from the wall's side.

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
