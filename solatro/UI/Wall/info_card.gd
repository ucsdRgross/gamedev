class_name InfoCard
extends Control
## The self-sizing notecard, anchored to the bottom of the WINDOW in screen space, over the wall.
## The anchor presets live on the scene; this script owns content and sizing only.
##
## Shows NOTHING until the first `show_entry()`, then keeps showing that same entry across any
## number of "stopped hovering" gaps — there is no "hover nothing" method, so the caller simply
## stops calling and the card does not react — until `reset()` hides it again.

signal info_shown(entry: InfoEntry)

## The most of the card's width a visual may take, leaving the rest for the text beside it.
const _VISUAL_MAX_WIDTH_SHARE := 0.5

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
		_make_inert(entry.visual)
	_resize_to_content()
	visible = true
	info_shown.emit(entry)

## ⚠ **THE VISUAL IS A READ-ONLY PICTURE OF THE THING, AND THIS IS WHAT GUARANTEES IT.**
##
## An entry's visual is a REAL game node — a preview `ControlCard` with a live `CardVisual`, or a
## `TextureRect` mirroring a picture's own `SubViewport`. Real, because a stand-in would show
## something the game does not. But real also means it arrives interactive: `ControlCard._ready()`
## sets `focus_mode = FOCUS_ALL`, so it becomes a focus stop that controller navigation can land on
## and steal focus from the board; and any `Control` defaults to `MOUSE_FILTER_STOP`, so it would
## swallow clicks aimed at whatever is behind the card.
##
## Every visual is therefore stripped of both, recursively, the moment this card takes it. What
## survives is drawing and idle animation, which is why the card still floats.
##
## ⚠ This is the ONE place it can be done safely — every entry passes through here, so a new
## `get_info()` somewhere else cannot forget. Doing it in each builder instead would be a rule that
## has to be remembered N times.
##
## Note the visual only ever DRAWS: `CardVisual` never writes to its `CardData` (it reads
## `CardEnvironment` for timing and nothing else), so a preview cannot mutate the card it shows.
func _make_inert(node: Node) -> void:
	var control := node as Control
	if control:
		control.focus_mode = Control.FOCUS_NONE
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child : Node in node.get_children():
		_make_inert(child)

## Hands the current entry back and stops owning it: the visual is DETACHED, not freed, so the
## entry can be shown again later.
##
## ⚠ The caller then owns `entry.visual` — a Node outside the tree that nothing else will free. It
## must either `show_entry()` it again or free it. This exists so a screen can be left and returned
## to with the card it had, which `reset()` cannot do because it frees.
func detach_entry() -> InfoEntry:
	var entry := current_entry
	if entry and entry.visual and is_instance_valid(entry.visual):
		if entry.visual.get_parent() == _visual_slot:
			_visual_slot.remove_child(entry.visual)
	current_entry = null
	visible = false
	return entry

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
	var visual_size := _visual_size(width)
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

## How much room the visual beside the text needs.
##
## ⚠ **MEASURED FROM THE SLOT'S CHILDREN, NOT FROM THE SLOT.** A container's own
## `get_combined_minimum_size()` is recomputed on a DEFERRED pass, so immediately after
## `add_child()` it still reports the previous entry's size — zero for the first entry of a
## session. The text was then measured at the FULL card width while actually laid out in the
## narrower column beside the visual: too few lines predicted, so the card came out too short and
## scrolled, and the text read as compressed. It corrected itself on the next entry, which is the
## signature of a deferred value being read too early.
func _visual_size(card_width: float) -> Vector2:
	var out := Vector2.ZERO
	for child : Node in _visual_slot.get_children():
		var control := child as Control
		if control == null: continue
		# ⚠ MINIMUM SIZE ONLY, never `size`. A Control's `size` before its first layout pass is
		# whatever it happens to hold — for a freshly added `ControlCard`, wider than this whole
		# card. Taking the max of the two made `text_width` collapse to its 1px floor, so the body
		# wrapped to ONE LETTER PER ROW, which then made the card max-height tall and the info pose
		# zoom right out to make room for it.
		var needed := control.get_combined_minimum_size()
		out = Vector2(out.x + needed.x, maxf(out.y, needed.y))
	# ⚠ AND A HARD CEILING. Whatever a visual asks for, the text keeps at least half the card —
	# no visual is worth leaving no room to read beside it, and this makes the one-letter-per-row
	# failure unreachable rather than merely fixed at its one known cause.
	out.x = minf(out.x, card_width * _VISUAL_MAX_WIDTH_SHARE)
	return out

## Bottom-centred against the CURRENT window, growing UPWARD as content gets taller: the bottom
## edge stays on `window.y` and only the top edge moves. Separate from `_resize_to_content()` so a
## window resize can re-anchor without recomputing font metrics — the card's SIZE comes from its
## content and two knobs, never from the window.
func _reposition_to_window() -> void:
	var window := get_viewport_rect().size
	position = Vector2((window.x - size.x) * 0.5, window.y - size.y)
