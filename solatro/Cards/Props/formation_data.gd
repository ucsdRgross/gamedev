class_name PropFormationData
extends Resource
## ONE condensed spawn pattern for a prop kind: plotted points in UNSCALED card space around
## the card anchor (CardVisual.CARD_SIZE footprint — every point must stay inside it; the
## whole formation fits one slot). A spawned batch maps onto these points (see
## PropFormationSet.offsets_for); card_scale is applied at use. Author these with the
## standalone editor tool: res://Cards/Props/Tools/formation_editor.tscn.

enum Mode { ORDERED, RANDOM }

## How a batch maps onto the points: ORDERED walks them in EXACT list order (prop i ->
## point i, wrapping); RANDOM walks a seeded shuffle of the list instead (still points-only —
## no point repeats until all are used, and a full batch still fills every point).
@export var mode : Mode = Mode.ORDERED

@export var points : PackedVector2Array = PackedVector2Array()
