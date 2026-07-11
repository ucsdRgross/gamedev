class_name PropData
extends RefCounted
## A transient data-layer prop (hoop/knife/ball/...): lives ONLY inside one scoring pass,
## NEVER serialized — a quit mid-act replays the whole act from the pre-act board
## (pending_action), so props never survive a save by design. ALL behavior lives in `mods`
## (composable PropModifiers); `kind` is a pure visual selector.

enum Reaction {NONE, JUMP, SPIN, JUGGLE, BURN}

# --- movement state: per-prop and ASYNC-MUTABLE (any hook may rewrite it mid-flight) ---
var at : Vector3i = Vector3i.MIN   ## slot currently over (MIN until first entry / after teleport)
var route : Array[Vector3i] = []   ## slots still ahead, [0] = next to enter; MUTABLE — this is
                                   ## what makes Strongman/Teleporter-style effects data writes
var countdown : int = 1            ## TICKS until the prop pops route[0]; staging/train stagger
                                   ## lives HERE, never in the route. Integer => replay-exact.
var ticks_per_slot : int = 1       ## per-prop speed: countdown reset on each entry; 1 = fastest
var done : bool = false
var pass_negated : bool = false    ## set during phase 1 of the CURRENT pass; auto-cleared

var mods : Array[PropModifier] = []   ## ALL behavior lives here (composable)
var kind : int = 0                    ## visual selector (suit index); no behavior
var fire_stacks : int = 0             ## visual flame tips (PropBurning sets it too)
var source : CardData = null          ## origin card, SUPPORTED input for future prop effects
                                      ## (must tolerate the card being off-board)

## The current tick's relocation log, injected by the tick loop each tick so teleport() can
## record (prop, from, to) for the view to blink instead of tween. Empty/ignored headless.
var reloc_sink : Array = []

# --- movement API (callable from ANY hook; the tick loop just re-reads next tick) ---

## Dodge: cancel the current pass's effect (phase 2). Notification (phase 3) still fires.
func negate_pass() -> void:
	pass_negated = true

## Instant relocation: continue traversal from `coord` along `new_route`. Recorded in the
## tick report so the view blinks/flashes instead of tweening across the board.
func teleport(coord: Vector3i, new_route: Array[Vector3i]) -> void:
	var from := at
	at = coord
	route = new_route
	reloc_sink.append([self, from, coord])

## Rewrite only the slots ahead (e.g. Strongman pushes the prop one row up: same direction,
## parallel row — build the new tail with game.row_slot_path_from(...)).
func set_route(new_route: Array[Vector3i]) -> void:
	route = new_route

## Duck-typed prop-mod dispatch, mirroring run_all_mods' idiom (not its class).
func run_mods(function: StringName, ...params: Array) -> void:
	for m in mods:
		if m.has_method(function):
			await Callable(m, function).callv(params)

## Union of the mods' view hints for the card currently under the prop (no duplicates, NONE
## dropped). View aggregates these across all props over a card each tick.
func reactions_for(card: CardData) -> Array[Reaction]:
	var out : Array[Reaction] = []
	for m in mods:
		if m.has_method(&"reaction_for"):
			var r : Reaction = m.call(&"reaction_for", self, card)
			if r != Reaction.NONE and r not in out:
				out.append(r)
	return out
