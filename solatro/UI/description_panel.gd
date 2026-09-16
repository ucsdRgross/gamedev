class_name DescriptionPanel
extends Control
## The description's contents: the name beside the thing's own visual, then the body, scrolled.

@onready var _scroll : ScrollContainer = %Scroll
@onready var _content : VBoxContainer = %Content
@onready var _visual_slot : HBoxContainer = %VisualSlot
@onready var _grid_slot : VBoxContainer = %GridSlot
@onready var _title_label : Label = %Title
@onready var _body_label : Label = %Body
@onready var _back_button : Button = %Back

## Godot's own mouse wheel steps an eighth of a page per notch, so a key or a stick meaning "a nudge" moves by the same step.
const WHEEL_STEP_PAGES := 0.125

## A card listed in the mounted grid was pointed at, focused or tapped -- what the sidebar shows switches to that card.
signal preview_card_picked(data: CardData, card_px: Vector2)

## The entry on screen, or null before the first `show_entry()`. Public so a caller can check WHICH entry shows, by identity.
var current_entry : InfoEntry = null

# HOW FAR THE PANEL IS SCROLLED, so a caller taking an entry away can put it back where its reader
# left it. ⚠ The bar's range is the LAYOUT's answer and the layout is a frame away, so the restore
# writes the content height `resize_to()` already computed -- what the next sort writes here anyway.
var scroll_position : int:
	get: return _scroll.scroll_vertical
	set(value):
		_scroll.get_v_scroll_bar().max_value = _content.custom_minimum_size.y
		_scroll.scroll_vertical = value

## Fills the panel from `entry` and lays it out inside `panel_size` -- `HudContainer` passes its own `container_rect()`'s size.
func show_entry(entry: InfoEntry, panel_size: Vector2) -> void:
	current_entry = entry
	_title_label.text = entry.title
	_body_label.text = entry.body
	_mount_visual(entry.visual)
	resize_to(panel_size)
	_scroll.scroll_vertical = 0
	visible = true

## The sub-pixel part of a scroll, carried to the next call -- the scroll position itself is whole pixels.
var _scroll_remainder : float = 0.0

# ⚠ THE REMAINDER IS WHAT MAKES A SLOW SCROLL MOVE AT ALL: a gentle stick on a short panel asks for
# a fraction of a pixel per frame, and rounding each frame on its own would throw every one away.
func scroll_by_pages(pages: float) -> void:
	var exact := pages * _scroll.size.y + _scroll_remainder
	var whole := roundi(exact)
	_scroll_remainder = exact - whole
	_scroll.scroll_vertical += whole

## Whether the description is scrolled to its own top, where an up press has nothing left to move.
func at_top() -> bool:
	return _scroll.scroll_vertical == 0

# A preview that changed size took the top row's height with it, so the content is re-laid after
# it. Nothing mounted is the ordinary case: the board publishes its card size on every rect change,
# HUD or description, and an entry showing no card of its own (the map's) re-draws nothing.
func resize_preview(card_px: Vector2) -> void:
	if current_entry == null: return
	for card : ControlCard in _visual_slot.find_children("*", "ControlCard", true, false):
		card.size_preview_to(card_px)
	resize_to(size)

## Hands the visual back OUT without freeing it, so the screen this description belongs to can be returned to.
func detach_entry() -> void:
	if current_entry == null: return
	var visual := current_entry.visual
	if visual:
		_unmake_grid_pickable(visual)
		_slot_for(visual).remove_child(visual)
	current_entry = null

# ⚠ THE PANEL OWNS WHATEVER IS MOUNTED and frees it when another entry replaces it. A caller that
# still needs its visual takes it back through `detach_entry()` first. It leaves the tree FIRST: a
# queue-freed child is still a child until the frame ends, and this entry is measured before then.
func _mount_visual(visual: Node) -> void:
	for slot : Container in [_visual_slot, _grid_slot] as Array[Container]:
		for child : Node in slot.get_children():
			slot.remove_child(child)
			child.queue_free()
	if visual == null: return
	_slot_for(visual).add_child(visual)
	_make_still(visual)
	_make_grid_pickable(visual)

# ⚠ A WRAPPING GRID OF MANY NEEDS THE WHOLE WIDTH, so it cannot sit in the top row beside the
# name: a flowing visual goes below the body instead, and scrolls with it.
func _slot_for(visual: Node) -> Container:
	return _grid_slot if visual is FlowContainer else _visual_slot

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

# ⚠ THE ONE EXCEPTION TO THE STILLNESS ABOVE: a GRID IS A LIST TO PICK FROM, so every card it lists
# takes the pointer, the pad and a finger back. What is drawn inside one stays inert, and a visual
# that is not a grid stays inert whole.
func _make_grid_pickable(visual: Node) -> void:
	for card : ControlCard in _listed_cards(visual):
		card.focus_mode = Control.FOCUS_ALL
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_entered.connect(_pick_preview_card.bind(card))
		card.focus_entered.connect(_pick_preview_card.bind(card))

# A DETACHED GRID IS MOUNTED AGAIN when the panel is taken back to it, and Godot refuses a second
# identical connection, so the picks leave with the grid.
func _unmake_grid_pickable(visual: Node) -> void:
	for card : ControlCard in _listed_cards(visual):
		card.mouse_entered.disconnect(_pick_preview_card.bind(card))
		card.focus_entered.disconnect(_pick_preview_card.bind(card))

## The cards a mounted grid lists -- a visual that is not a grid lists none.
func _listed_cards(visual: Node) -> Array[Node]:
	if visual is not FlowContainer: return []
	return visual.find_children("*", "ControlCard", true, false)

func _pick_preview_card(card: ControlCard) -> void:
	preview_card_picked.emit(card.child.data, card.child.card_size)

# The CONTENT's height is computed synchronously, so a caller reading straight after `show_entry()`
# never sees the last entry's layout. ⚠ THE SCROLL'S SIDEWAYS BAR IS NEVER SHOWN, NOT DISABLED: a
# disabled one makes the grid's width the scroll's minimum, which shoves it left off the panel.
func resize_to(panel_size: Vector2) -> void:
	size = panel_size
	_scroll.size = panel_size
	_grid_slot.size.x = panel_size.x
	_grid_slot.custom_minimum_size.x = panel_size.x
	var content_h := _top_row_height(panel_size.x) + _text_height(_body_label, panel_size.x)
	content_h += _grid_slot.get_combined_minimum_size().y
	_content.size = Vector2(panel_size.x, content_h)
	_content.custom_minimum_size.y = content_h

# The name sits BESIDE the visual and the way back, so that row is as tall as the tallest of them.
# An entry with no visual of its own leaves the slot empty, a way back that is down measures
# nothing, and a flowing visual sits below the row instead.
func _top_row_height(width: float) -> float:
	var flanking := maxf(_visual_slot.get_combined_minimum_size().y,
			_back_button.get_combined_minimum_size().y if _back_button.visible else 0.0)
	return maxf(flanking, _text_height(_title_label, width))

## How tall `label`'s text wraps to at `width`, from font metrics -- Godot's own layout pass has not run yet.
static func _text_height(label: Label, width: float) -> float:
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	return font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
