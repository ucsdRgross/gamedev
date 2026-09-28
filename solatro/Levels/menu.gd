class_name Menu
extends Control

# Main menu: Play unfolds the run row (New Run / Continue); New Run opens the deck
# picker, Continue resumes the run saved on disk.

signal new_run_requested(cards: Array[CardData], rules: Array[CardData])
signal continue_requested

## The card under the highlight in a viewer opened over this menu, relayed to the sidebar exactly as the game screen relays its board's.
signal info_requested(entry: InfoEntry)

@onready var play_row: HFlowContainer = $Content/Run
@onready var new_run_button: Button = get_node("Content/Run/New Run") as Button
@onready var continue_button: Button = $Content/Run/Continue
@onready var _content: VBoxContainer = $Content

# Set by `Main` before this screen's picture is built, the same hand-over `Map.hud_container` gets.
# A standalone fixture with no `Main` (`Tools/wall_editor.gd`'s preview) leaves it null and gets a
# private container instead, the same fallback `GameView`/`Map` use.
var hud_container : HudContainer = null

# Set by `Main` alongside `hud_container`, before `build()` parents this screen into its
# SubViewport -- lets `_apply_container_inset()` convert `hud_container`'s rects into this picture's
# own space. Null only for `Tools/wall_editor.gd`'s preview, whose fallback `hud_container` already lives there.
var wall_picture : WallPicture = null

func _ready() -> void:
	hud_container = HudContainer.ensure(hud_container, self)
	new_run_button.pressed.connect(_on_new_run_pressed)
	continue_button.pressed.connect(continue_requested.emit)
	refresh_continue()
	hud_container.connect_for_screen(self, hud_container.container_rect_changed,
			_apply_container_inset)
	_apply_container_inset()

# The column fills the space beside the sidebar as shown, at exactly the UI scale: the picture draws
# this canvas at its cover scale, so the column undoes it, and a row too wide for the space wraps.
func _apply_container_inset() -> void:
	var remaining := hud_container.rect_beside(wall_picture)
	var ui_per_canvas := 1.0 / WallPicture.cover_scale(get_viewport_rect().size,
			hud_container.get_viewport().get_visible_rect().size)
	_content.scale = Vector2.ONE * ui_per_canvas
	_content.position = remaining.position
	_content.size = remaining.size / ui_per_canvas

func _on_play_pressed() -> void:
	play_row.visible = not play_row.visible
	refresh_continue()

# The picker is the only content on the menu that describes anything, so what it described goes
# when the picker does.
func _on_new_run_pressed() -> void:
	var picker := DeckPicker.add_to_scene(hud_container.get_parent(), new_run_button)
	hud_container.host_deck_picker(picker)
	picker.deck_picked.connect(func(cards: Array[CardData], rules: Array[CardData]) -> void:
		new_run_requested.emit(cards, rules))
	picker.inspect_pressed.connect(_open_deck_viewer.bind(picker))
	picker.tree_exiting.connect(hud_container.release_screen.bind(HudContainer.MENU_SCREEN))

# ⚠ THE VIEWER IS UI ON THE SIDEBAR'S LAYER, so it outlives the picker unless the picker takes it
# with it: a Pick that starts a new run, or the picker's own close.
func _open_deck_viewer(cards: Array[CardData], inspect: Button, picker: DeckPicker) -> void:
	var viewer := DeckViewer.show_deck(hud_container.get_parent(), cards, inspect)
	if viewer == null: return
	hud_container.host_viewer(viewer, info_requested, HudContainer.MENU_SCREEN)
	picker.tree_exiting.connect(viewer.queue_free)

## Continue is only clickable while a resumable run exists on disk.
func refresh_continue() -> void:
	continue_button.disabled = not RunManager.has_save()
