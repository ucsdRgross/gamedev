class_name PropSpawner
extends RefCounted
## One scored suit card's emission plan. Owner-tunable spawn modes in one struct:
##   hoops/knives: batch_size = remaining (burst all at once, staged as a train)
##   ball/fire:    batch_size = 1, interval = 1 (fast sequential, one drop per tick)
##   million-prop edge case: max_live caps concurrency — first props move (and despawn)
##   while the spawner is still emitting; emission resumes as slots free up.

var origin : Vector3i = Vector3i.MIN   ## captured at spawn: survives source card removal
var remaining : int = 0                ## props still to emit
var batch_size : int = 1               ## emitted per due tick
var interval : int = 1                 ## ticks between emissions
var max_live : int = 32                ## concurrent live props from THIS spawner
var live : int = 0                     ## engine-maintained
var emitted : int = 0                  ## engine-maintained; passed to factory as emit_index
var factory : Callable                 ## func(emit_index: int) -> PropData  (pure)

func due(tick: int) -> bool:
	return remaining > 0 and tick % interval == 0
