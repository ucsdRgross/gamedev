class_name InfoCard
extends Control
## The self-sizing notecard, anchored to the bottom of the WINDOW in screen space, over the wall.
## The anchor presets live on the scene; this script owns content and sizing only.
##
## Shows NOTHING until the first `show_entry()`, then keeps showing that same entry across any
## number of "stopped hovering" gaps — there is no "hover nothing" method, so the caller simply
## stops calling and the card does not react — until `reset()` hides it again.

signal info_shown(entry: InfoEntry)

@onready var _title_label : Label = %Title
@onready var _body_label : Label = %Body
@onready var _visual_slot : Control = %VisualSlot
@onready var _scroll : ScrollContainer = %Scroll

## The entry currently on screen, or null before the first `show_entry()` and after `reset()`.
## Public so a caller can check WHICH entry is showing by identity, not merely that one is.
var current_entry : InfoEntry = null

func _ready() -> void:
	visible = false
	# The card is anchored to the WINDOW, so it must re-anchor on every resize — recomputing only
	# inside `show_entry()` would leave it wherever the window used to be, and a shrink would put
	# it off the bottom edge while Info mode still reported it shown. Nothing listens on its
	# behalf: `Main._on_window_resized()` re-packs the WALL and never touches the overlay.
	get_viewport().size_changed.connect(_reposition_to_window)

## Populates title/body/visual, grows the card to fit, and shows it.
## ⚠ `entry.visual` is REPARENTED into `%VisualSlot` and this card then OWNS it: the next
## `show_entry()` or `reset()` frees it. Hand over a visual you are fine losing, never one still
## needed elsewhere.
func show_entry(entry: InfoEntry) -> void:
	current_entry = entry
	_title_label.text = entry.title
	_body_label.text = entry.body
	for child : Node in _visual_slot.get_children():
		child.queue_free()
	if entry.visual:
		_visual_slot.add_child(entry.visual)
	_resize_to_content()
	visible = true
	info_shown.emit(entry)

## Resets the card to nothing: hides it AND drops the remembered entry, so a later
## `current_entry` read cannot look like something is still shown.
func reset() -> void:
	current_entry = null
	for child : Node in _visual_slot.get_children():
		child.queue_free()
	visible = false

## Sizes the card to its content, scrolling past `wall_info_card_max_height` rather than growing
## further; the text never shrinks. Computed SYNCHRONOUSLY from font metrics rather than left to
## Godot's deferred container-layout pass, which does not settle until the next frame — a caller
## reading `size` straight after `show_entry()` must see the final size.
func _resize_to_content() -> void:
	var width : float = WallPicture.settings().wall_info_card_width
	var max_height : float = WallPicture.settings().wall_info_card_max_height
	var title_font := _title_label.get_theme_font(&"font")
	var title_font_size := _title_label.get_theme_font_size(&"font_size")
	var body_font := _body_label.get_theme_font(&"font")
	var body_font_size := _body_label.get_theme_font_size(&"font_size")
	# ⚠ THE VISUAL SITS BESIDE THE TEXT, NOT ABOVE IT (`%VisualSlot` and the title/body `VBox` share
	# one `HBoxContainer`). Two things follow, and missing either makes the card scroll content it
	# had room to show:
	#  * the text column is only what the visual leaves, so measuring at the full card width
	#    UNDER-estimates how many lines the body wraps to;
	#  * the card is as tall as the TALLER column, so a short caption beside a preview image is
	#    still as tall as the image.
	var visual_size := _visual_slot.get_combined_minimum_size()
	var text_width := maxf(width - visual_size.x, 1.0)
	var title_h := title_font.get_multiline_string_size(_title_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, text_width, title_font_size).y
	var body_h := body_font.get_multiline_string_size(_body_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, text_width, body_font_size).y
	var content_h := maxf(title_h + body_h, visual_size.y)
	var card_h := minf(content_h, max_height)
	# ⚠ `custom_minimum_size` alone does NOT resize a `layout_mode=0` Control; that waits for
	# Godot's next deferred layout pass, which has not necessarily run when a caller reads `size`
	# straight after this call — leaving `_scroll` at its tiny default and wrapping labels to one
	# character per line. `.size` is set explicitly at every level down to the labels, so nothing
	# here depends on a deferred pass running.
	size = Vector2(width, card_h)
	custom_minimum_size = size
	_scroll.size = Vector2(width, card_h)
	_scroll.custom_minimum_size = Vector2(width, card_h)
	_title_label.custom_minimum_size.x = text_width
	_body_label.custom_minimum_size.x = text_width
	# Re-anchor: a different entry is a different height, so this runs on every `show_entry()`.
	_reposition_to_window()

## Bottom-centred against the CURRENT window, growing UPWARD as content gets taller: the bottom
## edge stays on `window.y` and only the top edge moves. Separate from `_resize_to_content()` so a
## window resize can re-anchor without recomputing font metrics — the card's SIZE comes from its
## content and two knobs, never from the window.
func _reposition_to_window() -> void:
	var window := get_viewport_rect().size
	position = Vector2((window.x - size.x) * 0.5, window.y - size.y)
