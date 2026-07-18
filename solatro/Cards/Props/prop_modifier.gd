class_name PropModifier
extends RefCounted
## Behavior unit for a PropData, mirroring CardModifier's duck-typed hook idiom WITHOUT the
## inheritance — props are transient movers, never card-owned, never serialized (see
## SUIT_PROPS_PLAN "Props separate from CardModifier"). All prop behavior composes as a list
## of these on the prop, so effects survive the spawner card leaving the board.
##
## Implementable hooks (duck-typed via has_method — override only what you need):
##   on_spawned(prop: PropData, game: Game) -> void
##       Emission, once, before the prop first moves.
##   on_pass_card(prop: PropData, game: Game, card: CardData) -> void
##       PHASE 2 of a pass — the EFFECT. Skipped when a card mod negated the pass.
##   on_finish(prop: PropData, game: Game) -> void
##       Route exhausted / ballistic arrival, just before despawn.
##   reaction_for(prop: PropData, card: CardData) -> PropData.Reaction
##       Pure view hint (NONE/JUMP/SPIN/JUGGLE/BURN) for the card currently under the prop.

## Combo identity for SCORING_MATH_PLAN §15a (mirror of CardModifier.combo_key): prop score
## effects self-register at their add_line_score seam. Default: one class per mod script.
func combo_key(_hook: StringName = &"") -> String:
	var script : Script = get_script()
	return script.resource_path
