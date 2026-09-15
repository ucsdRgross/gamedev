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

# ⚠ THE OPENER HANDS ITS OWN CONTROL IN: the pile buttons live in the wall overlay while this
# viewer lives inside a picture's SubViewport, and focus is cleared across every viewport of one
# window -- so reading a focus owner here would find nothing to come back to.
static func show_deck(parent:Node, new_deck:Array[CardData], opener:Control) -> DeckViewer:
	if is_instance_valid(_open):
		_open.queue_free()
	var viewer :DeckViewer= DECK_VIEWER.instantiate()
	viewer.deck = new_deck
	viewer._return_focus = opener
	parent.add_child(viewer)
	viewer.update_viewer()
	_open = viewer
	return viewer

# Closing announces the lost highlight the same way the board does, so a description locked before
# this viewer opened comes back and an unlocked sidebar keeps the last card read here.
func _close() -> void:
	_hand_the_focus_back()
	highlight_cleared.emit()
	queue_free()

# ⚠ THE OPENER CAN BE HIDDEN BY WHAT THIS VIEWER PUBLISHED: a pile button lives in the sidebar's
# own scene, which hides its HUD stack while a description shows, so the focus goes to that
# sidebar's exit X instead -- accept on it dismisses, and the buttons are back.
func _hand_the_focus_back() -> void:
	if not is_instance_valid(_return_focus): return
	if _return_focus.is_visible_in_tree(): _return_focus.grab_focus()
	else: (_return_focus.owner as HudContainer).focus_exit()

# The initial focus is stolen from whatever button opened this viewer, so ui_accept cannot re-open
# it and the arrows walk the cards (ControlCards are focus stops). ⚠ DEFERRED: that focus is a
# highlight, so it must publish AFTER the opener has connected and fitted this viewer, never before.
func update_viewer() -> void:
	_cards = CardsViewer.new(flow_container)
	var first := _cards.populate(deck, _publish_info)
	if first: first.grab_focus.call_deferred()

# A HOVER OR A KEY/PAD FOCUS, NEVER A CLICK: a click in this viewer is its own action, and the lock
# belongs to the board.
func _publish_info(data: CardData) -> void:
	PlayArea.card_info(data, _cards.card_window_px()).relay_to(info_requested)

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

## Keyboard/controller close: Escape/back AND Enter/accept both close (the viewer is
## read-only, so accept has no other meaning). Mouse click on the margin closes below.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_close()

func _on_flow_container_hidden() -> void:
	if _cards: _cards.clear()

func _on_margin_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event : InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_close()
