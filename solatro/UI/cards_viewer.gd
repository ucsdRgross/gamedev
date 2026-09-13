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

## How big a window pixel is against one of the picture these cards are listed in; pushed in by the screen that hosts the list.
var picture_to_window_scale : float = 1.0

## The size one of these cards has in WINDOW pixels, so a description published from this list is previewed as the very object the player is pointing at.
func card_window_px() -> Vector2:
	return controls[0].child.card_size * picture_to_window_scale

func _init(container: Node, context := CardVisual.DisplayContext.DECK_VIEWER) -> void:
	_container = container
	_context = context

## Fill the container with one ControlCard per card. `on_inspect(card)` (optional) fires on
## hover AND focus. Returns the first card (for initial focus), or null when empty. Call clear()
## first if repopulating.
func populate(cards: Array[CardData], on_inspect := Callable()) -> ControlCard:
	_on_inspect = on_inspect
	for data in cards:
		var control := ControlCard.add_child_control_card(_container, data, _context)
		controls.append(control)
		if on_inspect.is_valid():
			inspect_on_highlight(control, data)
	return controls[0] if controls else null

## The callback `populate()` wired, kept so a list that has been re-sized can publish through it again.
var _on_inspect : Callable = Callable()

## The listed card the highlight last reached; a viewer announces its own close, so nothing else retires it.
var _highlighted : CardData = null

## Wires one listed control's hover AND focus to the inspect callback -- also the way a control REPLACING one keeps its place in the list wired.
func inspect_on_highlight(control: ControlCard, data: CardData) -> void:
	control.mouse_entered.connect(_publish_highlight.bind(data))
	control.focus_entered.connect(_publish_highlight.bind(data))

# Remembered rather than only relayed: a list that has been re-sized owes the description it
# published the same card again, drawn at the size this list now draws it at.
func _publish_highlight(data: CardData) -> void:
	_highlighted = data
	_on_inspect.call(data)

## Publishes the card the highlight is on again -- nothing to say while a freshly built list has not been pointed at yet.
func republish_highlight() -> void:
	if _highlighted: _publish_highlight(_highlighted)

# A SLOT SWAPPED UNDER THE HIGHLIGHT: the pointer never moved, so what it is on now is whatever took
# the slot -- otherwise the description reads the card that is gone until the player moves.
func rehighlight(replaced: CardData, data: CardData) -> void:
	if _highlighted == replaced: _publish_highlight(data)

## Remove every listed ControlCard (before repopulating, or when the viewer hides). Detaches
## immediately (not just queue_free) so a same-frame repopulate never shows stale cards.
func clear() -> void:
	for control in controls:
		if is_instance_valid(control):
			if control.get_parent():
				control.get_parent().remove_child(control)
			control.queue_free()
	controls.clear()
