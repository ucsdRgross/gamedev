class_name Pacing
extends RefCounted
## Pause-respecting timer for game code. Not wall-specific, which is why it lives here rather
## than under Scripts/Wall/.
##
## ⚠ **Returns a NODE because a `SceneTreeTimer` cannot express the contract.** A scene-tree timer
## has no node binding: `process_always` keys on the TREE's pause flag, which the wall holds on for
## the whole session, so `create_timer(secs, false)` never fires in any screen. A `Timer` child
## obeys its HOST's effective process mode — so a frozen screen's pacing freezes, a live screen's
## runs, and a screen frozen mid-wait resumes with the time it had left.

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
