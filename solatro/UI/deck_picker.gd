class_name DeckPicker
extends Control

## Menu overlay listing every starter deck (Deck.get_deck_list): inspect a deck's cards, or pick one to start a new run with.

signal deck_picked(cards: Array[CardData], rules: Array[CardData])

## Inspect was pressed on a deck's row: the screen hosting this picker opens that deck's viewer, with `inspect` as its opener, exactly as it opens its own viewers.
signal inspect_pressed(cards: Array[CardData], inspect: Button)

const DECK_PICKER := preload("res://UI/deck_picker.tscn")

@onready var rows: VBoxContainer = %Rows
@onready var _panel: PanelContainer = $Panel
@onready var _scroll: ScrollContainer = $Panel/VBox/Scroll

var _deck : Deck = Deck.new()
# Focus to restore on close (keyboard/controller flow back to the opening button).
var _return_focus : Control = null
# A pick built the rules list too (get_rules) — remembered so LeakSentinel can root the
# built list without force-building it on a plain close.
var _rules_built : bool = false

# ⚠ THE OPENER HANDS ITS OWN CONTROL IN: it is in the menu's picture, another viewport than this
# picker's, and the focus this picker grabs clears it across every viewport of the window.
static func add_to_scene(parent: Node, opener: Control) -> DeckPicker:
	var picker : DeckPicker = DECK_PICKER.instantiate()
	picker._return_focus = opener
	parent.add_child(picker)
	return picker

func _ready() -> void:
	for entry in _deck.get_deck_list():
		var cards : Array[CardData] = entry["cards"]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s  (%d cards)" % [entry["name"], cards.size()]
		label.custom_minimum_size = Vector2(240, 0)
		row.add_child(label)
		var inspect := Button.new()
		inspect.text = "Inspect"
		inspect.pressed.connect(func() -> void: inspect_pressed.emit(cards, inspect))
		row.add_child(inspect)
		var pick := Button.new()
		pick.text = "Pick"
		pick.pressed.connect(_on_pick.bind(cards))
		row.add_child(pick)
		rows.add_child(row)
	focus_the_first_pick()

# The scroll follows this focus off rows not yet laid out -- measured, one 39 px row past the top --
# so it is set back.
## Focuses the first deck's Pick with the list at its top; a no-op while the picker is hidden.
func focus_the_first_pick() -> void:
	if not is_visible_in_tree(): return
	(rows.get_child(0).get_child(2) as Button).grab_focus()
	_scroll.scroll_vertical = 0

## Centres the list in `remaining`, the space the menu's own content is centred in.
func fit_beside(remaining: Rect2) -> void:
	_panel.position = remaining.get_center() - _panel.size / 2.0

## Keyboard/controller close.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()

func _on_pick(cards: Array[CardData]) -> void:
	_rules_built = true
	deck_picked.emit(cards, _deck.get_rules())
	queue_free()

func _on_close_pressed() -> void:
	_close()

func _close() -> void:
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()
	queue_free()
