class_name CountingEnvironment
extends FakeEnvironment
## A harness environment that counts hook dispatches, per hook name.

#It counts at the ENVIRONMENT and not inside a rule, because the claim it exists to prove is about
#a board carrying NO rule: there is no rule to count inside. ⚠ Add it as a child and free it, like
#every FakeEnvironment.
var dispatches : Dictionary[StringName, int] = {}

func _note_mod_fired(mod: CardModifier, function: StringName,
		feeds_act_combo := true, counts_as_activation := false) -> void:
	dispatches[function] = dispatches.get(function, 0) + 1
	super(mod, function, feeds_act_combo, counts_as_activation)

## Every dispatch of every hook.
func total() -> int:
	var n := 0
	for hook : StringName in dispatches: n += dispatches[hook]
	return n
