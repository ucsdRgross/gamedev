class_name WallOverlay
extends CanvasLayer
## The persistent Back/Forward/Wall row, on its own CanvasLayer so it never rides the wall camera.

# ⚠ TOP-LEFT, NEVER THE BOTTOM: there the row would cover the start menu's Profile/Options and the
# map's Deck button. It owns no navigation state: it reports presses and reflects a `FocusStack`.

## Emitted when the corresponding control is pressed. `Main` consumes all three.
signal back_pressed
signal forward_pressed
signal wall_pressed

## A second-button press landed on one of this layer's controls; `Wall` routes it, because they must not swallow cancel.
signal second_button_pressed(event: InputEventMouseButton)

@onready var _back_button : Button = %BackButton
@onready var _forward_button : Button = %ForwardButton
@onready var _wall_button : Button = %WallButton
@onready var _authored_size : Vector2 = _back_button.size

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

# GROWS the AUTHORED row to the touch target, keeping each button's authored top-left and gap; the
# minimum goes first, as `size` is clamped to the last one. ⚠ The minimum alone resizes a manually
# placed Control only at the deferred layout pass, so `size` is set too for a read after `_ready()`.
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
	button.custom_minimum_size = Vector2(maxf(_authored_size.x, target), maxf(_authored_size.y, target))
	button.size = button.custom_minimum_size

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

# THE ONE ANNOUNCE FOR EVERY CONTROL ON THIS LAYER -- the button row and the sidebar container alike.
# Cancel is reachable from anywhere on screen, so the second button is read here, ahead of the GUI
# pass that would hand it to whichever control sits under the pointer and stop there.

# Each control is asked for its OWN rect: the band must not depend on the container's covering it.
func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if not button or button.button_index != MOUSE_BUTTON_RIGHT or not button.pressed: return
	for child : Node in get_children():
		var control := child as Control
		if control and control.is_visible_in_tree() and control.get_global_rect().has_point(
				control.get_canvas_transform().affine_inverse() * button.position):
			second_button_pressed.emit(button)
			return
