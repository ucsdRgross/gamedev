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
		_current_font_size = _calculate_best_font_size()

	add_theme_font_size_override("font_size", _current_font_size)

func _calculate_best_font_size() -> int:
	var available_width := size.x * font_size_width_percent
	var available_height := size.y

	var font := get_theme_font("font")
	# Largest size that fits (fit is monotonic in size): binary search, ~7 string
	# measurements instead of one per size stepping down — this runs on every resize.
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
