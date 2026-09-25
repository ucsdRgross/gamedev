class_name DeckViewer
extends CanvasLayer

const DECK_VIEWER = preload("uid://dnvpthmsneqjl")

## The card under the pointer, handed to the screen that opened this viewer, which relays it to the sidebar exactly as it relays the board's own.
signal info_requested(entry: InfoEntry)

## This viewer closed, so nothing of its is highlighted any more and the sidebar returns to whatever was locked behind it.
signal highlight_cleared

@onready var flow_container: FlowContainer = %FlowContainer
@onready var margin_container: MarginContainer = $MarginContainer

var deck : Array[CardData]
## Owns this viewer's listed cards (the shared listing logic; see CardsViewer).
var _cards : CardsViewer

# Only one viewer at a time: opening a new one (Deck button, deck picker Inspect, Enter
# re-triggering a still-focused button, ...) replaces the previous instead of stacking.
static var _open : DeckViewer = null
# Focus to restore on close, so keyboard/controller users land back on the button that
# opened the viewer instead of nowhere.
var _return_focus : Control = null
## Where the focus goes on close when the opener is hidden; set by the `HudContainer` hosting this viewer.
var fallback_focus : Control = null

# ⚠ THE OPENER HANDS ITS OWN CONTROL IN: focus is cleared across every viewport of one window, so
# reading a focus owner here would find nothing to come back to. A SECOND PRESS OF THAT SAME
# opener is a close and returns null; any other replaces the viewer, as swapping piles does.
static func show_deck(parent:Node, new_deck:Array[CardData], opener:Control) -> DeckViewer:
	if is_instance_valid(_open) and not _open.is_queued_for_deletion():
		var same_opener : bool = _open._return_focus == opener
		_open._close()
		if same_opener: return null
	var viewer :DeckViewer= DECK_VIEWER.instantiate()
	viewer.deck = new_deck
	viewer._return_focus = opener
	parent.add_child(viewer)
	viewer.update_viewer()
	_open = viewer
	return viewer

# THE OPENER IS ALSO THE CLOSER while its viewer is up, a second press toggling it shut, so it says
# so until the viewer leaves the tree, however it goes. A button freed first takes the connection.
static func read_close_while_open(opener: Button, close_key: StringName, viewer: DeckViewer) -> void:
	if viewer == null: return
	viewer.tree_exiting.connect(opener.set_text.bind(opener.text))
	opener.text = TRANSLATION.find(close_key)

# ⚠ ANNOUNCED BEFORE THE FOCUS IS HANDED BACK: the sidebar falls back to what was under this
# viewer first, so the opener is on screen again by the time the focus goes looking for it.
func _close() -> void:
	queue_free()
	highlight_cleared.emit()
	_hand_the_focus_back()

# ⚠ THE OPENER CAN BE HIDDEN BY WHAT THIS VIEWER PUBLISHED: a pile button lives in the sidebar's
# own scene, which hides its HUD stack while a description shows, so the focus goes to the fallback
# its host set, the sidebar's exit X -- accept on it dismisses, and the buttons are back.
func _hand_the_focus_back() -> void:
	if not is_instance_valid(_return_focus): return
	if _return_focus.is_visible_in_tree(): _return_focus.grab_focus()
	else: fallback_focus.grab_focus()

# ⚠ NOTHING IS FOCUSED ON OPEN: a focus here is a highlight, and a highlight holds the sidebar
# against the HUD the player still has to reach. The first arrow enters the list instead
# (`HudContainer` hands it over, the two being in different viewports).
func update_viewer() -> void:
	_cards = CardsViewer.new(flow_container)
	_cards.populate(deck, _publish_info)

# The card the highlight reached, drawn at this viewer's own card size.
func _publish_info(data: CardData) -> void:
	PlayArea.highlight_info(data,
			CardVisual.preview_window_px(_cards.picture_to_window_scale)).relay_to(info_requested)

# ⚠ THIS VIEWER IS A FULL-SCREEN OVERLAY INSIDE ITS PICTURE and would otherwise cover the sidebar,
# so its cards list inside the space left beside it -- ALL FOUR EDGES, or a row runs off the far one.
# The scale rides along, so a re-publish after it is drawn at the size THIS viewer now draws a card.
func fit_beside(remaining: Rect2, window_scale: float) -> void:
	_cards.picture_to_window_scale = window_scale
	var picture := get_viewport().get_visible_rect().size
	_inset_margin(&"margin_left", remaining.position.x)
	_inset_margin(&"margin_top", remaining.position.y)
	_inset_margin(&"margin_right", picture.x - remaining.end.x)
	_inset_margin(&"margin_bottom", picture.y - remaining.end.y)

## Publishes the card its highlight is on again -- asked by the opener only while a description is UP, so one the player dismissed stays dismissed across a re-fit.
func republish_highlight() -> void:
	_cards.republish_highlight()

## This viewer's listed cards, which carry the modal and sticky model its host wires itself to.
func cards() -> CardsViewer:
	return _cards

## The sidebar's own X asking this viewer to go: one press unsticks and closes together.
func close_from_sidebar() -> void:
	_close()

## The margins the scene authored, read once before the first fit overrides them.
var _authored_margins : Dictionary[StringName, int] = {}

# The click-to-close catcher keeps the picture's whole rect while its CONTENT moves in, so the inset
# rides on the MarginContainer's authored padding. ⚠ SET FROM THAT, NEVER ADDED TO WHAT IS THERE:
# this runs again on every window change while the viewer is open.
func _inset_margin(margin: StringName, inset: float) -> void:
	if not _authored_margins.has(margin):
		_authored_margins[margin] = margin_container.get_theme_constant(margin)
	margin_container.add_theme_constant_override(margin,
			_authored_margins[margin] + ceili(inset))

## Keyboard/controller: the shared modal verdict decides. Mouse click on the margin closes below.
func _unhandled_input(event: InputEvent) -> void:
	var verdict := _cards.modal_verdict(event)
	if verdict == CardsViewer.Modal.PASS: return
	get_viewport().set_input_as_handled()
	if verdict == CardsViewer.Modal.CLOSE: _close()

func _on_flow_container_hidden() -> void:
	if _cards: _cards.clear()

# EITHER BUTTON: a press outside the list closes, and the second button cancels from anywhere on
# screen, which over this viewer is the same act.
func _on_margin_container_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed: return
	if button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: _close()
