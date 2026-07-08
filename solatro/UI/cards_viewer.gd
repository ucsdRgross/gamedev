class_name CardsViewer
extends RefCounted

## Owns the card-list contents of ONE container Control: instantiates a ControlCard per
## CardData and (optionally) wires an inspector callback fired on hover AND keyboard/controller
## focus. Composed into each viewer (DeckViewer / ChoiceViewer / MapHoverPanel) — they differ
## only in their container and whether they inspect, so the listing logic lives here once,
## rather than copied per viewer. Composition (not a shared base class): the viewers' scene
## roots differ (CanvasLayer / Control / PanelContainer), and ControlCard stays singular (one
## card, not a list).

var _container: Node
var _context: CardVisual.DisplayContext
## The ControlCards currently listed, in order; controls[0] is the natural initial-focus target.
var controls: Array[ControlCard] = []

func _init(container: Node, context := CardVisual.DisplayContext.DECK_VIEWER) -> void:
	_container = container
	_context = context

## Fill the container with one ControlCard per card. `on_inspect(card)` (optional) fires on
## hover AND focus. Returns the first card (for initial focus), or null when empty. Call clear()
## first if repopulating.
func populate(cards: Array[CardData], on_inspect := Callable()) -> ControlCard:
	for data in cards:
		var control := ControlCard.add_child_control_card(_container, data, _context)
		controls.append(control)
		if on_inspect.is_valid():
			control.mouse_entered.connect(on_inspect.bind(data))
			control.focus_entered.connect(on_inspect.bind(data))
	return controls[0] if controls else null

## Remove every listed ControlCard (before repopulating, or when the viewer hides). Detaches
## immediately (not just queue_free) so a same-frame repopulate never shows stale cards.
func clear() -> void:
	for control in controls:
		if is_instance_valid(control):
			if control.get_parent():
				control.get_parent().remove_child(control)
			control.queue_free()
	controls.clear()
