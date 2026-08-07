@abstract class_name CardModifierStatus
extends CardModifier
## A fourth kind of CardModifier (alongside skill / type / stamp): a self-affecting,
## stackable status effect stored in an Array on CardData. Plugs into the existing
## run_all_mods / run_card_mods dispatch with no new machinery — statuses self-scope every
## targeted hook with `if target != data: return`, exactly like the other mods.

## Stack count. Setter removes the status from its card at <= 0 (expiry) and otherwise
## fires data_changed so the card visual refreshes.
@export_storage var stacks : int = 1:
	set(value):
		stacks = value
		fit_to_stacks()
		if stacks <= 0:
			if data: data.remove_status(self)
		elif data:
			data.data_changed.emit()

## Statuses of the same class merge (stacks add) instead of coexisting. Override to return
## false for statuses that want independent instances (e.g. a future StatusSeal).
func can_merge_with(other: CardModifierStatus) -> bool:
	return get_script() == other.get_script()

## Fold `other` into this status — the merge can_merge_with just approved. Default is stacks add.
## Statuses carrying PER-STACK data override this to extend that data in the SAME operation:
## adding stacks without extending it breaks the size invariant and silently loses the incoming
## stacks' provenance.
func merge_from(other: CardModifierStatus) -> void:
	stacks += other.stacks

## Re-align any per-stack data with `stacks`. Called from the stacks setter, so it covers every
## path that can change the count — a drop, a merge, a decay, and loading a save written before
## the per-stack data existed. Base statuses carry none, so this is a no-op for them.
func fit_to_stacks() -> void:
	pass

## Absorb context from the prop that dropped this status. Default: nothing. Statuses carrying
## per-stack provenance override it — a juggled ball must remember the fire level it was spawned
## with, because a ball's flame is the BALL's own effect and is never read from its card's
## Burning (owner rulings 3 and 21).
func on_dropped_by(_prop: PropData) -> void:
	pass

## Statuses work anywhere on their own card — no rules-deck requirement (unlike skills).
func is_spotlit() -> bool:
	return stacks > 0

## Fresh instance of `script` carrying `n` stacks. Script-based (not a polymorphic static:
## GDScript static funcs have no `self`), so Phase 3 can do
## CardModifierStatus.stacked(StatusJuggling, 1) or hold the Script and call it.
static func stacked(script: GDScript, n := 1) -> CardModifierStatus:
	var status : CardModifierStatus = script.new()
	status.stacks = n
	return status

## Chainable stack setter for building test/board statuses inline.
func with_stacks(n: int) -> CardModifierStatus:
	stacks = n
	return self

## Visuals are Phase 5 (no status_pips.png asset yet); satisfy the abstract slot as a no-op.
func set_texture(_polygon2d: Polygon2D) -> void:
	pass

## The visual effects this status renders, or an empty array. The status owns its own presentation, so
## FxAttachment never learns which effects exist and a new visual status is a NEW CLASS, not an edit to
## the FX layer. A status may declare several (StatusJuggling declares its balls AND the fire riding
## them), which keeps the knowledge that one depends on the other inside the one class that owns both.
##
## ⚠ **THIS IS NOW A STATUS'S ONLY PRESENCE ON THE CARD, AND THAT IS A STANDING RULE.** The
## `StatusLayer` — a row of placeholder icons plus a stack count in the card's top-left — is deleted
## (owner 2026-08-04: *"no more status icons, they are represented by status effects like fire and
## juggling shader... stack count and status names stay in description at top"*), and with it the
## `draw_icon` hook whose base implementation drew nothing while the layer still showed the count. That
## backstop is what has gone: **a new status that declares no FX here is INVISIBLE on the board.** Its
## name and stacks still reach the player through the inspector text (`ControlCard.describe_card`),
## which is where the owner wants them, but nothing on the card itself will say it is there.
func fx_request() -> Array[FxRequest]:
	return []

## The OUTLINE ALERT this status asks its card to run — the "this card's ability is about to fire"
## nudge — or an empty array, which is the default and what every status shipping today wants.
##
## ⚠ **DECLARED, NEVER PUSHED, and the difference is a leak.** An imperative `alert_on()` / `alert_off()`
## pair leaks the moment a status is freed, merged away or rewound mid-alert: nothing is left to call
## the "off". `CardVisual` re-derives this list from the LIVE status list on every refresh, so an alert
## that no status still declares is already gone, and one of two simultaneous alerts clearing cannot
## switch off the other. It is the same reasoning that makes `fx_request` a declaration.
func alert_request() -> Array[CardAlert]:
	return []
