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

## When ON, the formation's HEIGHT tracks the live card-separation setting and its points are
## STORED separation-agnostically in FULL-CARD normalized space (ratio 1 when separation == card
## height — owner spec 2026-07-15): authoring the same visual pattern at any separation level
## stores the same points. Consume via PropFormationSet.norm_to_strip (offsets_for does this):
## the pattern always fills the same fraction of the visible top strip — the whole card at max
## separation, squeezed into the top sliver at min. Factor =
## SettingsManager.settings.card_separation_scale in game / the editor's separation stand-in in
## the tool. OFF = points are fixed card-space y. Saved per formation (tunable like `mode`).
@export var spread_by_separation : bool = false

@export var points : PackedVector2Array = PackedVector2Array()
