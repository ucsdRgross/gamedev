class_name PropBurning
extends PropModifier
## Cosmetic-for-now: stamps a Burning spawner's fire stacks onto every prop it emits, so the
## visual can draw flame tips. Added by any suit whose card carries StatusBurning. Reserved as
## hook space for future fire-prop behavior; no core v1 effect reads prop.fire_stacks yet.

var stacks : int

func _init(s := 1) -> void:
	stacks = s

func on_spawned(prop: PropData, _g: Game) -> void:
	prop.fire_stacks = stacks
