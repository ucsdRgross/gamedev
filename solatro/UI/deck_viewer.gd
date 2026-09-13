class_name DeckViewer
extends CanvasLayer

const DECK_VIEWER = preload("uid://dnvpthmsneqjl")

## The card under the pointer, handed to the screen that opened this viewer, which relays it to the sidebar exactly as it relays the board's own.
signal info_requested(entry: InfoEntry)

## This viewer closed, so nothing of its is highlighted any more and the sidebar returns to whatever was locked behind it.
signal highlight_cleared

@onready var flow_container: FlowContainer = %FlowContainer
@onready var margin_container: MarginContainer = $MarginContainer

enum SORTING_TYPE {RANK,SUIT,EFFECT}
enum SORTING_ORDER {ASCENDING,DESCENDING}

var deck : Array[CardData]
## Owns this viewer's listed cards (the shared listing logic; see CardsViewer).
var _cards : CardsViewer
var randomized : bool = false
var sorting_type : SORTING_TYPE = SORTING_TYPE.RANK
var sorting_order : SORTING_ORDER = SORTING_ORDER.ASCENDING

# Only one viewer at a time: opening a new one (Deck button, deck picker Inspect, Enter
# re-triggering a still-focused button, ...) replaces the previous instead of stacking.
static var _open : DeckViewer = null
# Focus to restore on close, so keyboard/controller users land back on the button that
# opened the viewer instead of nowhere.
var _return_focus : Control = null

static func show_deck(parent:Node, new_deck:Array[CardData]) -> DeckViewer:
	if is_instance_valid(_open):
		_open.queue_free()
	var viewer :DeckViewer= DECK_VIEWER.instantiate()
	viewer.deck = new_deck
	viewer._return_focus = parent.get_viewport().gui_get_focus_owner() if parent.is_inside_tree() else null
	parent.add_child(viewer)
	viewer.update_viewer()
	_open = viewer
	return viewer

# Closing announces the lost highlight the same way the board does, so a description locked before
# this viewer opened comes back and an unlocked sidebar keeps the last card read here.
func _close() -> void:
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()
	highlight_cleared.emit()
	queue_free()

# The initial focus is stolen from whatever button opened this viewer, so ui_accept cannot re-open
# it and the arrows walk the cards (ControlCards are focus stops).
func update_viewer() -> void:
	_cards = CardsViewer.new(flow_container)
	var first := _cards.populate(deck, _publish_info)
	if first: first.grab_focus()

# A HOVER OR A KEY/PAD FOCUS, NEVER A CLICK: a click in this viewer is its own action, and the lock
# belongs to the board.
func _publish_info(data: CardData) -> void:
	PlayArea.card_info(data, _cards.card_window_px()).relay_to(info_requested)

# ⚠ THIS VIEWER IS A FULL-SCREEN OVERLAY INSIDE ITS PICTURE and would otherwise cover the sidebar,
# so its cards start at the inner edge of the space left beside it. The scale rides along: the
# description's preview is drawn at the size THIS viewer draws a card at.
func fit_beside(remaining: Rect2, window_scale: float) -> void:
	_cards.picture_to_window_scale = window_scale
	margin_container.add_theme_constant_override(&"margin_left",
			margin_container.get_theme_constant(&"margin_left") + ceili(remaining.position.x))
	margin_container.add_theme_constant_override(&"margin_top",
			margin_container.get_theme_constant(&"margin_top") + ceili(remaining.position.y))

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
