class_name Menu
extends Control

# Main menu: Play unfolds the run row (New Run / Continue); New Run opens the deck
# picker, Continue resumes the run saved on disk.

signal new_run_requested(cards: Array[CardData], rules: Array[CardData])
signal continue_requested

@onready var play_row: HBoxContainer = $Play
@onready var new_run_button: Button = get_node("Play/New Run") as Button
@onready var continue_button: Button = $Play/Continue
@onready var _main_control: Control = $Main
@onready var _title: Label = $Label

# Set by `Main` before this screen's picture is built, the same hand-over `Map.hud_container` gets.
# A standalone fixture with no `Main` (`Tools/wall_editor.gd`'s preview) leaves it null and gets a
# private container instead, the same fallback `GameView`/`Map` use.
var hud_container : HudContainer = null

# Set by `Main` alongside `hud_container`, before `build()` parents this screen into its
# SubViewport -- lets `_apply_container_inset()` convert `hud_container`'s rects into this picture's
# own space. Null only for `Tools/wall_editor.gd`'s preview, whose fallback `hud_container` already lives there.
var wall_picture : WallPicture = null

const HUD_CONTAINER_SCENE := preload("res://UI/hud_container.tscn")

# Each content node's own place on the design canvas, captured once before any inset scale --
# `_fit_beside_container()` re-derives every node's position from these, never from the node's
# own (already-scaled) `.position`, or a second inset would compound onto the first.
var _authored_positions : Dictionary[Control, Vector2] = {}

# The menu's own authored content bounds -- title, buttons and the run row -- captured once, the
# same way `_authored_positions` is: what actually has to fit beside the container, not the
# window's own empty margin around it.
var _design_rect : Rect2

func _ready() -> void:
	if hud_container == null:
		hud_container = HUD_CONTAINER_SCENE.instantiate() as HudContainer
		add_child(hud_container)
	new_run_button.pressed.connect(_on_new_run_pressed)
	continue_button.pressed.connect(continue_requested.emit)
	refresh_continue()
	for content : Control in [_title, _main_control, play_row]:
		_authored_positions[content] = content.position
	_design_rect = _content_bounds()
	hud_container.container_rect_changed.connect(_apply_container_inset)
	_apply_container_inset()

# The union of every button under `Main`, the title and the run row -- `_main_control` itself
# fills the whole window (its authored anchors), so its own rect cannot stand in for it.
func _content_bounds() -> Rect2:
	var bounds := Rect2(_title.position, _title.size)
	bounds = bounds.merge(Rect2(play_row.position, play_row.size))
	for button : Button in _main_control.get_children():
		bounds = bounds.merge(Rect2(button.position, button.size))
	return bounds

# The sidebar is always visible: the whole menu (title included) is centred in the space beside
# `container_rect()`. Any scale is UNIFORM and only shrinks -- never distorts a glyph or a button --
# so it only kicks in once the design content would not otherwise fit beside the container.
func _apply_container_inset() -> void:
	var window_screen := hud_container.get_viewport().get_visible_rect().size
	var rect_screen := hud_container.container_rect()
	var top := HudContainer.container_is_top(window_screen, SettingsManager.settings)
	var remaining := wall_picture.local_rect_beside(window_screen, rect_screen, top) if wall_picture \
			else (Rect2(0.0, rect_screen.size.y, window_screen.x, window_screen.y - rect_screen.size.y) \
				if top else Rect2(rect_screen.size.x, 0.0,
					window_screen.x - rect_screen.size.x, window_screen.y))
	_fit_beside_container(remaining)

# Centres `_design_rect` inside `remaining` (already in this menu's own picture space), shrinking
# -- never distorting -- only if it would not otherwise fit.
func _fit_beside_container(remaining: Rect2) -> void:
	var factor := minf(1.0, minf(remaining.size.x / _design_rect.size.x,
			remaining.size.y / _design_rect.size.y))
	var translation := remaining.position + (remaining.size - _design_rect.size * factor) / 2.0 \
			- _design_rect.position * factor
	for content : Control in [_title, _main_control, play_row]:
		content.scale = Vector2.ONE * factor
		content.position = _authored_positions[content] * factor + translation

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
