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
@onready var _bottom_row: HFlowContainer = $Content/Main

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
	hud_container.connect_for_screen(self, hud_container.active_screen_changed, refresh_continue)
	hud_container.connect_for_screen(self, hud_container.active_screen_changed, take_the_focus)
	hud_container.connect_for_screen(self, hud_container.container_rect_changed,
			_apply_container_inset)
	_content.minimum_size_changed.connect(_apply_container_inset)
	_apply_container_inset()

# The column is laid out at exactly the UI scale (the picture draws this canvas at its cover scale,
# so the column undoes it) in the space beside the RESTING sidebar whenever any of it is in, and only
# shifts with the slide, centre to centre: a row too wide wraps once, as the slide starts or ends.
func _apply_container_inset() -> void:
	var shown := hud_container.rect_beside(wall_picture)
	var resting := hud_container.resting_rect_beside(wall_picture)
	var fitted := resting if hud_container.slid_fraction() > 0.0 else shown
	var ui_per_canvas := 1.0 / WallPicture.cover_scale(get_viewport_rect().size,
			hud_container.get_viewport().get_visible_rect().size)
	_content.scale = Vector2.ONE * ui_per_canvas
	_content.position = fitted.position + shown.get_center() - fitted.get_center()
	_content.size = fitted.size / ui_per_canvas
	_stack_the_buttons(_stacked_height() <= resting.size.y / ui_per_canvas)

# A SEPARATION AS WIDE AS THE ROW leaves no line room for a second button, whatever the labels.
# ⚠ Left and Right stay put on a stack: the engine takes any wider button above or below as lying
# to the side (measured: Left on Play landed on Profile).
func _stack_the_buttons(stacked: bool) -> void:
	var buttons : Array[Node] = [$Content/Play]
	for row : HFlowContainer in [play_row, _bottom_row] as Array[HFlowContainer]:
		if stacked: row.add_theme_constant_override(&"h_separation", ceili(_content.size.x))
		else: row.remove_theme_constant_override(&"h_separation")
		buttons += row.get_children()
	for button : Control in buttons:
		button.focus_neighbor_left = ^"." if stacked else ^""
		button.focus_neighbor_right = button.focus_neighbor_left

# THE BUTTONS STACK INTO ONE COLUMN wherever all of it, the Play submenu open, fits beside the
# resting sidebar: the window alone decides, so neither Play nor the slide re-arranges the menu.
# ⚠ A row reports its LAST sort's height, so the column re-fits when its own minimum changes.
func _stacked_height() -> float:
	var height := _content.get_theme_constant(&"separation") * (_content.get_child_count() - 1.0)
	for child : Control in _content.get_children():
		var row := child as HFlowContainer
		if row == null:
			height += child.get_combined_minimum_size().y
			continue
		height += row.get_theme_constant(&"v_separation") * (row.get_child_count() - 1.0)
		for button : Control in row.get_children():
			height += button.get_combined_minimum_size().y
	return height

# A KEY OR PAD PLAYER STARTS HERE: Play takes the focus each time the menu becomes the screen shown,
# so one device alone reaches every button -- unless the picker or a viewer is up over it, which
# holds the focus itself, and a return never focuses a control behind a viewer.
func take_the_focus() -> void:
	if hud_container.shows_the_bare_menu(): ($Content/Play as Button).grab_focus()

func _on_play_pressed() -> void:
	play_row.visible = not play_row.visible

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
	var viewer := DeckViewer.show_deck(hud_container.get_parent(), cards, inspect,
			&"viewer_inspect")
	if viewer == null: return
	hud_container.host_viewer(viewer, info_requested, HudContainer.MENU_SCREEN)
	picker.tree_exiting.connect(viewer.queue_free)

## Continue is only clickable while a resumable run exists on disk, re-read each time any screen becomes the one shown.
func refresh_continue() -> void:
	HudContainer.hold(continue_button, not RunManager.has_save())
