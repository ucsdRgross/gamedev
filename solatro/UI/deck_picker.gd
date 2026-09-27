class_name DeckPicker
extends CanvasLayer

## Menu overlay listing every starter deck (Deck.get_deck_list): inspect a deck's cards, or pick one to start a new run with.

signal deck_picked(cards: Array[CardData], rules: Array[CardData])

## Inspect was pressed on a deck's row: the screen hosting this picker opens that deck's viewer, with `inspect` as its opener, exactly as it opens its own viewers.
signal inspect_pressed(cards: Array[CardData], inspect: Button)

const DECK_PICKER := preload("res://UI/deck_picker.tscn")

@onready var rows: VBoxContainer = %Rows

var _deck : Deck = Deck.new()
# Focus to restore on close (keyboard/controller flow back to the opening button).
var _return_focus : Control = null
# A pick built the rules list too (get_rules) — remembered so LeakSentinel can root the
# built list without force-building it on a plain close.
var _rules_built : bool = false

static func add_to_scene(parent: Node) -> DeckPicker:
	var picker : DeckPicker = DECK_PICKER.instantiate()
	picker._return_focus = parent.get_viewport().gui_get_focus_owner() if parent.is_inside_tree() else null
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
	var first_row := rows.get_child(0) as HBoxContainer
	if first_row:
		(first_row.get_child(2) as Button).grab_focus()

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
