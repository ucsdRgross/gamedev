class_name DescriptionPanel
extends Control
## The description's contents: the name beside the thing's own visual, then the body, scrolled.

@onready var _scroll : ScrollContainer = %Scroll
@onready var _content : VBoxContainer = %Content
@onready var _visual_slot : HBoxContainer = %VisualSlot
@onready var _title_label : Label = %Title
@onready var _body_label : Label = %Body

## The entry on screen, or null before the first `show_entry()`. Public so a caller can check WHICH entry shows, by identity.
var current_entry : InfoEntry = null

## Fills the panel from `entry` and lays it out inside `panel_size` -- `HudContainer` passes its own `container_rect()`'s size.
func show_entry(entry: InfoEntry, panel_size: Vector2) -> void:
	current_entry = entry
	_title_label.text = entry.title
	_body_label.text = entry.body
	_mount_visual(entry.visual)
	resize_to(panel_size)
	visible = true

## Hands the visual back OUT without freeing it, so the screen this description belongs to can be returned to.
func detach_entry() -> void:
	if current_entry == null: return
	var visual := current_entry.visual
	if visual: _visual_slot.remove_child(visual)
	current_entry = null

# ⚠ THE PANEL OWNS WHATEVER IS MOUNTED and frees it when another entry replaces it. A caller that
# still needs its visual takes it back through `detach_entry()` first.
func _mount_visual(visual: Node) -> void:
	for child : Node in _visual_slot.get_children():
		child.queue_free()
	if visual == null: return
	_visual_slot.add_child(visual)
	_make_still(visual)

# ⚠ A VISUAL IS A REAL GAME NODE, so it arrives focusable, mouse-hungry and idling: it would steal
# pad focus from the board, swallow clicks aimed behind it, and float while it is being read. The
# reading surface is calm and inert instead, recursively, the moment the panel takes it.
func _make_still(node: Node) -> void:
	var control := node as Control
	if control:
		control.focus_mode = Control.FOCUS_NONE
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := node as ControlCard
	if card and card.child: card.child.floating = false
	for child : Node in node.get_children():
		_make_still(child)

# The panel's own height is the container's, so only the CONTENT's height is computed here, and
# synchronously: a caller reading the panel straight after `show_entry()` must not see the layout
# pass's leftovers from the previous entry. Called again on every resize, with the same entry up.
func resize_to(panel_size: Vector2) -> void:
	size = panel_size
	_scroll.size = panel_size
	var content_h := _top_row_height(panel_size.x) + _text_height(_body_label, panel_size.x)
	_content.size = Vector2(panel_size.x, content_h)
	_content.custom_minimum_size.y = content_h

# The name sits BESIDE the visual, so that row is as tall as the taller of the two.
func _top_row_height(width: float) -> float:
	return maxf(_visual_height(), _text_height(_title_label, width))

## The visual's own height, or none when the entry brought no visual -- `InfoEntry.visual` is optional.
func _visual_height() -> float:
	var control := current_entry.visual as Control
	if control == null: return 0.0
	return control.get_combined_minimum_size().y

## How tall `label`'s text wraps to at `width`, from font metrics -- Godot's own layout pass has not run yet.
static func _text_height(label: Label, width: float) -> float:
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	return font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
