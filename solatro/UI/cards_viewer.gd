class_name CardsViewer
extends RefCounted

## Owns the card-list contents of ONE container Control: instantiates a ControlCard per CardData and (optionally) wires an inspector callback fired on hover AND keyboard/controller focus, plus the one MODAL model every viewer shares: a click sticks the sidebar to a card, a later hover borrows the description only while it lasts, keys never reach the screen beneath, and one cancel unsticks and closes together. Composed into each viewer (DeckViewer / ChoiceViewer / MapHoverPanel) — they differ only in their container and whether they inspect, so the listing logic lives here once, rather than copied per viewer. Composition (not a shared base class): the viewers' scene roots differ (CanvasLayer / Control / PanelContainer), and ControlCard stays singular (one card, not a list).

var _container: Node
var _context: CardVisual.DisplayContext
## The ControlCards currently listed, in order; controls[0] is the natural initial-focus target.
var controls: Array[ControlCard] = []

## How big a window pixel is against one of the picture these cards are listed in; pushed in by the screen that hosts the list.
var picture_to_window_scale : float = 1.0

func _init(container: Node, context := CardVisual.DisplayContext.DECK_VIEWER) -> void:
	_container = container
	_context = context

## Fill the container with one ControlCard per card. `on_inspect(card)` (optional) fires on hover AND focus. Returns the first card (for initial focus), or null when empty. Call clear() first if repopulating.
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

## Wires one listed control's hover, focus AND click -- also the way a control REPLACING one keeps its place in the list wired.
func inspect_on_highlight(control: ControlCard, data: CardData) -> void:
	control.mouse_entered.connect(_enter_highlight.bind(data))
	control.mouse_exited.connect(_leave_highlight)
	control.focus_entered.connect(_publish_highlight.bind(data))
	control.gui_input.connect(_on_card_gui_input.bind(data, control))

## The listed card the player CLICKED, or null while none is: what keeps the sidebar on it while the highlight moves on.
var sticky : CardData = null

## A card became the sticky one, or the sticky one was let go -- the sidebar pins and unpins on this.
signal sticky_changed(stuck: bool)

## A navigation key reached the LIST'S OWN EDGE while a card is stuck: the sidebar is the only place left to go, and it is in another viewport.
signal sidebar_requested

## The pointer is on none of the listed cards any more -- the sidebar goes back to whatever is under this list's highlights.
signal highlight_left

## How many listed cards the pointer is inside: a card gives the highlight up only when the last one does.
var _hovering : int = 0

func _enter_highlight(data: CardData) -> void:
	_hovering += 1
	_publish_highlight(data)

# A HOVER OVERRIDES A STUCK CARD ONLY WHILE IT LASTS: the player can read a long description by
# moving off every card, or on into the sidebar, and find the one they clicked still there.
func _leave_highlight() -> void:
	_hovering -= 1
	if _hovering <= 0: highlight_left.emit()

# A CLICK IS WHAT MAKES A DESCRIPTION STAY, and it is taken here so it never reaches the catcher
# behind the list, which reads a click anywhere else as "close".
func _on_card_gui_input(event: InputEvent, data: CardData, control: ControlCard) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed: return
	control.accept_event()
	control.grab_focus()
	stick_to(data)

## Pins the sidebar to `data`: it stays the description's subject until it is let go.
func stick_to(data: CardData) -> void:
	sticky = data
	_publish_highlight(data)

## Lets the stuck card go, so the highlight describes whatever it is on again.
func unstick() -> void:
	if sticky == null: return
	sticky = null
	sticky_changed.emit(false)
	if _hovering <= 0: highlight_left.emit()

## What a viewer must do with one input: KEEP takes it from the screen beneath, CLOSE dismisses the viewer, PASS leaves it alone.
enum Modal { PASS, KEEP, CLOSE }

## The navigation actions a viewer's own list walks on, and the ones the screen beneath would otherwise answer.
const NAVIGATION : Array[StringName] = [&"ui_left", &"ui_right", &"ui_up", &"ui_down"]

# ⚠ REACHED ONLY AFTER THE GUI PASS: an arrow that found a focus neighbour inside the list has
# already moved and never arrives, so what is left is an arrow off the list's own EDGE.
func modal_verdict(event: InputEvent) -> Modal:
	if event.is_action_pressed(&"ui_cancel"): return Modal.CLOSE
# ACCEPT IS THE CLICK'S OWN KEY: it sticks the card the focus is on. Reaching here at all means no
# button took it, so it is swallowed either way rather than reaching the map beneath.
	if event.is_action_pressed(&"ui_accept"):
		for control : ControlCard in controls:
			if control.has_focus(): stick_to(control.child.data)
		return Modal.KEEP
	for action : StringName in NAVIGATION:
		if not event.is_action_pressed(action, true): continue
# ⚠ REACHED FOR A PRESS PUSHED STRAIGHT INTO THIS PICTURE'S OWN VIEWPORT, which never rises to the
# overlay, so the container's earlier hand-over never sees it -- measured on the map's deck viewer.
		if focus_first(): return Modal.KEEP
		if sticky != null:
			_publish_highlight(sticky)
			sidebar_requested.emit()
		return Modal.KEEP
	return Modal.PASS

# Remembered rather than only relayed: a list that has been re-sized owes the description it
# published the same card again. Only the stuck entry carries the X, so the stuck card's fresh
# description is re-stuck rather than shown as a highlight over its own lock.
func _publish_highlight(data: CardData) -> void:
	_highlighted = data
	_on_inspect.call(data)
	if data == sticky: sticky_changed.emit(true)

# HOW A KEY OR PAD PLAYER ENTERS A LIST THAT OPENED WITH NOTHING FOCUSED. Answers whether it took
# the press, so the caller knows whether the screen beneath may still have it.
func focus_first() -> bool:
	if controls.is_empty() or focus_is_inside(): return false
	controls[0].grab_focus()
	return true

## Whether one of the listed cards holds the keyboard/pad focus: the one test for "the player is navigating inside this list".
func focus_is_inside() -> bool:
	for control : ControlCard in controls:
		if control.has_focus(): return true
	return false

## Publishes the card the highlight is on again -- nothing to say while a freshly built list has not been pointed at yet.
func republish_highlight() -> void:
	if _highlighted: _publish_highlight(_highlighted)

# A SLOT SWAPPED UNDER THE HIGHLIGHT: the pointer never moved, so what it is on now is whatever took
# the slot -- otherwise the description reads the card that is gone until the player moves.
func rehighlight(replaced: CardData, data: CardData) -> void:
	if sticky == replaced: stick_to(data)
	elif _highlighted == replaced: _publish_highlight(data)

## Remove every listed ControlCard (before repopulating, or when the viewer hides). Detaches immediately (not just queue_free) so a same-frame repopulate never shows stale cards.
func clear() -> void:
	for control in controls:
		if is_instance_valid(control):
			if control.get_parent():
				control.get_parent().remove_child(control)
			control.queue_free()
	controls.clear()
