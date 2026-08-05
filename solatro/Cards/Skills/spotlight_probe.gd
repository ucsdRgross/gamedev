class_name SpotlightProbe
extends CardModifierSkill
## **A SKILL THAT DOES NOTHING, SO THE MOMENTARY SPOTLIGHT HAS SOMETHING TO ANNOUNCE.**
##
## ⚠ **IT EXISTS BECAUSE S15 IS OTHERWISE INVISIBLE IN THE SHIPPED GAME, AND THAT IS NOT A BUG IN
## S15.** `CardEnvironment.spotlight_cued` is `Q246`=(a)-filtered to skills that implement
## `on_spotlight`, and until this class was added **exactly one** in the whole game did —
## `Cards/Skills/Rules/zone_adder.gd`, a RULES-stage card, which lives in a rules collection and has
## no `CardVisual` on the board. `SpotlightDirector._on_cued` therefore looked it up, found no visual,
## and drew nothing: the cue could never appear. This is the board-stage skill the filter was always
## meant to be selecting.
##
## ⚠ **THE HOOK IS DELIBERATELY EMPTY, AND THE EMPTINESS IS THE POINT.** `Q246` gates the cue on
## *having something to announce*, not on doing something — so a hook with no body is the cleanest
## possible test of the cue itself: anything it did would be a second thing that could be what you are
## actually seeing on screen. `on_unspotlight` is here for the same reason — without it the card would
## announce on the way in and stay silent on the way out, which is not the shape the chart describes.
##
## ⚠ **NOT A GAMEPLAY CARD.** It scores nothing, is never a combo class (so it cannot move patience or
## an act's bookkeeping), and exists to be looked at. Reach it from the DEBUG BAR's *Cue* button
## (`GameView._on_debug_cue`), which stamps it onto an uncovered board card and re-runs the sweep.

func get_str() -> String: return TRANSLATION.find('SKILL_SPOTLIGHT_PROBE')
func get_description() -> String: return TRANSLATION.find('SKILL_SPOTLIGHT_PROBE_DESCRIPTION')
func get_frame() -> int: return 0

## Never a combo class — the same reason `SpotlightTestSkill` and `ZoneAdder` declare this. A probe
## that shifted the score would change the act it is supposed to be observing.
func combo_key(_hook: StringName = &"") -> String: return ""

## The whole reason this class exists: its PRESENCE passes `Q246`'s filter. Intentionally empty.
func on_spotlight() -> void:
	pass

## Present so the card announces on the way OUT as well as in — chart T's edge is two-sided.
func on_unspotlight() -> void:
	pass
