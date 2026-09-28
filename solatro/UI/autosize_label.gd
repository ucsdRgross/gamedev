class_name AutosizeLabel
extends Label

@export var autosize_on: bool = true
@export var use_default_font_size: bool = true
@export var font_size_override: int = -1
@export var font_size_min: int = 8
@export var font_size_max: int = 100
@export var font_size_width_percent: float = 0.9

var _current_font_size: int
var _default_font_size: int

func _ready() -> void:
	resized.connect(_on_resized)
	_initialize_default_font_size()
	_update_font_size()

func _initialize_default_font_size() -> void:
	_default_font_size = get_theme_font_size("font_size")
	if use_default_font_size:
		font_size_max = _default_font_size

func _on_resized() -> void:
	_update_font_size()

func _update_font_size() -> void:
	if not autosize_on:
		return

	if font_size_override >= 0:
		_current_font_size = font_size_override
	else:
		_current_font_size = _calculate_best_font_size(size)

	add_theme_font_size_override("font_size", _current_font_size)

# ⚠ MEASURED AGAINST `custom_minimum_size`, NOT `size`: a label is never shorter than its own font,
# so a size that already overflows the box inflates `size` to fit and then passes its own test.
# Asking must not depend on the answer, or a group sharing one font never shrinks it.

## The size this label WOULD choose for its minimum box and its text right now.
func best_font_size() -> int:
	return _calculate_best_font_size(custom_minimum_size)

# Used where a GROUP of labels has to read as one set rather than each fitting its own box.
## Force one size on this label, overriding the autosize; -1 hands it back.
func force_font_size(px: int) -> void:
	if font_size_override == px: return
	font_size_override = px
	_update_font_size()

# The largest size that fits, by binary search since fit is monotonic in size: ~7 string
# measurements instead of one per size stepping down, and this runs on every resize.
func _calculate_best_font_size(box: Vector2) -> int:
	var available_width := box.x * font_size_width_percent
	var available_height := box.y

	var font := get_theme_font("font")
	var lo := font_size_min
	var hi := font_size_max
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, mid)
		if text_size.x <= available_width and text_size.y <= available_height:
			lo = mid
		else:
			hi = mid - 1

	return max(font_size_min, min(font_size_max, lo))
