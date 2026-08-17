class_name InfoCard
extends Control
## The self-sizing notecard (PLAN.md §1.11; NAMES.md; DESIGN.md flowchart J). Anchored to the
## bottom of the WINDOW in screen space, on top of the wall (Q129=a) -- this control's own anchor
## presets are set on the scene, not computed here; this script owns content and sizing only.
##
## J5/J6 (DESIGN.md): shows NOTHING until the first `show_entry()`, then keeps showing that same
## entry across any number of "stopped hovering" gaps (there is no "hover nothing" method at all --
## the caller simply stops calling `show_entry()`, and the card does not react to that absence),
## until `reset()` (leaving info mode) hides it again.

signal info_shown(entry: InfoEntry)

@onready var _title_label : Label = %Title
@onready var _body_label : Label = %Body
@onready var _visual_slot : Control = %VisualSlot
@onready var _scroll : ScrollContainer = %Scroll

## The entry currently on screen, or null before the first `show_entry()`/after `reset()`. Exposed
## (not `_`-prefixed) so a caller/test can read WHICH entry is showing, not merely THAT one is --
## J2's own trap: "still shown" must be checked by identity, not just visibility (HANDOFF traps).
var current_entry : InfoEntry = null

func _ready() -> void:
	visible = false

## J1/J5: populates title/body/visual and grows the card to fit them (J4/Q130), then shows it.
## Q130: "shows a copy of the hovered item as a visual beside the description" -- `entry.visual`,
## if present, is REPARENTED into `%VisualSlot` (this card takes ownership of it for as long as it
## is the current entry; a later `show_entry()`/`reset()` frees whatever was there before, so a
## caller must hand over a visual it is fine losing, never one it still needs elsewhere).
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

## J6 (DESIGN.md): leaving info mode resets the card to nothing -- hides it AND drops the
## remembered entry, so a stray `current_entry` read afterward cannot look like it is still shown.
func reset() -> void:
	current_entry = null
	for child : Node in _visual_slot.get_children():
		child.queue_free()
	visible = false

## J4/Q130 (self-sizing, "so each one reads as unique") + J12/Q140-override (scrolls upward past
## `wall_info_card_max_height` instead of growing further, text never shrinks). Computed
## SYNCHRONOUSLY from font metrics rather than left to Godot's own deferred container-layout pass
## (which does not settle until the next idle/frame) -- a caller/test reading `size` immediately
## after `show_entry()` must see the real, final size, not a stale one from before this call.
func _resize_to_content() -> void:
	var width : float = SettingsManager.settings.wall_info_card_width
	var max_height : float = SettingsManager.settings.wall_info_card_max_height
	var title_font := _title_label.get_theme_font(&"font")
	var title_font_size := _title_label.get_theme_font_size(&"font_size")
	var body_font := _body_label.get_theme_font(&"font")
	var body_font_size := _body_label.get_theme_font_size(&"font_size")
	var title_h := title_font.get_multiline_string_size(_title_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, width, title_font_size).y
	var body_h := body_font.get_multiline_string_size(_body_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, width, body_font_size).y
	var content_h := title_h + body_h
	var card_h := minf(content_h, max_height)
	# ⚠ `custom_minimum_size` alone does NOT make a `layout_mode=0` (manual position/size) Control
	# actually resize -- that only happens on Godot's own next deferred container-layout pass,
	# which has not necessarily run by the time a caller reads `size` immediately after this call
	# (measured directly: labels wrapped to one character per line the first time this shipped,
	# because `_scroll`'s REAL `size` was still whatever tiny default it started at). `.size` is
	# set explicitly, at every level down to the labels themselves, so nothing here depends on a
	# deferred pass ever running.
	size = Vector2(width, card_h)
	custom_minimum_size = size
	_scroll.size = Vector2(width, card_h)
	_scroll.custom_minimum_size = Vector2(width, card_h)
	_title_label.custom_minimum_size.x = width
	_body_label.custom_minimum_size.x = width
	# Q129=a: anchored to the bottom of the WINDOW, centred horizontally. Grows UPWARD as content
	# gets taller (J12: "scrolls upward over the whole picture") -- the bottom edge stays fixed at
	# `window.y`, only the top edge (`window.y - card_h`) moves as `card_h` changes, never the
	# reverse. Recomputed every `show_entry()`, not just once, since a different entry can be a
	# different height (this IS J4's own effect: differing content -> differing on-screen size).
	var window := get_viewport_rect().size
	position = Vector2((window.x - width) * 0.5, window.y - card_h)
