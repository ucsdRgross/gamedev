class_name Menu
extends Control

# Main menu: Play unfolds the run row (New Run / Continue); New Run opens the deck
# picker, Continue resumes the run saved on disk.

signal new_run_requested(cards: Array[CardData], rules: Array[CardData])
signal continue_requested

## The card under the highlight in a viewer opened over this menu, relayed to the sidebar exactly as the game screen relays its board's.
signal info_requested(entry: InfoEntry)

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

# Each content node's own place on the design canvas, captured once before any inset scale --
# `_fit_beside_container()` re-derives every node's position from these, never from the node's
# own (already-scaled) `.position`, or a second inset would compound onto the first.
var _authored_positions : Dictionary[Control, Vector2] = {}

# The menu's own authored content bounds -- title, buttons and the run row -- captured once, the
# same way `_authored_positions` is: what actually has to fit beside the container, not the
# window's own empty margin around it.
var _design_rect : Rect2

func _ready() -> void:
	hud_container = HudContainer.ensure(hud_container, self)
	new_run_button.pressed.connect(_on_new_run_pressed)
	continue_button.pressed.connect(continue_requested.emit)
	refresh_continue()
	for content : Control in [_title, _main_control, play_row]:
		_authored_positions[content] = content.position
	_design_rect = _content_bounds()
	hud_container.connect_for_screen(self, hud_container.container_rect_changed,
			_apply_container_inset)
	hud_container.connect_for_screen(self, hud_container.container_rect_changed, _fit_open_viewer)
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
	_fit_beside_container(hud_container.rect_beside(wall_picture))

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

# The picker is the only content on the menu that describes anything, so what it described goes
# when the picker does.
func _on_new_run_pressed() -> void:
	var picker := DeckPicker.add_to_scene(self)
	picker.deck_picked.connect(func(cards: Array[CardData], rules: Array[CardData]) -> void:
		new_run_requested.emit(cards, rules))
	picker.viewer_opened.connect(_on_viewer_opened)
	picker.tree_exiting.connect(hud_container.release_screen.bind(HudContainer.MENU_SCREEN))

## The viewer an Inspect opened over this menu, if any -- one at a time, the same one `DeckViewer` itself keeps.
var _deck_viewer : DeckViewer = null

# THE PICKER'S VIEWER IS A SCREEN OCCUPANT LIKE THE MENU ITSELF: it lays out in the space beside the
# sidebar and publishes into it, the same rule the game screen's and the map's viewers follow.
func _on_viewer_opened(viewer: DeckViewer) -> void:
	_deck_viewer = viewer
	viewer.info_requested.connect(_relay_info_requested)
	viewer.highlight_cleared.connect(hud_container.return_to_lock)
	_fit_open_viewer()

# The re-fit re-publishes only a description that is UP: a dismissal is the player's own act and a
# window change is not one.
func _fit_open_viewer() -> void:
	if not is_instance_valid(_deck_viewer): return
	_deck_viewer.fit_beside(hud_container.rect_beside(wall_picture),
			hud_container.window_scale(wall_picture))
	if hud_container.showing_description(): _deck_viewer.republish_highlight()

# The relay owns the live preview the entry carries when no `Main` is listening.
func _relay_info_requested(entry: InfoEntry) -> void:
	entry.relay_to(info_requested)

## Continue is only clickable while a resumable run exists on disk.
func refresh_continue() -> void:
	continue_button.disabled = not RunManager.has_save()
