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
		if stacks <= 0:
			if data: data.remove_status(self)
		elif data:
			data.data_changed.emit()

## Statuses of the same class merge (stacks add) instead of coexisting. Override to return
## false for statuses that want independent instances (e.g. a future StatusSeal).
func can_merge_with(other: CardModifierStatus) -> bool:
	return get_script() == other.get_script()

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

## Placeholder icon draw (Phase 5, pending a status_pips.png asset). Subclasses draw a
## kind-distinct primitive into `canvas` anchored at `at`, spanning roughly `size` px wide.
## Base draws nothing so an un-arted status simply shows its count label (StatusLayer).
func draw_icon(_canvas: CanvasItem, _at: Vector2, _size: float) -> void:
	pass
