class_name Menu
extends Control

## Main menu: Play unfolds the run row (New Run / Continue); New Run opens the deck
## picker, Continue resumes the run saved on disk.

signal new_run_requested(cards: Array[CardData], rules: Array[CardData])
signal continue_requested

@onready var play_row: HBoxContainer = $Play
@onready var new_run_button: Button = get_node("Play/New Run") as Button
@onready var continue_button: Button = $Play/Continue

func _ready() -> void:
	new_run_button.pressed.connect(_on_new_run_pressed)
	continue_button.pressed.connect(continue_requested.emit)
	refresh_continue()

func _on_play_pressed() -> void:
	play_row.visible = not play_row.visible
	refresh_continue()

func _on_new_run_pressed() -> void:
	var picker := DeckPicker.add_to_scene(self)
	picker.deck_picked.connect(func(cards: Array[CardData], rules: Array[CardData]) -> void:
		new_run_requested.emit(cards, rules))

## Continue is only clickable while a resumable run exists on disk.
func refresh_continue() -> void:
	continue_button.disabled = not RunManager.has_save()
