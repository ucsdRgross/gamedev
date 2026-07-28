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
func is_active() -> bool:
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

## The visual effects this status renders, or an empty array for statuses that only show an icon.
## Mirrors draw_icon: the status owns its own presentation, so FxAttachment never learns which
## effects exist and a new visual status is a NEW CLASS, not an edit to the FX layer. A status may
## declare several (StatusJuggling declares its balls AND the fire riding them), which keeps the
## knowledge that one depends on the other inside the one class that owns both.
func fx_request() -> Array[FxRequest]:
	return []

## Placeholder icon draw (Phase 5, pending a status_pips.png asset). Subclasses draw a
## kind-distinct primitive into `canvas` anchored at `at`, spanning roughly `size` px wide.
## Base draws nothing so an un-arted status simply shows its count label (StatusLayer).
func draw_icon(_canvas: CanvasItem, _at: Vector2, _size: float) -> void:
	pass
