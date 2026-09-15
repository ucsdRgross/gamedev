class_name WallOverlay
extends CanvasLayer
## The persistent Back/Forward/Wall row, on its own CanvasLayer so it never rides the wall camera.

# ⚠ TOP-LEFT, NEVER THE BOTTOM: there the row would cover the start menu's Profile/Options and the
# map's Deck button. It owns no navigation state: it reports presses and reflects a `FocusStack`.

## Emitted when the corresponding control is pressed. `Main` consumes all three.
signal back_pressed
signal forward_pressed
signal wall_pressed

@onready var _back_button : Button = %BackButton
@onready var _forward_button : Button = %ForwardButton
@onready var _wall_button : Button = %WallButton

## Localises every label (never a literal string), wires each control to its signal, and re-grows the row on every resize.
func _ready() -> void:
	_back_button.text = TRANSLATION.find('WALL_BACK')
	_forward_button.text = TRANSLATION.find('WALL_FORWARD')
	_wall_button.text = TRANSLATION.find('WALL_OVERVIEW')
	_back_button.pressed.connect(_on_back_pressed)
	_forward_button.pressed.connect(_on_forward_pressed)
	_wall_button.pressed.connect(_on_wall_pressed)
	_apply_touch_targets()
	get_viewport().size_changed.connect(_apply_touch_targets)

# GROWS the authored row to the touch target, keeping each button's authored top-left and gap.
# ⚠ `custom_minimum_size` alone does not resize a manually positioned Control until the deferred
# layout pass, so `size` is set too and a caller reading it straight after `_ready()` sees the real one.
func _apply_touch_targets() -> void:
	var target := WallInput.touch_target_px(get_viewport().get_visible_rect().size,
			WallPicture.settings())
	var row : Array[Button] = [_back_button, _forward_button, _wall_button]
	var gap := row[1].position.x - (row[0].position.x + row[0].size.x)
	var x := row[0].position.x
	for button : Button in row:
		_grow_to(button, target)
		button.position.x = x
		x += button.size.x + gap

func _grow_to(button: Button, target: float) -> void:
	button.size = Vector2(maxf(button.size.x, target), maxf(button.size.y, target))
	button.custom_minimum_size = button.size

# Back and Forward VISIBLY disable rather than doing nothing; Wall hides with one picture or fewer.
# ⚠ In wall view Back returns to the stack's top, so it is live while the stack has ANY entry --
# `can_back()` alone greys it out on cold launch -> Escape while Escape and pad Back still work.
func refresh(stack: FocusStack, picture_count: int = 2, in_wall_view: bool = false) -> void:
	_back_button.disabled = not (stack.current() != &"" if in_wall_view else stack.can_back())
	_forward_button.disabled = not stack.can_forward()
	_wall_button.visible = picture_count > 1

## The grown row's bottom edge, read off the buttons themselves rather than re-typed elsewhere.
func button_band_bottom() -> float:
	return maxf(_back_button.position.y + _back_button.size.y,
			maxf(_forward_button.position.y + _forward_button.size.y,
					_wall_button.position.y + _wall_button.size.y))

## The row's authored gap from the window's edge, which the container's content keeps from its own edges.
func button_band_inset() -> float:
	return _back_button.position.x

func _on_back_pressed() -> void:
	back_pressed.emit()

func _on_forward_pressed() -> void:
	forward_pressed.emit()

func _on_wall_pressed() -> void:
	wall_pressed.emit()
